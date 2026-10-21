import "server-only";

import { createClient } from "@/lib/supabase/server";

import { isRecentRecovery } from "./recovery";

type ServerClient = Awaited<ReturnType<typeof createClient>>;

/** Confere (no Auth) se a sessão atual veio de um link de recuperação recente. */
export async function hasRecoverySession(supabase: ServerClient): Promise<boolean> {
  const { data, error } = await supabase.auth.getClaims();
  if (error || !data) return false;
  return isRecentRecovery(data.claims, Math.floor(Date.now() / 1000));
}
