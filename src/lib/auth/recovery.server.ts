import "server-only";

import { createClient } from "@/lib/supabase/server";

import { emailFromClaims, isRecentRecovery } from "./recovery";

type ServerClient = Awaited<ReturnType<typeof createClient>>;

export type RecoverySession = { email: string | null };

/** Sessão atual, se veio de um link de recuperação recente (conferida no Auth); senão `null`. */
export async function getRecoverySession(supabase: ServerClient): Promise<RecoverySession | null> {
  const { data, error } = await supabase.auth.getClaims();
  if (error || !data) return null;
  if (!isRecentRecovery(data.claims, Math.floor(Date.now() / 1000))) return null;
  return { email: emailFromClaims(data.claims) };
}

/** Confere (no Auth) se a sessão atual veio de um link de recuperação recente. */
export async function hasRecoverySession(supabase: ServerClient): Promise<boolean> {
  return (await getRecoverySession(supabase)) !== null;
}
