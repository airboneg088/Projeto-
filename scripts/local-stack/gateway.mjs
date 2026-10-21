#!/usr/bin/env node
// Gateway HTTP da stack local (sem dependências), no papel do Kong do Supabase:
//   /auth/v1/*    -> GoTrue    (127.0.0.1:54331), prefixo removido
//   /rest/v1/*    -> PostgREST (127.0.0.1:54330), prefixo removido
//   /storage/v1/* -> 501 (storage-api não roda localmente; policies testadas em SQL)
//   /health       -> saúde do gateway e dos serviços
//   /email-templates/supabase/templates/* -> arquivos de template de e-mail para o GoTrue
//
// Comportamento do Kong reproduzido:
//   - exige `apikey` (header ou ?apikey=) igual à chave anon ou service_role, exceto nas rotas
//     abertas do auth (verify, callback, authorize, jwks);
//   - sem header Authorization, envia `Authorization: Bearer <apikey>` ao serviço;
//   - CORS para o app local (http://localhost:3000).

import { createReadStream, existsSync, statSync } from "node:fs";
import http from "node:http";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { localKeys } from "./gen-keys.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const templatesDir = join(root, "supabase", "templates");

const PORT = Number(process.env.GATEWAY_PORT || 54321);
const HOST = "127.0.0.1";
const UPSTREAMS = {
  auth: { host: "127.0.0.1", port: Number(process.env.AUTH_PORT || 54331) },
  rest: { host: "127.0.0.1", port: Number(process.env.REST_PORT || 54330) },
};
const REST_ADMIN_PORT = Number(process.env.REST_ADMIN_PORT || 54332);

const keys = localKeys();
const VALID_KEYS = new Set([keys.anon, keys.service_role]);

const ALLOWED_ORIGINS = new Set(
  ["http://localhost:3000", "http://127.0.0.1:3000", process.env.SITE_URL].filter(Boolean),
);

// Rotas do auth que o Kong do Supabase deixa sem apikey (links de e-mail, OAuth)
const OPEN_AUTH_PATHS = [
  /^\/verify\/?$/,
  /^\/callback\/?$/,
  /^\/authorize\/?$/,
  /^\/\.well-known\/jwks\.json$/,
];

function corsHeaders(req) {
  const origin = req.headers.origin;
  if (!origin || !ALLOWED_ORIGINS.has(origin)) return {};
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-credentials": "true",
    "access-control-expose-headers":
      "Content-Range, Content-Profile, Content-Location, Preference-Applied, Range-Unit, X-Total-Count, X-Supabase-Api-Version",
    vary: "Origin",
  };
}

function sendJson(req, res, status, body, extra = {}) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
    ...corsHeaders(req),
    ...extra,
  });
  res.end(payload);
}

function probe(port, path) {
  return new Promise((resolveProbe) => {
    const r = http.get({ host: "127.0.0.1", port, path, timeout: 2000 }, (resp) => {
      resp.resume();
      resolveProbe(resp.statusCode >= 200 && resp.statusCode < 300);
    });
    r.on("timeout", () => r.destroy());
    r.on("error", () => resolveProbe(false));
  });
}

function proxy(req, res, upstream, path) {
  const headers = { ...req.headers };
  delete headers.host;
  delete headers.connection;
  if (!headers.authorization && headers.apikey) headers.authorization = `Bearer ${headers.apikey}`;
  const remote = req.socket.remoteAddress || "127.0.0.1";
  headers["x-forwarded-for"] = headers["x-forwarded-for"]
    ? `${headers["x-forwarded-for"]}, ${remote}`
    : remote;
  headers["x-forwarded-host"] = req.headers.host || `${HOST}:${PORT}`;
  headers["x-forwarded-proto"] = "http";
  headers["x-forwarded-port"] = String(PORT);

  const upstreamReq = http.request(
    {
      host: upstream.host,
      port: upstream.port,
      method: req.method,
      path,
      headers: { ...headers, host: `${upstream.host}:${upstream.port}` },
    },
    (upstreamRes) => {
      const outHeaders = { ...upstreamRes.headers, ...corsHeaders(req) };
      res.writeHead(upstreamRes.statusCode || 502, outHeaders);
      upstreamRes.pipe(res);
    },
  );
  upstreamReq.on("error", (err) => {
    if (!res.headersSent) {
      sendJson(req, res, 502, {
        message: "Serviço local indisponível. Rode `pnpm stack:up`.",
        detail: err.code || String(err),
      });
    } else {
      res.destroy();
    }
  });
  req.pipe(upstreamReq);
}

function serveTemplate(req, res, relPath) {
  const abs = resolve(root, relPath);
  if (!abs.startsWith(templatesDir + sep) || !existsSync(abs) || !statSync(abs).isFile()) {
    return sendJson(req, res, 404, { message: "template não encontrado" });
  }
  res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
  createReadStream(abs).pipe(res);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", `http://${HOST}:${PORT}`);
  const pathname = url.pathname;

  // Preflight CORS (como o plugin cors do Kong, antes da checagem de chave)
  if (req.method === "OPTIONS") {
    const cors = corsHeaders(req);
    res.writeHead(204, {
      ...cors,
      "access-control-allow-methods": "GET, HEAD, PUT, PATCH, POST, DELETE, OPTIONS",
      "access-control-allow-headers":
        req.headers["access-control-request-headers"] ||
        "authorization, x-client-info, apikey, content-type, prefer, range, accept-profile, content-profile, x-upsert",
      "access-control-max-age": "3600",
    });
    return res.end();
  }

  if (pathname === "/health") {
    const [auth, rest] = await Promise.all([
      probe(UPSTREAMS.auth.port, "/health"),
      probe(REST_ADMIN_PORT, "/ready"),
    ]);
    return sendJson(req, res, 200, {
      gateway: "ok",
      auth: auth ? "ok" : "down",
      rest: rest ? "ok" : "down",
    });
  }

  if (pathname.startsWith("/email-templates/")) {
    return serveTemplate(req, res, decodeURIComponent(pathname.slice("/email-templates/".length)));
  }

  const match = /^\/(auth|rest|storage)\/v1(\/.*)?$/.exec(pathname);
  if (!match) return sendJson(req, res, 404, { message: "no Route matched with those values" });
  const service = match[1];
  const subpath = match[2] || "/";

  if (service === "storage") {
    return sendJson(req, res, 501, {
      statusCode: "501",
      error: "Not Implemented",
      message:
        "O storage-api não roda na stack local. As policies de storage são testadas em SQL (ver docs/dev-local.md).",
    });
  }

  const isOpen = service === "auth" && OPEN_AUTH_PATHS.some((re) => re.test(subpath));
  if (!isOpen) {
    const apikey = req.headers.apikey || url.searchParams.get("apikey");
    if (!apikey) {
      return sendJson(req, res, 401, {
        message: "No API key found in request",
        hint: "Envie o header apikey com a chave publishable (anon) ou secreta.",
      });
    }
    if (!VALID_KEYS.has(String(apikey)))
      return sendJson(req, res, 401, { message: "Invalid API key" });
    if (!req.headers.apikey) req.headers.apikey = String(apikey);
  }

  // Repassa a query string original (sem reescrever a codificação), tirando só o ?apikey=
  const rawUrl = req.url || "/";
  const q = rawUrl.indexOf("?");
  const query =
    q >= 0
      ? rawUrl
          .slice(q + 1)
          .split("&")
          .filter((part) => part && !part.startsWith("apikey="))
          .join("&")
      : "";
  const rawPath = (q >= 0 ? rawUrl.slice(0, q) : rawUrl).replace(/^\/(auth|rest)\/v1/, "") || "/";
  proxy(req, res, UPSTREAMS[service], `${rawPath}${query ? `?${query}` : ""}`);
});

server.keepAliveTimeout = 65_000;
server.listen(PORT, HOST, () => {
  console.log(
    `[gateway] ouvindo em http://${HOST}:${PORT} (auth -> :${UPSTREAMS.auth.port}, rest -> :${UPSTREAMS.rest.port})`,
  );
});

for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => {
    server.close();
    process.exit(0);
  });
}
