/**
 * Tempo mínimo de resposta das ações de autenticação (D67). O Auth responde mais rápido para
 * e-mail que não existe (não confere a senha) e mais devagar para quem existe (confere a senha ou
 * envia o e-mail de recuperação). Esperar até um piso fixo deixa as respostas do app iguais
 * também no tempo, além da mensagem.
 */

/** Piso das respostas de login recusado (senha errada, conta inexistente, bloqueada, limite). */
export const SIGN_IN_FAILURE_MIN_MS = 800;
/** Piso da resposta de "Esqueci minha senha" (inclui o envio do e-mail pelo Auth). */
export const PASSWORD_RESET_MIN_MS = 1500;

type Clock = { now: () => number; sleep: (ms: number) => Promise<void> };

const realClock: Clock = {
  now: () => performance.now(),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};

/** Marca o início de uma ação (relógio monotônico). */
export function startTimer(clock: Clock = realClock): number {
  return clock.now();
}

/**
 * Espera até `minMs` terem passado desde `startedAt`. Não espera se já passou. Repete a espera se
 * o timer acordar um pouco antes (o `setTimeout` pode adiantar frações de milissegundo).
 */
export async function waitUntilElapsed(
  startedAt: number,
  minMs: number,
  clock: Clock = realClock,
): Promise<void> {
  let remaining = minMs - (clock.now() - startedAt);
  while (remaining > 0) {
    await clock.sleep(Math.ceil(remaining));
    remaining = minMs - (clock.now() - startedAt);
  }
}
