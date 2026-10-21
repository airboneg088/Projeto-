import { describe, expect, it } from "vitest";

import { isLoginPath, isProtectedPath, normalizePath } from "./paths";

describe("normalizePath", () => {
  it.each([
    ["/", "/"],
    ["/Gerente/", "/gerente"],
    ["//gerente//", "/gerente"],
    ["/%67erente", "/gerente"],
    ["/HOJE/tarefa", "/hoje/tarefa"],
    ["/hoje%2Fx", "/hoje/x"],
    ["/painel\\x", "/painel/x"],
  ])("%j → %j", (input, expected) => {
    expect(normalizePath(input)).toBe(expected);
  });
});

describe("isProtectedPath", () => {
  it.each([
    "/",
    "/hoje",
    "/hoje/",
    "/HOJE",
    "/Hoje/tarefa/123",
    "/gerente",
    "/GERENTE/",
    "//gerente",
    "/%67erente",
    "/painel",
    "/painel/lojas",
    "/admin",
    "/Admin/usuarios",
  ])("protege %j", (path) => {
    expect(isProtectedPath(path)).toBe(true);
  });

  it.each([
    "/login",
    "/recuperar-senha",
    "/redefinir-senha",
    "/auth/confirm",
    "/hojex",
    "/gerentes",
    "/administracao",
  ])("não protege %j", (path) => {
    expect(isProtectedPath(path)).toBe(false);
  });
});

describe("isLoginPath", () => {
  it("reconhece variações de /login", () => {
    expect(isLoginPath("/login")).toBe(true);
    expect(isLoginPath("/Login/")).toBe(true);
    expect(isLoginPath("/login/outra")).toBe(false);
    expect(isLoginPath("/")).toBe(false);
  });
});
