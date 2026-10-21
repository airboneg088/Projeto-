import { describe, expect, it } from "vitest";

import { EnvError, parsePublicEnv } from "./env";

/** JWT de teste (assinatura falsa): só o payload importa para a checagem local. */
function fakeJwt(payload: Record<string, unknown>): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "HS256", typ: "JWT" })}.${encode(payload)}.assinatura`;
}

const valid = {
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321/",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: fakeJwt({ iss: "supabase-demo", role: "anon" }),
  NEXT_PUBLIC_SITE_URL: "http://localhost:3000",
};

describe("parsePublicEnv", () => {
  it("aceita valores válidos e tira a barra final das URLs", () => {
    const env = parsePublicEnv(valid);
    expect(env.NEXT_PUBLIC_SUPABASE_URL).toBe("http://127.0.0.1:54321");
    expect(env.NEXT_PUBLIC_SITE_URL).toBe("http://localhost:3000");
  });

  it("aceita chave publicável no formato novo", () => {
    const env = parsePublicEnv({
      ...valid,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_abc",
    });
    expect(env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY).toBe("sb_publishable_abc");
  });

  it("lista todas as variáveis ausentes", () => {
    expect(() => parsePublicEnv({})).toThrow(EnvError);
    try {
      parsePublicEnv({});
    } catch (error) {
      const message = (error as Error).message;
      expect(message).toContain("NEXT_PUBLIC_SUPABASE_URL");
      expect(message).toContain("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
      expect(message).toContain("NEXT_PUBLIC_SITE_URL");
      expect(message).toContain("pnpm stack:up");
    }
  });

  it("rejeita URL inválida ou sem http(s)", () => {
    expect(() => parsePublicEnv({ ...valid, NEXT_PUBLIC_SUPABASE_URL: "127.0.0.1:54321" })).toThrow(
      /NEXT_PUBLIC_SUPABASE_URL/,
    );
    expect(() => parsePublicEnv({ ...valid, NEXT_PUBLIC_SITE_URL: "ftp://exemplo.com" })).toThrow(
      /NEXT_PUBLIC_SITE_URL/,
    );
  });

  it("recusa chave secreta no lugar da publicável", () => {
    expect(() =>
      parsePublicEnv({ ...valid, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_secret_abc" }),
    ).toThrow(/chave secreta/);
    expect(() =>
      parsePublicEnv({
        ...valid,
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: fakeJwt({ role: "authenticated" }),
      }),
    ).toThrow(/anon/);
  });

  it("rejeita chave vazia", () => {
    expect(() => parsePublicEnv({ ...valid, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "  " })).toThrow(
      EnvError,
    );
  });
});
