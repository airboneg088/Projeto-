import { type Area, type Role, AREA_PATH, canAccess, homeFor, isRole, primaryRole } from "./roles";

/** Linha mínima de `memberships` usada para decidir acesso. */
export type MembershipLike = {
  role: string;
  store_id: string | null;
  starts_at: string;
  ends_at: string | null;
};

/** Vínculo vigente: começou (starts_at <= agora) e não terminou (ends_at nulo ou > agora). */
export function isMembershipActive(membership: MembershipLike, now: Date): boolean {
  const startsAt = Date.parse(membership.starts_at);
  if (Number.isNaN(startsAt) || startsAt > now.getTime()) return false;
  if (membership.ends_at === null) return true;
  const endsAt = Date.parse(membership.ends_at);
  return !Number.isNaN(endsAt) && endsAt > now.getTime();
}

/** Papéis distintos dos vínculos (ignora valores desconhecidos). */
export function rolesFrom(memberships: readonly MembershipLike[]): Role[] {
  const roles = new Set<Role>();
  for (const membership of memberships) {
    if (isRole(membership.role)) roles.add(membership.role);
  }
  return [...roles];
}

export type AccessInput = {
  profileStatus: string | null;
  roles: readonly Role[];
};

export type AccessDecision =
  | { kind: "login"; to: string }
  | { kind: "sem-acesso"; to: string }
  | { kind: "redirect"; to: string }
  | { kind: "ok" };

export const NO_ACCESS_PATH = "/login?erro=sem-acesso";

/** Caminho do login com o retorno em `next` ("/" dispensa o parâmetro). */
export function loginPathFor(next: string): string {
  return next === "/" ? "/login" : `/login?next=${encodeURIComponent(next)}`;
}

/**
 * Decide o que fazer com um pedido para `area` (ou para "/" quando `area` é null).
 * - sem sessão → login com `next`;
 * - perfil inativo/ausente ou sem vínculo vigente → sair e mostrar "sem acesso";
 * - área de outro papel → página inicial do papel principal.
 */
export function decideAccess(input: AccessInput | null, area: Area | null): AccessDecision {
  if (input === null) {
    return { kind: "login", to: loginPathFor(area ? AREA_PATH[area] : "/") };
  }
  const main = primaryRole(input.roles);
  if (input.profileStatus !== "active" || main === null) {
    return { kind: "sem-acesso", to: NO_ACCESS_PATH };
  }
  if (area === null || !canAccess(area, input.roles)) {
    return { kind: "redirect", to: homeFor(main) };
  }
  return { kind: "ok" };
}
