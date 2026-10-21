import { existsSync, readFileSync } from "node:fs";

import { type APIRequestContext, expect, test } from "@playwright/test";

import { USUARIOS, entrar } from "./fixtures/usuarios";

/**
 * R2-APP-05: o check:secrets estático não vê o que o servidor renderiza. Aqui o HTML e o RSC
 * servidos de verdade (sem login e com cada papel) são varridos atrás do valor da chave secreta.
 */
function secretValue(): string {
  const fromEnv = process.env.SUPABASE_SECRET_KEY?.trim();
  if (fromEnv) return fromEnv;
  const envLocal = ".env.local";
  if (existsSync(envLocal)) {
    const match = /^\s*SUPABASE_SECRET_KEY\s*=\s*(.+?)\s*$/m.exec(readFileSync(envLocal, "utf8"));
    if (match?.[1]) return match[1].replace(/^["']|["']$/g, "");
  }
  throw new Error("SUPABASE_SECRET_KEY não encontrada (ambiente ou .env.local)");
}

const SECRET = secretValue();

async function expectNoSecret(request: APIRequestContext, path: string) {
  for (const headers of [{}, { RSC: "1" }] as Record<string, string>[]) {
    const response = await request.get(path, { headers });
    const body = await response.text();
    expect(body.length, `${path} ${JSON.stringify(headers)}`).toBeGreaterThan(0);
    expect(body.includes(SECRET), `${path} ${JSON.stringify(headers)}`).toBe(false);
  }
}

test("HTML e RSC das páginas públicas não contêm a chave secreta", async ({ request }) => {
  expect(SECRET.length).toBeGreaterThan(20);
  for (const path of ["/login", "/recuperar-senha", "/redefinir-senha", "/nao-existe"]) {
    await expectNoSecret(request, path);
  }
});

for (const usuario of [
  USUARIOS.proprietaria,
  USUARIOS.admin,
  USUARIOS.gerentePrimavera,
  USUARIOS.colaborador1Primavera,
]) {
  test(`HTML e RSC de ${usuario.inicio} (${usuario.papel}) não contêm a chave secreta`, async ({
    page,
  }) => {
    await entrar(page, usuario);
    await expectNoSecret(page.request, usuario.inicio);
  });
}
