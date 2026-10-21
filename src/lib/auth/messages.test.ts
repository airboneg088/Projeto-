import { describe, expect, it } from "vitest";

import { AUTH_MESSAGES, lookupMessage } from "./messages";

describe("lookupMessage", () => {
  const table: Readonly<Record<string, string>> = {
    "sem-acesso": AUTH_MESSAGES.noAccess,
    "link-invalido": AUTH_MESSAGES.invalidLink,
  };

  it("devolve a mensagem das chaves da tabela", () => {
    expect(lookupMessage(table, "sem-acesso")).toBe(AUTH_MESSAGES.noAccess);
    expect(lookupMessage(table, "link-invalido")).toBe(AUTH_MESSAGES.invalidLink);
  });

  // R2-APP-15: /login?erro=__proto__ (e afins) dava 500.
  it.each([
    "__proto__",
    "constructor",
    "toString",
    "hasOwnProperty",
    "valueOf",
    "isPrototypeOf",
    "__defineGetter__",
    "",
    "nao-existe",
  ])("ignora %j", (key) => {
    expect(lookupMessage(table, key)).toBeUndefined();
  });

  it("ignora ausência de valor", () => {
    expect(lookupMessage(table, undefined)).toBeUndefined();
  });
});
