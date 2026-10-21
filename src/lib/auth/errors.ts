import { AUTH_MESSAGES } from "./messages";

/** Campos do erro do Auth usados para escolher a mensagem (o AuthError do supabase-js tem ambos). */
export type AuthErrorLike = { status?: number; code?: string };

/**
 * Mensagem do login recusado. Conta inexistente, senha errada e conta bloqueada no Auth
 * (`user_banned`, conferido pelo Auth ANTES da senha) recebem o mesmo texto: outra mensagem
 * revelaria, sem a senha, que a conta existe e está bloqueada (D67). Quem tem a senha certa mas
 * está sem acesso no app (perfil inativo, sem vínculo) vê "sem acesso" depois de entrar
 * (requireArea).
 */
export function signInErrorMessage(error: AuthErrorLike): string {
  if (error.status === 429 || error.code === "over_request_rate_limit") {
    return AUTH_MESSAGES.tooManyAttempts;
  }
  if (error.status && error.status >= 400 && error.status < 500) {
    return AUTH_MESSAGES.invalidCredentials;
  }
  return AUTH_MESSAGES.signInUnavailable;
}

/** Erros esperados ao gravar a senha nova (não vão para o log do servidor). */
const EXPECTED_UPDATE_ERRORS = new Set(["same_password", "weak_password", "validation_failed"]);

export function isExpectedPasswordUpdateError(error: AuthErrorLike): boolean {
  return error.code !== undefined && EXPECTED_UPDATE_ERRORS.has(error.code);
}

/** Mensagem do erro ao gravar a senha nova (R2-APP-14: cada recusa do Auth com o seu texto). */
export function passwordUpdateErrorMessage(error: AuthErrorLike): string {
  switch (error.code) {
    case "same_password":
      return AUTH_MESSAGES.samePassword;
    case "weak_password":
      return AUTH_MESSAGES.weakPassword;
    case "validation_failed":
      return AUTH_MESSAGES.passwordTooLong;
    default:
      return AUTH_MESSAGES.passwordUpdateFailed;
  }
}
