import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { localKeys, signJwt } from "../gen-keys.mjs";
import { parseToml } from "../toml.mjs";

describe("gen-keys", () => {
  it("gera as mesmas chaves padrão da CLI do Supabase", () => {
    const { anon, service_role } = localKeys();
    expect(anon).toBe(
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
    );
    const payload = JSON.parse(Buffer.from(service_role.split(".")[1], "base64url").toString());
    expect(payload).toEqual({ iss: "supabase-demo", role: "service_role", exp: 1983812996 });
  });

  it("assina HS256 de forma determinística", () => {
    expect(signJwt({ a: 1 }, "segredo")).toBe(signJwt({ a: 1 }, "segredo"));
    expect(signJwt({ a: 1 }, "segredo")).not.toBe(signJwt({ a: 1 }, "outro"));
  });
});

describe("toml", () => {
  it("lê tabelas, strings, booleanos, números e arrays", () => {
    const cfg = parseToml(`
# comentário
project_id = "x" # fim de linha
[auth]
site_url = "http://localhost:3000"
additional_redirect_urls = ["http://localhost:3000/**", 'b']
enable_signup = false
jwt_expiry = 3600
[auth.email.template.recovery]
subject = "Redefinir senha # não é comentário"
`);
    expect(cfg.project_id).toBe("x");
    expect(cfg.auth.site_url).toBe("http://localhost:3000");
    expect(cfg.auth.additional_redirect_urls).toEqual(["http://localhost:3000/**", "b"]);
    expect(cfg.auth.enable_signup).toBe(false);
    expect(cfg.auth.jwt_expiry).toBe(3600);
    expect(cfg.auth.email.template.recovery.subject).toBe("Redefinir senha # não é comentário");
  });

  it("lê o supabase/config.toml do projeto com os valores do Éde Gestão", () => {
    const cfg = parseToml(
      readFileSync(new URL("../../../supabase/config.toml", import.meta.url), "utf8"),
    );
    expect(cfg.project_id).toBe("ede-gestao");
    expect(cfg.auth.enable_signup).toBe(false);
    expect(cfg.auth.email.enable_signup).toBe(true);
    expect(cfg.auth.site_url).toBe("http://localhost:3000");
    expect(cfg.db.major_version).toBe(17);
  });
});
