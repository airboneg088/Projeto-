/**
 * Sessão de recuperação de senha: criada pelo link do e-mail (/auth/confirm, fluxo PKCE).
 * O JWT traz `amr` com o método "recovery". Outros métodos não contam, inclusive "otp" (é o que
 * um link de login por e-mail, "magic link", gera; ver D62).
 */

export const RECOVERY_WINDOW_SECONDS = 60 * 60;

type AmrEntry = { method?: unknown; timestamp?: unknown };

/** `true` se as claims vêm de um link de recuperação aberto há no máximo 1 hora. */
export function isRecentRecovery(claims: unknown, nowSeconds: number): boolean {
  if (!claims || typeof claims !== "object" || !("amr" in claims)) return false;
  const amr = (claims as { amr?: unknown }).amr;
  if (!Array.isArray(amr)) return false;
  return amr.some((entry: AmrEntry) => {
    if (!entry || typeof entry !== "object") return false;
    if (entry.method !== "recovery") return false;
    if (typeof entry.timestamp !== "number") return false;
    const age = nowSeconds - entry.timestamp;
    return age >= -60 && age <= RECOVERY_WINDOW_SECONDS;
  });
}

/** E-mail das claims (para mostrar de qual conta é a nova senha), ou `null`. */
export function emailFromClaims(claims: unknown): string | null {
  if (!claims || typeof claims !== "object" || !("email" in claims)) return null;
  const email = (claims as { email?: unknown }).email;
  return typeof email === "string" && email.length > 0 ? email : null;
}

/**
 * Erros da troca do código PKCE que significam "este navegador não é o que pediu o link" (ou o
 * link já foi usado aqui): o `code_verifier` não está neste navegador ou não confere. O link só
 * funciona uma vez e no mesmo aparelho e navegador em que a pessoa pediu a nova senha (D62, D80).
 */
const OTHER_BROWSER_CODES: ReadonlySet<string> = new Set([
  "pkce_code_verifier_not_found",
  "bad_code_verifier",
  "flow_state_not_found",
]);

/** Chave de `/login?erro=` para uma troca de código que falhou. */
export function recoveryLinkError(code: string | undefined): "outro-navegador" | "link-invalido" {
  return code !== undefined && OTHER_BROWSER_CODES.has(code) ? "outro-navegador" : "link-invalido";
}
