import { describe, expect, it } from "vitest";

import { buildCsp, createNonce } from "./csp";

function directives(csp: string): Map<string, string[]> {
  return new Map(
    csp.split(";").map((part) => {
      const [name = "", ...values] = part.trim().split(/\s+/);
      return [name, values];
    }),
  );
}

const base = {
  nonce: "abc123==",
  supabaseUrl: "https://projeto.supabase.co/",
  isDev: false,
  upgradeInsecureRequests: true,
};

describe("buildCsp", () => {
  it("monta a política de produção", () => {
    const map = directives(buildCsp(base));
    expect(map.get("default-src")).toEqual(["'self'"]);
    expect(map.get("script-src")).toEqual(["'self'", "'nonce-abc123=='", "'strict-dynamic'"]);
    expect(map.get("style-src")).toEqual(["'self'", "'unsafe-inline'"]);
    expect(map.get("img-src")).toEqual(["'self'", "data:", "blob:", "https://projeto.supabase.co"]);
    expect(map.get("connect-src")).toEqual(["'self'", "https://projeto.supabase.co"]);
    expect(map.get("font-src")).toEqual(["'self'"]);
    expect(map.get("frame-ancestors")).toEqual(["'none'"]);
    expect(map.get("form-action")).toEqual(["'self'"]);
    expect(map.get("base-uri")).toEqual(["'self'"]);
    expect(map.get("object-src")).toEqual(["'none'"]);
    expect(map.has("upgrade-insecure-requests")).toBe(true);
  });

  it("só libera unsafe-eval em desenvolvimento", () => {
    expect(buildCsp(base)).not.toContain("unsafe-eval");
    expect(directives(buildCsp({ ...base, isDev: true })).get("script-src")).toContain(
      "'unsafe-eval'",
    );
  });

  it("não força https fora de produção com https", () => {
    expect(buildCsp({ ...base, upgradeInsecureRequests: false })).not.toContain(
      "upgrade-insecure-requests",
    );
  });

  it("nunca usa unsafe-inline em scripts", () => {
    expect(directives(buildCsp({ ...base, isDev: true })).get("script-src")).not.toContain(
      "'unsafe-inline'",
    );
  });
});

describe("createNonce", () => {
  it("gera 128 bits em base64, diferente a cada chamada", () => {
    const a = createNonce();
    const b = createNonce();
    expect(a).not.toBe(b);
    expect(a).toMatch(/^[A-Za-z0-9+/]{22}==$/);
    expect(Buffer.from(a, "base64")).toHaveLength(16);
  });
});
