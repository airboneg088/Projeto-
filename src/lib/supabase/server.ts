import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

import { getPublicEnv } from "@/lib/env";

import type { Database } from "./database.types";

/**
 * Cliente Supabase do servidor (Server Components, Server Actions e Route Handlers), com a sessão
 * nos cookies. Usa a chave publicável: tudo passa pela RLS do usuário logado.
 * Crie um cliente novo a cada pedido; nunca compartilhe entre pedidos.
 *
 * Decisões de acesso usam `auth.getUser()` ou `auth.getClaims()` (validados no Auth),
 * nunca `auth.getSession()` (lê o cookie sem validar).
 */
export async function createClient() {
  const cookieStore = await cookies();
  const env = getPublicEnv();

  return createServerClient<Database>(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, options);
            }
          } catch {
            // Server Components não podem gravar cookies. O proxy (src/proxy.ts) renova a
            // sessão a cada pedido, então ignorar aqui é seguro.
          }
        },
      },
    },
  );
}
