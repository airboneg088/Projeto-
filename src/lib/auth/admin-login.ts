import { type MembershipLike, isMembershipActive } from "./access";

/** Detalhes do login de admin enviados a `log_admin_login` (o banco ainda valida o ip e corta o user_agent). */
export type AdminLoginDetails = { ip?: string; user_agent?: string };

const MAX_IP = 64;
const MAX_USER_AGENT = 300;

/**
 * Monta os detalhes do registro de login de admin a partir dos cabeçalhos do pedido:
 * o 1º endereço de `x-forwarded-for` (na Vercel, o proxy grava o ip real do cliente) e o
 * `user-agent`, cortados e sem campos vazios.
 */
export function adminLoginDetails(
  forwardedFor: string | null,
  userAgent: string | null,
): AdminLoginDetails {
  const details: AdminLoginDetails = {};
  const ip = forwardedFor?.split(",")[0]?.trim().slice(0, MAX_IP);
  if (ip) details.ip = ip;
  const agent = userAgent?.trim().slice(0, MAX_USER_AGENT);
  if (agent) details.user_agent = agent;
  return details;
}

/** Tem vínculo de admin de rede (store_id nulo) vigente agora? */
export function hasActiveAdminMembership(
  memberships: readonly MembershipLike[],
  now: Date,
): boolean {
  return memberships.some(
    (m) => m.role === "admin" && m.store_id === null && isMembershipActive(m, now),
  );
}
