import { describe, expect, it } from "vitest";

import { formatLongDate, formatTime } from "./format";

describe("formatação no fuso da loja", () => {
  it("data por extenso em pt-BR, no dia local (não no UTC)", () => {
    // 02:30 UTC de 22/10 ainda é 21/10 em São Paulo (UTC-3).
    const date = new Date("2026-10-22T02:30:00Z");
    expect(formatLongDate(date)).toBe("quarta-feira, 21 de outubro");
  });

  it("hora com dois dígitos, 24 h", () => {
    expect(formatTime(new Date("2026-10-21T10:30:00Z"))).toBe("07:30");
    expect(formatTime(new Date("2026-10-22T00:05:00Z"))).toBe("21:05");
  });
});
