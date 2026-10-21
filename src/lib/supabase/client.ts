import { createBrowserClient } from "@supabase/ssr";

import { getPublicEnv } from "@/lib/env";

import type { Database } from "./database.types";

/**
 * Cliente Supabase do navegador (Client Components). Só usa a chave publicável;
 * os dados são protegidos pela RLS. Nunca importe chaves secretas aqui.
 */
export function createClient() {
  const env = getPublicEnv();
  return createBrowserClient<Database>(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );
}
