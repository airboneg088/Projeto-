#!/usr/bin/env node
// Teste de fumaça da stack local, tudo pelo gateway (como o app faria):
//   1. cria um usuário pela API admin do GoTrue (chave service_role);
//   2. faz login com e-mail e senha (grant_type=password);
//   3. chama /rest/v1/ com o access token (espera 200);
//   4. pede recuperação de senha, confere o .eml em .local/mail e abre o link do e-mail;
//   5. apaga o usuário.
// Uso: node scripts/local-stack/smoke.mjs

import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { localKeys } from "./gen-keys.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const mailDir = resolve(here, "../../.local/mail");
const API = "http://127.0.0.1:54321";
const { anon, service_role: service } = localKeys();

const email = `smoke-${Date.now()}@exemplo.local`;
const password = "Exemplo#2026";
let userId = null;

function step(msg) {
  console.log(`[smoke] ${msg}`);
}

async function call(method, path, { key = anon, token, body } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      apikey: key,
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { status: res.status, json, text };
}

function expect(cond, msg, extra) {
  if (!cond) {
    console.error(`[smoke] FALHOU: ${msg}`, extra ?? "");
    process.exitCode = 1;
    throw new Error(msg);
  }
}

const listEml = () =>
  new Set(
    (() => {
      try {
        return readdirSync(mailDir).filter((f) => f.endsWith(".eml"));
      } catch {
        return [];
      }
    })(),
  );

try {
  const noKey = await fetch(`${API}/rest/v1/`);
  expect(noKey.status === 401, `gateway sem apikey deveria responder 401 (veio ${noKey.status})`);
  step("gateway exige apikey: ok (401 sem chave)");

  const created = await call("POST", "/auth/v1/admin/users", {
    key: service,
    body: { email, password, email_confirm: true },
  });
  expect(created.status === 200 && created.json?.id, "criar usuário (admin)", created.text);
  userId = created.json.id;
  step(`usuário criado pela API admin: ${email} (${userId})`);

  const login = await call("POST", "/auth/v1/token?grant_type=password", {
    body: { email, password },
  });
  expect(login.status === 200 && login.json?.access_token, "login com senha", login.text);
  step("login grant_type=password: ok (access_token recebido)");

  const rest = await call("GET", "/rest/v1/", { token: login.json.access_token });
  expect(
    rest.status === 200,
    `GET /rest/v1/ com token deveria ser 200 (veio ${rest.status})`,
    rest.text,
  );
  step("GET /rest/v1/ com access token: 200");

  const before = listEml();
  const recover = await call("POST", "/auth/v1/recover", { body: { email } });
  expect(recover.status === 200, `POST /auth/v1/recover (veio ${recover.status})`, recover.text);
  let found = null;
  for (let i = 0; i < 50 && !found; i++) {
    await new Promise((r) => setTimeout(r, 100));
    found = [...listEml()].find((f) => !before.has(f)) ?? null;
  }
  expect(found, "e-mail de recuperação não chegou em .local/mail");
  const meta = JSON.parse(readFileSync(join(mailDir, found.replace(/\.eml$/, ".json")), "utf8"));
  const link = meta.links.find((l) => l.includes("/auth/v1/verify") && l.includes("type=recovery"));
  expect(meta.envelope.rcptTo.includes(email), "destinatário do e-mail", meta.envelope);
  expect(link, "link de recuperação no e-mail", meta.links);
  step(`e-mail de recuperação gravado: .local/mail/${found}`);

  // O link do e-mail é rota aberta do gateway (sem apikey) e redireciona ao site com a sessão
  const verify = await fetch(link, { redirect: "manual" });
  const location = verify.headers.get("location") ?? "";
  expect(
    verify.status === 303 &&
      location.startsWith("http://localhost:3000") &&
      location.includes("access_token="),
    `link de recuperação deveria redirecionar ao site com sessão (veio ${verify.status} ${location})`,
  );
  step(`link de recuperação válido: 303 -> ${location.split("#")[0]}#access_token=...`);
} finally {
  if (userId) {
    const del = await call("DELETE", `/auth/v1/admin/users/${userId}`, { key: service });
    if (del.status === 200) step("usuário apagado");
    else {
      console.error(`[smoke] FALHOU ao apagar usuário (${del.status})`, del.text);
      process.exitCode = 1;
    }
  }
}

if (!process.exitCode) step("tudo certo");
