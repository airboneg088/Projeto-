/**
 * Sessão de recuperação de senha: criada pelo link do e-mail (/auth/confirm).
 * O JWT traz `amr` com o método "recovery" (fluxo com code) ou "otp" (fluxo com token_hash).
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
    if (entry.method !== "recovery" && entry.method !== "otp") return false;
    if (typeof entry.timestamp !== "number") return false;
    const age = nowSeconds - entry.timestamp;
    return age >= -60 && age <= RECOVERY_WINDOW_SECONDS;
  });
}
