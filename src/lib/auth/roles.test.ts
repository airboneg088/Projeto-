import { describe, expect, it } from "vitest";

import {
  AREAS,
  AREA_ACCESS,
  type Area,
  ROLES,
  type Role,
  accessibleAreas,
  canAccess,
  homeFor,
  isRole,
  primaryRole,
  safeNextPath,
} from "./roles";

describe("primaryRole", () => {
  it("segue a prioridade owner > manager > staff > admin", () => {
    expect(primaryRole(["admin", "staff", "manager", "owner"])).toBe("owner");
    expect(primaryRole(["admin", "staff", "manager"])).toBe("manager");
    expect(primaryRole(["admin", "staff"])).toBe("staff");
    expect(primaryRole(["admin"])).toBe("admin");
    expect(primaryRole(["staff", "owner"])).toBe("owner");
  });

  it("devolve null sem papéis", () => {
    expect(primaryRole([])).toBeNull();
  });
});

describe("homeFor", () => {
  it("leva cada papel à sua área", () => {
    expect(homeFor("owner")).toBe("/painel");
    expect(homeFor("manager")).toBe("/gerente");
    expect(homeFor("staff")).toBe("/hoje");
    expect(homeFor("admin")).toBe("/admin");
  });
});

describe("canAccess", () => {
  const expected: Record<Area, Record<Role, boolean>> = {
    hoje: { staff: true, manager: false, owner: false, admin: false },
    gerente: { staff: false, manager: true, owner: true, admin: false },
    painel: { staff: false, manager: false, owner: true, admin: false },
    admin: { staff: false, manager: false, owner: false, admin: true },
  };

  for (const area of AREAS) {
    for (const role of ROLES) {
      it(`${role} ${expected[area][role] ? "entra" : "não entra"} em /${area}`, () => {
        expect(canAccess(area, [role])).toBe(expected[area][role]);
      });
    }
  }

  it("bate com AREA_ACCESS", () => {
    expect(AREA_ACCESS).toEqual({
      hoje: ["staff"],
      gerente: ["manager", "owner"],
      painel: ["owner"],
      admin: ["admin"],
    });
  });

  it("aceita qualquer um dos papéis e nega lista vazia", () => {
    expect(canAccess("gerente", ["staff", "manager"])).toBe(true);
    expect(canAccess("hoje", [])).toBe(false);
  });

  it("lista as áreas acessíveis", () => {
    expect(accessibleAreas(["owner"])).toEqual(["gerente", "painel"]);
    expect(accessibleAreas(["staff"])).toEqual(["hoje"]);
    expect(accessibleAreas([])).toEqual([]);
  });
});

describe("isRole", () => {
  it("reconhece só os 4 papéis", () => {
    for (const role of ROLES) expect(isRole(role)).toBe(true);
    expect(isRole("Owner")).toBe(false);
    expect(isRole("superuser")).toBe(false);
    expect(isRole(null)).toBe(false);
  });
});

describe("safeNextPath", () => {
  it.each([
    "//evil.com",
    "/\\evil.com",
    "\\\\evil.com",
    "https://evil.com",
    "http:evil.com",
    "javascript:alert(1)",
    "JaVaScRiPt:alert(1)",
    "data:text/html,oi",
    "/%2F%2Fevil.com",
    "%2F%2Fevil.com",
    "/%2f%2fevil.com",
    "/%5Cevil.com",
    "/%252F%252Fevil.com",
    "/%09/evil.com",
    "/\t/evil.com",
    "/\n/evil.com",
    "/ok\u0000",
    "/%E0%A4%A",
    "evil.com",
    "",
    " /hoje",
  ])("rejeita %j", (input) => {
    expect(safeNextPath(input)).toBe("/");
  });

  it.each(["/", "/hoje", "/gerente", "/ok?x=1", "/painel?loja=primavera&periodo=7d#topo"])(
    "mantém %j",
    (input) => {
      expect(safeNextPath(input)).toBe(input);
    },
  );

  it("usa o fallback para valores que não são texto ou longos demais", () => {
    expect(safeNextPath(undefined)).toBe("/");
    expect(safeNextPath(null)).toBe("/");
    expect(safeNextPath(["/hoje"])).toBe("/");
    expect(safeNextPath(`/${"a".repeat(3000)}`)).toBe("/");
    expect(safeNextPath("//evil.com", "/login")).toBe("/login");
  });
});
