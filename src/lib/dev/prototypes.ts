import "server-only";

import { notFound } from "next/navigation";

/**
 * Páginas de protótipo (/prototipo/*) só existem com ENABLE_PROTOTYPES=1 no ambiente do
 * servidor, lido a cada pedido (não é embutido no build). Sem a variável — o padrão, inclusive
 * em produção — respondem 404. Ver docs/dev-local.md e D116.
 */
export function prototypesEnabled(): boolean {
  return process.env.ENABLE_PROTOTYPES === "1";
}

/** Chame no layout E na página (eles renderizam em paralelo). */
export function assertPrototypesEnabled(): void {
  if (!prototypesEnabled()) notFound();
}
