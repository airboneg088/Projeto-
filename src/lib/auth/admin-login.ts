import { isIP } from "node:net";

import { type MembershipLike, isMembershipActive } from "./access";

/** Contexto do login de admin enviado a `log_admin_login` (o banco ainda valida o ip e corta o user_agent). */
export type AdminLoginDetails = { ip?: string; user_agent?: string };

/**
 * De onde vem um ip de cliente confiável (D68):
 * - `vercel`: a borda da Vercel grava `x-real-ip` (e `x-vercel-forwarded-for`) com o ip de quem
 *   conectou e sobrescreve o que o cliente mandar nesses cabeçalhos;
 * - `none`: sem proxy confiável na frente (local, `next start`). Qualquer `x-forwarded-for` ou
 *   `x-real-ip` foi escrito pelo próprio cliente, então o ip não é registrado.
 * O 1º valor de `x-forwarded-for` nunca é usado: atrás de um proxy que acrescenta (nginx, a
 * maioria dos balanceadores), ele é escolhido pelo cliente.
 */
export type IpTrust = "vercel" | "none";

/** Fonte confiável deste ambiente: Vercel (variável de sistema `VERCEL=1`) ou nenhuma. */
export function ipTrustFromEnv(env: Readonly<Record<string, string | undefined>>): IpTrust {
  return env.VERCEL === "1" ? "vercel" : "none";
}

type HeaderReader = { get(name: string): string | null };

const MAX_USER_AGENT = 300;

/** Ip do cliente lido só de fonte confiável e só se for um endereço válido; senão `undefined`. */
export function trustedClientIp(headers: HeaderReader, trust: IpTrust): string | undefined {
  if (trust !== "vercel") return undefined;
  const candidate =
    headers.get("x-real-ip") ?? headers.get("x-vercel-forwarded-for")?.split(",")[0] ?? null;
  const ip = candidate?.trim();
  return ip && isIP(ip) !== 0 ? ip : undefined;
}

/**
 * Monta os detalhes do registro de login de admin a partir dos cabeçalhos do pedido: o ip de
 * fonte confiável (trustedClientIp) e o `user-agent` (informado pelo cliente; só descritivo),
 * cortado e sem campos vazios.
 */
export function adminLoginDetails(headers: HeaderReader, trust: IpTrust): AdminLoginDetails {
  const details: AdminLoginDetails = {};
  const ip = trustedClientIp(headers, trust);
  if (ip) details.ip = ip;
  const agent = headers.get("user-agent")?.trim().slice(0, MAX_USER_AGENT);
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
