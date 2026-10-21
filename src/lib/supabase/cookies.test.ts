import { describe, expect, it } from "vitest";

import { SESSION_COOKIE_MAX_AGE_SECONDS, sessionCookieOptions } from "./cookies";

describe("sessionCookieOptions", () => {
  // R2-APP-04: o padrão do @supabase/ssr é httpOnly false, sem Secure e 400 dias.
  const ssrDefaults = { path: "/", sameSite: "lax" as const, httpOnly: false, maxAge: 400 * 86400 };

  it("grava HttpOnly, Secure em produção, Lax, path / e 7 dias", () => {
    expect(sessionCookieOptions(ssrDefaults, true)).toEqual({
      path: "/",
      sameSite: "lax",
      httpOnly: true,
      secure: true,
      maxAge: SESSION_COOKIE_MAX_AGE_SECONDS,
    });
    expect(SESSION_COOKIE_MAX_AGE_SECONDS).toBe(604800);
  });

  it("fora de produção não exige HTTPS, mas continua HttpOnly", () => {
    const options = sessionCookieOptions(ssrDefaults, false);
    expect(options.secure).toBe(false);
    expect(options.httpOnly).toBe(true);
  });

  it("mantém a remoção do cookie", () => {
    expect(sessionCookieOptions({ ...ssrDefaults, maxAge: 0 }, true).maxAge).toBe(0);
    expect(sessionCookieOptions({ path: "/", expires: new Date(0) }, true).maxAge).toBe(0);
  });

  it("não deixa opções vindas da biblioteca afrouxarem a política", () => {
    const options = sessionCookieOptions(
      { path: "/outro", sameSite: "none", httpOnly: false, secure: false, maxAge: 999999999 },
      true,
    );
    expect(options).toMatchObject({ path: "/", sameSite: "lax", httpOnly: true, secure: true });
    expect(options.maxAge).toBe(SESSION_COOKIE_MAX_AGE_SECONDS);
  });
});
