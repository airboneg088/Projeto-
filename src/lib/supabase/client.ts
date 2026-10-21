import { createBrowserClient } from "@supabase/ssr";

import { getPublicEnv } from "@/lib/env";

import type { Database } from "./database.types";

/**
 * Cliente Supabase do navegador (Client Components). Só usa a chave publicável;
 * os dados são protegidos pela RLS. Nunca importe chaves secretas aqui.
 *
 * ATENÇÃO (D63): o cookie da sessão é HttpOnly, então este cliente NÃO enxerga quem está logado
 * (chama a API como anônimo, e a RLS nega). Leituras e gravações de quem está logado passam pelo
 * servidor (Server Components, Server Actions e Route Handlers, como o POST /api/sync da Fase 3).
 * Hoje nenhum arquivo importa este cliente.
 */
export function createClient() {
  const env = getPublicEnv();
  return createBrowserClient<Database>(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );
}
