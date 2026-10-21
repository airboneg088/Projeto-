import { describe, expect, it } from "vitest";

import { adminLoginDetails, hasActiveAdminMembership } from "./admin-login";

describe("adminLoginDetails", () => {
  it("usa o 1º endereço de x-forwarded-for e o user-agent", () => {
    expect(adminLoginDetails(" 203.0.113.7 , 10.0.0.1", "Mozilla/5.0")).toEqual({
      ip: "203.0.113.7",
      user_agent: "Mozilla/5.0",
    });
  });

  it("omite campos ausentes ou vazios", () => {
    expect(adminLoginDetails(null, null)).toEqual({});
    expect(adminLoginDetails("  ", "   ")).toEqual({});
  });

  it("corta valores longos (o banco também limita)", () => {
    const details = adminLoginDetails("1".repeat(500), "a".repeat(5000));
    expect(details.ip).toHaveLength(64);
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
