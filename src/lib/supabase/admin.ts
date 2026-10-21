import "server-only";

import { createClient } from "@supabase/supabase-js";

import { getPublicEnv } from "@/lib/env";
import { getServerEnv } from "@/lib/env.server";

import type { Database } from "./database.types";

/**
 * Cliente administrativo com a chave secreta (SUPABASE_SECRET_KEY): IGNORA a RLS.
 * Somente no servidor, para tarefas que a RLS não cobre (ex.: criar usuários na administração).
 * Hoje só registra o login de admin (`log_admin_login`, que só a chave secreta executa). Toda
 * chamada deve checar o papel de quem pediu antes.
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
