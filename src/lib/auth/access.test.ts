import { describe, expect, it } from "vitest";

import {
  NO_ACCESS_PATH,
  decideAccess,
  isMembershipActive,
  loginPathFor,
  rolesFrom,
} from "./access";
import type { Role } from "./roles";

const now = new Date("2026-10-20T15:00:00Z");
const membership = (starts_at: string, ends_at: string | null, role = "staff") => ({
  role,
  store_id: "loja-1",
  starts_at,
  ends_at,
});

describe("isMembershipActive", () => {
  it("vale quando começou e não tem fim", () => {
    expect(isMembershipActive(membership("2026-01-01T00:00:00Z", null), now)).toBe(true);
  });

  it("vale quando o fim é no futuro", () => {
    expect(
      isMembershipActive(membership("2026-01-01T00:00:00Z", "2026-10-21T00:00:00Z"), now),
    ).toBe(true);
  });

  it("vale exatamente no início", () => {
    expect(isMembershipActive(membership("2026-10-20T15:00:00Z", null), now)).toBe(true);
  });

  it("não vale antes do início", () => {
    expect(isMembershipActive(membership("2026-10-20T15:00:01Z", null), now)).toBe(false);
  });

  it("não vale depois do fim (fim exclusivo)", () => {
    expect(
      isMembershipActive(membership("2026-01-01T00:00:00Z", "2026-10-20T15:00:00Z"), now),
    ).toBe(false);
    expect(
      isMembershipActive(membership("2026-01-01T00:00:00Z", "2026-05-01T00:00:00Z"), now),
    ).toBe(false);
  });

  it("não vale com data inválida", () => {
    expect(isMembershipActive(membership("ontem", null), now)).toBe(false);
    expect(isMembershipActive(membership("2026-01-01T00:00:00Z", "amanhã"), now)).toBe(false);
  });
});

describe("rolesFrom", () => {
  it("junta papéis distintos e ignora valores desconhecidos", () => {
    const list = [
      membership("2026-01-01T00:00:00Z", null, "staff"),
      membership("2026-01-01T00:00:00Z", null, "staff"),
      membership("2026-01-01T00:00:00Z", null, "manager"),
      membership("2026-01-01T00:00:00Z", null, "root"),
    ];
    expect(rolesFrom(list).sort()).toEqual(["manager", "staff"]);
  });
});

describe("loginPathFor", () => {
  it("codifica o retorno e dispensa o da raiz", () => {
    expect(loginPathFor("/gerente")).toBe("/login?next=%2Fgerente");
    expect(loginPathFor("/hoje?x=1")).toBe("/login?next=%2Fhoje%3Fx%3D1");
    expect(loginPathFor("/")).toBe("/login");
  });
});

describe("decideAccess", () => {
  const active = (roles: Role[]) => ({ profileStatus: "active", roles });

  it("sem sessão vai para o login com next", () => {
    expect(decideAccess(null, "gerente")).toEqual({ kind: "login", to: "/login?next=%2Fgerente" });
    expect(decideAccess(null, null)).toEqual({ kind: "login", to: "/login" });
  });

  it("perfil inativo ou ausente → sem acesso", () => {
    expect(decideAccess({ profileStatus: "inactive", roles: ["staff"] }, "hoje")).toEqual({
      kind: "sem-acesso",
      to: NO_ACCESS_PATH,
    });
    expect(decideAccess({ profileStatus: null, roles: ["owner"] }, "painel").kind).toBe(
      "sem-acesso",
    );
  });

  it("sem vínculo vigente → sem acesso", () => {
    expect(decideAccess(active([]), "hoje").kind).toBe("sem-acesso");
    expect(decideAccess(active([]), null).kind).toBe("sem-acesso");
  });

  it("libera a área do papel", () => {
    expect(decideAccess(active(["staff"]), "hoje")).toEqual({ kind: "ok" });
    expect(decideAccess(active(["manager"]), "gerente")).toEqual({ kind: "ok" });
    expect(decideAccess(active(["owner"]), "gerente")).toEqual({ kind: "ok" });
    expect(decideAccess(active(["owner"]), "painel")).toEqual({ kind: "ok" });
    expect(decideAccess(active(["admin"]), "admin")).toEqual({ kind: "ok" });
  });

  it("área de outro papel → página do papel principal", () => {
    expect(decideAccess(active(["staff"]), "gerente")).toEqual({ kind: "redirect", to: "/hoje" });
    expect(decideAccess(active(["staff"]), "painel")).toEqual({ kind: "redirect", to: "/hoje" });
    expect(decideAccess(active(["staff"]), "admin")).toEqual({ kind: "redirect", to: "/hoje" });
    expect(decideAccess(active(["manager"]), "painel")).toEqual({
      kind: "redirect",
      to: "/gerente",
    });
    expect(decideAccess(active(["manager"]), "admin")).toEqual({
      kind: "redirect",
      to: "/gerente",
    });
    expect(decideAccess(active(["admin"]), "hoje")).toEqual({ kind: "redirect", to: "/admin" });
  });

  it('"/" sempre redireciona para a página do papel', () => {
    expect(decideAccess(active(["owner", "admin"]), null)).toEqual({
      kind: "redirect",
      to: "/painel",
    });
    expect(decideAccess(active(["staff"]), null)).toEqual({ kind: "redirect", to: "/hoje" });
  });
});
