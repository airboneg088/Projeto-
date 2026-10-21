import "server-only";

import type { User } from "@supabase/supabase-js";
import { redirect } from "next/navigation";
import { cache } from "react";

import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/supabase/database.types";

import { type AccessDecision, decideAccess, isMembershipActive, rolesFrom } from "./access";
import { type Area, type Role } from "./roles";

export type Profile = Pick<Tables<"profiles">, "id" | "full_name" | "status">;
export type Membership = Pick<
  Tables<"memberships">,
  "id" | "role" | "organization_id" | "store_id" | "sector_id" | "starts_at" | "ends_at"
>;
export type StoreSummary = Pick<Tables<"stores">, "id" | "name">;

export type UserContext = {
  user: User;
  profile: Profile | null;
  /** Vínculos vigentes agora (starts_at <= agora e ends_at nulo ou no futuro). */
  activeMemberships: Membership[];
  roles: Role[];
  /** Lojas dos vínculos vigentes (vazio para quem só tem vínculo de rede). */
  stores: StoreSummary[];
  /** Tem vínculo de rede (owner/admin com store_id nulo). */
  networkWide: boolean;
};

/**
 * Pessoa logada, perfil, vínculos vigentes, papéis e lojas, lidos com o cliente do usuário
 * (passa pela RLS). Memorizado por pedido: layout e página compartilham a mesma leitura.
 * `null` quando não há sessão válida (validada no Auth com getUser()).
 */
export const getUserContext = cache(async (): Promise<UserContext | null> => {
  const supabase = await createClient();
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();
  if (userError || !user) return null;

  const [profileResult, membershipsResult] = await Promise.all([
    supabase.from("profiles").select("id, full_name, status").eq("id", user.id).maybeSingle(),
    supabase
      .from("memberships")
      .select("id, role, organization_id, store_id, sector_id, starts_at, ends_at")
      .eq("profile_id", user.id),
  ]);
  if (profileResult.error) {
    throw new Error("Não foi possível carregar o perfil.", { cause: profileResult.error });
  }
  if (membershipsResult.error) {
    throw new Error("Não foi possível carregar os vínculos.", { cause: membershipsResult.error });
  }

  const now = new Date();
  const activeMemberships = membershipsResult.data.filter((m) => isMembershipActive(m, now));
  const roles = rolesFrom(activeMemberships);
  const storeIds = [
    ...new Set(activeMemberships.map((m) => m.store_id).filter((id): id is string => !!id)),
  ];

  let stores: StoreSummary[] = [];
  if (storeIds.length > 0) {
    const storesResult = await supabase
      .from("stores")
      .select("id, name")
      .in("id", storeIds)
      .order("name");
    if (storesResult.error) {
      throw new Error("Não foi possível carregar as lojas.", { cause: storesResult.error });
    }
    stores = storesResult.data;
  }

  return {
    user,
    profile: profileResult.data,
    activeMemberships,
    roles,
    stores,
    networkWide: activeMemberships.some((m) => m.store_id === null),
  };
});

/**
 * Encerra a sessão no Auth. Em Server Components os cookies não podem ser apagados aqui, mas a
 * sessão deixa de valer no servidor e o proxy limpa os cookies no próximo pedido.
 */
async function signOutQuietly() {
  try {
    const supabase = await createClient();
    await supabase.auth.signOut({ scope: "local" });
  } catch (error) {
    console.error("[auth] falha ao encerrar a sessão", error);
  }
}

async function enforce(decision: AccessDecision): Promise<void> {
  switch (decision.kind) {
    case "ok":
      return;
    case "login":
      redirect(decision.to);
    case "sem-acesso":
      await signOutQuietly();
      redirect(decision.to);
    case "redirect":
      redirect(decision.to);
  }
}

function accessInput(ctx: UserContext | null) {
  return ctx ? { profileStatus: ctx.profile?.status ?? null, roles: ctx.roles } : null;
}

/**
 * Exige acesso à área. Sem sessão → /login?next=…; perfil inativo ou sem vínculo vigente →
 * encerra a sessão e vai para /login?erro=sem-acesso; papel sem acesso → página do papel.
 */
export async function requireArea(area: Area): Promise<UserContext> {
  const ctx = await getUserContext();
  await enforce(decideAccess(accessInput(ctx), area));
  // decideAccess só devolve "ok" com contexto presente.
  return ctx as UserContext;
}

/** Para "/": sempre redireciona (login, sem acesso ou página inicial do papel). */
export async function redirectToHome(): Promise<never> {
  const ctx = await getUserContext();
  await enforce(decideAccess(accessInput(ctx), null));
  // decideAccess(…, null) nunca devolve "ok"; por garantia, volta ao login.
  redirect("/login");
}
