import { describe, expect, it } from "vitest";

import {
  isExpectedPasswordUpdateError,
  passwordUpdateErrorMessage,
  signInErrorMessage,
} from "./errors";
import { AUTH_MESSAGES } from "./messages";

describe("signInErrorMessage", () => {
  it("conta inexistente, senha errada e conta bloqueada recebem o mesmo texto (R2-APP-09)", () => {
    const invalid = { status: 400, code: "invalid_credentials" };
    const banned = { status: 400, code: "user_banned" };
    expect(signInErrorMessage(invalid)).toBe(AUTH_MESSAGES.invalidCredentials);
    expect(signInErrorMessage(banned)).toBe(AUTH_MESSAGES.invalidCredentials);
    expect(signInErrorMessage({ status: 403, code: "user_banned" })).toBe(
      AUTH_MESSAGES.invalidCredentials,
    );
  });

  it("limite de tentativas tem texto próprio", () => {
    expect(signInErrorMessage({ status: 429 })).toBe(AUTH_MESSAGES.tooManyAttempts);
    expect(signInErrorMessage({ status: 400, code: "over_request_rate_limit" })).toBe(
      AUTH_MESSAGES.tooManyAttempts,
    );
  });

  it("falha do serviço pede para tentar de novo", () => {
    expect(signInErrorMessage({ status: 500 })).toBe(AUTH_MESSAGES.signInUnavailable);
    expect(signInErrorMessage({})).toBe(AUTH_MESSAGES.signInUnavailable);
  });
});

describe("passwordUpdateErrorMessage", () => {
  it("explica cada recusa do Auth (R2-APP-14)", () => {
    expect(passwordUpdateErrorMessage({ code: "same_password" })).toBe(AUTH_MESSAGES.samePassword);
    expect(passwordUpdateErrorMessage({ code: "weak_password" })).toBe(AUTH_MESSAGES.weakPassword);
    expect(passwordUpdateErrorMessage({ code: "validation_failed" })).toBe(
      AUTH_MESSAGES.passwordTooLong,
    );
    expect(passwordUpdateErrorMessage({ code: "unexpected_failure" })).toBe(
      AUTH_MESSAGES.passwordUpdateFailed,
    );
  });

  it("só erros inesperados vão para o log", () => {
    expect(isExpectedPasswordUpdateError({ code: "weak_password" })).toBe(true);
    expect(isExpectedPasswordUpdateError({ code: "validation_failed" })).toBe(true);
    expect(isExpectedPasswordUpdateError({ code: "unexpected_failure" })).toBe(false);
    expect(isExpectedPasswordUpdateError({})).toBe(false);
  });
});
