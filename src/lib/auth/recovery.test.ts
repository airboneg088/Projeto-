import { describe, expect, it } from "vitest";

import { RECOVERY_WINDOW_SECONDS, isRecentRecovery } from "./recovery";

const now = 1_800_000_000;

describe("isRecentRecovery", () => {
  it("aceita sessão aberta pelo link de recuperação há pouco", () => {
    expect(isRecentRecovery({ amr: [{ method: "recovery", timestamp: now - 30 }] }, now)).toBe(
      true,
    );
    expect(isRecentRecovery({ amr: [{ method: "otp", timestamp: now - 30 }] }, now)).toBe(true);
  });

  it("recusa sessão de login com senha", () => {
    expect(isRecentRecovery({ amr: [{ method: "password", timestamp: now - 30 }] }, now)).toBe(
      false,
    );
  });

  it("recusa recuperação antiga", () => {
    const old = now - RECOVERY_WINDOW_SECONDS - 1;
    expect(isRecentRecovery({ amr: [{ method: "recovery", timestamp: old }] }, now)).toBe(false);
  });

  it("recusa claims sem amr ou malformadas", () => {
    expect(isRecentRecovery(null, now)).toBe(false);
    expect(isRecentRecovery({}, now)).toBe(false);
    expect(isRecentRecovery({ amr: "recovery" }, now)).toBe(false);
    expect(isRecentRecovery({ amr: [{ method: "recovery" }] }, now)).toBe(false);
  });
});
