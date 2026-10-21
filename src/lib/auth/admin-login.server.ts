import "server-only";

import { headers } from "next/headers";

import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

import { adminLoginDetails, hasActiveAdminMembership, ipTrustFromEnv } from "./admin-login";

type ServerClient = Awaited<ReturnType<typeof createClient>>;

/**
 * Complementa o registro do login de admin com o contexto que só o servidor conhece: o ip de fonte
 * confiável (D68) e o user_agent (`admin_login_context` no audit_log). O login em si ("login de
 * admin", exigência de LGPD/segurança) é gravado pelo próprio Auth, pelo hook Custom Access Token
 * (`private.custom_access_token_hook`, D79), inclusive quando alguém entra direto na API pública do
 * Auth sem passar por este app. O contexto é gravado por `log_admin_login`, que só a chave secreta
 * executa: o navegador não grava um contexto inventado nem enche a trilha. O banco confere de novo o
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

  const details = adminLoginDetails(await headers(), ipTrustFromEnv(process.env));
  const { error: logError } = await createAdminClient().rpc("log_admin_login", {
    p_actor_id: userId,
    p_ip: details.ip,
    p_user_agent: details.user_agent,
  });
  if (logError) {
    console.error(
      "[auth] falha ao registrar o contexto do login de admin",
      logError.code ?? logError.message,
    );
  }
}
