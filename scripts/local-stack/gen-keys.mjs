#!/usr/bin/env node
// Gera as chaves JWT locais (anon e service_role) com node:crypto, sem dependências.
// Mesmo segredo, header e payload da CLI do Supabase: as chaves geradas são idênticas às
// impressas por `supabase start` (padrão público de desenvolvimento, nunca usar em produção).
//
// Uso:
//   node scripts/local-stack/gen-keys.mjs            -> JSON { anon, service_role, jwt_secret }
//   node scripts/local-stack/gen-keys.mjs --shell    -> linhas ANON_KEY=... e SERVICE_ROLE_KEY=...
//   node scripts/local-stack/gen-keys.mjs --write-env <arquivo>
//        -> cria/atualiza o .env.local, preservando variáveis que não são da stack.

import { createHmac } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const JWT_SECRET = "super-secret-jwt-token-with-at-least-32-characters-long";
// exp fixo (2032-11-12), igual ao da CLI do Supabase
const EXP = 1983812996;

function base64url(input) {
  return Buffer.from(input).toString("base64url");
}

export function signJwt(payload, secret = JWT_SECRET) {
  const header = base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = base64url(JSON.stringify(payload));
  const signature = createHmac("sha256", secret).update(`${header}.${body}`).digest("base64url");
  return `${header}.${body}.${signature}`;
}

export function localKeys() {
  return {
    anon: signJwt({ iss: "supabase-demo", role: "anon", exp: EXP }),
    service_role: signJwt({ iss: "supabase-demo", role: "service_role", exp: EXP }),
    jwt_secret: JWT_SECRET,
  };
}

function writeEnv(file) {
  const keys = localKeys();
  const managed = new Map([
    ["NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321"],
    ["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", keys.anon],
    ["SUPABASE_SECRET_KEY", keys.service_role],
    ["NEXT_PUBLIC_SITE_URL", "http://localhost:3000"],
    ["DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres"],
  ]);
  const header = [
    "# Gerado por `pnpm stack:up` para a stack local. Não versionar.",
    "# Chaves de desenvolvimento local (padrão público da CLI do Supabase). Nunca usar em produção.",
  ];
  const kept = [];
  if (existsSync(file)) {
    for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
      const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=/.exec(line);
      if (m && managed.has(m[1])) continue;
      if (header.includes(line)) continue;
      kept.push(line);
    }
  }
  while (kept.length && kept[kept.length - 1].trim() === "") kept.pop();
  const out = [...header, ...[...managed].map(([k, v]) => `${k}=${v}`)];
  if (kept.some((l) => l.trim() !== "")) out.push("", ...kept);
  writeFileSync(file, out.join("\n") + "\n", { mode: 0o600 });
}

function main() {
  const args = process.argv.slice(2);
  if (args[0] === "--write-env") {
    if (!args[1]) {
      console.error("uso: gen-keys.mjs --write-env <arquivo>");
      process.exit(2);
    }
    writeEnv(args[1]);
  } else if (args[0] === "--shell") {
    const k = localKeys();
    process.stdout.write(`ANON_KEY=${k.anon}\nSERVICE_ROLE_KEY=${k.service_role}\n`);
  } else {
    process.stdout.write(JSON.stringify(localKeys(), null, 2) + "\n");
  }
}

// Só executa a CLI quando chamado diretamente (o módulo também é importado pelo gateway).
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
