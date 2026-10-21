import "server-only";

import { createClient } from "@supabase/supabase-js";

import { getPublicEnv } from "@/lib/env";
import { getServerEnv } from "@/lib/env.server";

import type { Database } from "./database.types";

/**
 * Cliente administrativo com a chave secreta (SUPABASE_SECRET_KEY): IGNORA a RLS.
 * Somente no servidor, para tarefas que a RLS não cobre (ex.: criar usuários na administração).
 * Hoje registra o contexto do login de admin (`log_admin_login`, que só a chave secreta executa) e
 * assina URLs de leitura do storage depois da conferência como o usuário
 * (`src/lib/storage/signed-url.server.ts`, D77). Toda chamada deve checar o acesso de quem pediu antes.
 */
export function createAdminClient() {
  const { NEXT_PUBLIC_SUPABASE_URL } = getPublicEnv();
  const { SUPABASE_SECRET_KEY } = getServerEnv();
  return createClient<Database>(NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SECRET_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
}
