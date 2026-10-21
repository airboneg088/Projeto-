"use server";

import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

/** Sai da conta neste aparelho e volta para o login. */
export async function signOut(): Promise<void> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) {
    const { error } = await supabase.auth.signOut({ scope: "local" });
    if (error) console.error("[auth] falha ao sair", error.code ?? error.message);
  }
  redirect("/login");
}
