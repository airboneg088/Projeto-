import "server-only";

import { headers } from "next/headers";

import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

import { adminLoginDetails, hasActiveAdminMembership } from "./admin-login";

type ServerClient = Awaited<ReturnType<typeof createClient>>;

/**
 * Registra no audit_log o login de quem tem vínculo vigente de admin (exigência de LGPD/segurança:
 * "login de admin"). Roda no servidor logo depois do login. O registro é gravado por
 * `log_admin_login`, que só a chave secreta executa: o navegador não consegue gravar um login
 * inventado (com ip/user_agent escolhidos por ele) nem encher a trilha. O banco confere de novo o
 * vínculo de admin, aceita só ip válido e user_agent curto e grava no máximo um registro por admin
 * por minuto. Falha ao registrar não impede o login (fica no log do servidor).
 */
export async function auditAdminLogin(supabase: ServerClient, userId: string): Promise<void> {
  const { data, error } = await supabase
    .from("memberships")
    .select("role, store_id, starts_at, ends_at")
    .eq("profile_id", userId)
    .eq("role", "admin");
  if (error) {
    console.error("[auth] falha ao conferir vínculo de admin", error.code ?? error.message);
    return;
  }
  if (!hasActiveAdminMembership(data, new Date())) return;

  const requestHeaders = await headers();
  const details = adminLoginDetails(
    requestHeaders.get("x-forwarded-for"),
    requestHeaders.get("user-agent"),
  );
  const { error: logError } = await createAdminClient().rpc("log_admin_login", {
    p_actor_id: userId,
    p_ip: details.ip,
    p_user_agent: details.user_agent,
  });
  if (logError) {
    console.error("[auth] falha ao registrar login de admin", logError.code ?? logError.message);
  }
}
