import { describe, expect, it } from "vitest";

import {
  RECOVERY_WINDOW_SECONDS,
  emailFromClaims,
  isRecentRecovery,
  recoveryLinkError,
} from "./recovery";

const now = 1_800_000_000;

describe("isRecentRecovery", () => {
  it("aceita sessão aberta pelo link de recuperação há pouco", () => {
    expect(isRecentRecovery({ amr: [{ method: "recovery", timestamp: now - 30 }] }, now)).toBe(
      true,
    );
  });

  // R2-APP-06: o token de um link de login por e-mail ("magic link") também valida como
  // type=recovery no Auth e gera amr "otp". Só o fluxo PKCE de recuperação ("recovery") vale.
  it("recusa sessão de link de login por e-mail (amr otp)", () => {
    expect(isRecentRecovery({ amr: [{ method: "otp", timestamp: now - 30 }] }, now)).toBe(false);
    expect(isRecentRecovery({ amr: [{ method: "magiclink", timestamp: now - 30 }] }, now)).toBe(
      false,
    );
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

describe("emailFromClaims", () => {
  it("lê o e-mail das claims", () => {
    expect(emailFromClaims({ email: "pessoa@exemplo.local" })).toBe("pessoa@exemplo.local");
  });

  it("devolve null sem e-mail válido", () => {
    expect(emailFromClaims(null)).toBeNull();
    expect(emailFromClaims({})).toBeNull();
    expect(emailFromClaims({ email: "" })).toBeNull();
    expect(emailFromClaims({ email: 1 })).toBeNull();
  });
});

// R3-CRITERIOS-01: o link aberto em outro navegador (ou de novo) dizia "expirou ou já foi usado".
describe("recoveryLinkError", () => {
  it.each(["pkce_code_verifier_not_found", "bad_code_verifier", "flow_state_not_found"])(
    "%s: link aberto em outro navegador (ou já usado aqui)",
    (code) => {
      expect(recoveryLinkError(code)).toBe("outro-navegador");
    },
  );

  it.each([undefined, "otp_expired", "flow_state_expired", "unexpected_failure"])(
    "%s: link inválido ou expirado",
    (code) => {
      expect(recoveryLinkError(code)).toBe("link-invalido");
    },
  );
});
