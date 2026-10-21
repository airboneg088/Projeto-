import { afterEach, describe, expect, it, vi } from "vitest";

const notFound = vi.fn(() => {
  throw new Error("NEXT_NOT_FOUND");
});
vi.mock("next/navigation", () => ({ notFound }));

const { assertPrototypesEnabled, prototypesEnabled } = await import("./prototypes");

describe("portão dos protótipos (ENABLE_PROTOTYPES)", () => {
  const original = process.env.ENABLE_PROTOTYPES;
  afterEach(() => {
    if (original === undefined) delete process.env.ENABLE_PROTOTYPES;
    else process.env.ENABLE_PROTOTYPES = original;
    notFound.mockClear();
  });

  it("sem a variável: 404", () => {
    delete process.env.ENABLE_PROTOTYPES;
    expect(prototypesEnabled()).toBe(false);
    expect(() => assertPrototypesEnabled()).toThrow("NEXT_NOT_FOUND");
    expect(notFound).toHaveBeenCalledOnce();
  });

  it.each(["0", "true", "yes", " 1", "1 ", ""])("valor %j não liga", (value) => {
    process.env.ENABLE_PROTOTYPES = value;
    expect(prototypesEnabled()).toBe(false);
    expect(() => assertPrototypesEnabled()).toThrow("NEXT_NOT_FOUND");
  });

  it('só exatamente "1" liga', () => {
    process.env.ENABLE_PROTOTYPES = "1";
    expect(prototypesEnabled()).toBe(true);
    expect(() => assertPrototypesEnabled()).not.toThrow();
    expect(notFound).not.toHaveBeenCalled();
  });
});
