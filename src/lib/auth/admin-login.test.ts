import { describe, expect, it } from "vitest";

import {
  adminLoginDetails,
  hasActiveAdminMembership,
  ipTrustFromEnv,
  trustedClientIp,
} from "./admin-login";

const h = (values: Record<string, string>) => new Headers(values);

describe("trustedClientIp", () => {
  // R2-APP-16: o 1º valor de x-forwarded-for é escolhido pelo cliente atrás de proxy que acrescenta.
  it("na Vercel usa x-real-ip e ignora x-forwarded-for forjado", () => {
    const headers = h({
      "x-forwarded-for": "203.0.113.66, 127.0.0.1",
      "x-real-ip": "198.51.100.7",
      "x-vercel-forwarded-for": "198.51.100.7",
    });
    expect(trustedClientIp(headers, "vercel")).toBe("198.51.100.7");
  });

  it("na Vercel, sem x-real-ip, usa o 1º de x-vercel-forwarded-for", () => {
    expect(
      trustedClientIp(h({ "x-vercel-forwarded-for": "2001:db8::1, 10.0.0.1" }), "vercel"),
    ).toBe("2001:db8::1");
  });

  it("sem fonte confiável (local), não registra ip nenhum", () => {
    const headers = h({ "x-forwarded-for": "203.0.113.66", "x-real-ip": "203.0.113.66" });
    expect(trustedClientIp(headers, "none")).toBeUndefined();
  });

  it("ignora valor que não é endereço ip", () => {
    expect(trustedClientIp(h({ "x-real-ip": "agente-forjado" }), "vercel")).toBeUndefined();
    expect(trustedClientIp(h({ "x-real-ip": "1".repeat(500) }), "vercel")).toBeUndefined();
    expect(trustedClientIp(h({}), "vercel")).toBeUndefined();
  });
});

describe("ipTrustFromEnv", () => {
  it("confia nos cabeçalhos só na Vercel", () => {
    expect(ipTrustFromEnv({ VERCEL: "1" })).toBe("vercel");
    expect(ipTrustFromEnv({})).toBe("none");
    expect(ipTrustFromEnv({ VERCEL: "0" })).toBe("none");
  });
});

describe("adminLoginDetails", () => {
  it("usa o ip confiável e o user-agent", () => {
    const headers = h({
      "x-forwarded-for": "203.0.113.66, 127.0.0.1",
      "x-real-ip": "198.51.100.7",
      "user-agent": "Mozilla/5.0",
    });
    expect(adminLoginDetails(headers, "vercel")).toEqual({
      ip: "198.51.100.7",
      user_agent: "Mozilla/5.0",
    });
    expect(adminLoginDetails(headers, "none")).toEqual({ user_agent: "Mozilla/5.0" });
  });

  it("omite campos ausentes ou vazios", () => {
    expect(adminLoginDetails(h({}), "vercel")).toEqual({});
    expect(adminLoginDetails(h({ "user-agent": "   " }), "vercel")).toEqual({});
  });

  it("corta o user-agent longo (o banco também limita)", () => {
    const details = adminLoginDetails(h({ "user-agent": "a".repeat(5000) }), "vercel");
    expect(details.user_agent).toHaveLength(300);
    expect(JSON.stringify(details).length).toBeLessThan(2048);
  });
});

describe("hasActiveAdminMembership", () => {
  const now = new Date("2026-10-21T12:00:00Z");
  const admin = { role: "admin", store_id: null, starts_at: "2026-01-01T00:00:00Z", ends_at: null };

  it("reconhece vínculo de admin de rede vigente", () => {
    expect(hasActiveAdminMembership([admin], now)).toBe(true);
  });

  it("ignora vínculo encerrado, futuro, com loja ou de outro papel", () => {
    expect(hasActiveAdminMembership([{ ...admin, ends_at: "2026-10-21T11:00:00Z" }], now)).toBe(
      false,
    );
    expect(hasActiveAdminMembership([{ ...admin, starts_at: "2026-10-22T00:00:00Z" }], now)).toBe(
      false,
    );
    expect(hasActiveAdminMembership([{ ...admin, store_id: "loja" }], now)).toBe(false);
    expect(hasActiveAdminMembership([{ ...admin, role: "manager", store_id: "loja" }], now)).toBe(
      false,
    );
    expect(hasActiveAdminMembership([], now)).toBe(false);
  });
});
