"use server";

import type { AuthError } from "@supabase/supabase-js";
import { redirect } from "next/navigation";

import { AUTH_MESSAGES } from "@/lib/auth/messages";
import { hasRecoverySession } from "@/lib/auth/recovery.server";
import { type FieldErrors, firstFieldErrors, formText, redefinirSchema } from "@/lib/auth/schemas";
import { createClient } from "@/lib/supabase/server";

export type RedefinirState = {
  error?: string;
  /** A sessão de recuperação acabou: mostrar o caminho para pedir outro link. */
  expired?: boolean;
  fieldErrors?: FieldErrors<"password" | "confirmPassword">;
};

function updateErrorMessage(error: AuthError): string {
  if (error.code === "same_password") return AUTH_MESSAGES.samePassword;
  if (error.code === "weak_password") return AUTH_MESSAGES.weakPassword;
  return AUTH_MESSAGES.passwordUpdateFailed;
}

/**
 * Grava a nova senha. Exige a sessão criada pelo link de recuperação (conferida de novo aqui).
 * Depois encerra todas as sessões da conta e pede login com a senha nova.
 */
export async function updatePassword(
  _previous: RedefinirState,
  formData: FormData,
): Promise<RedefinirState> {
  const parsed = redefinirSchema.safeParse({
    password: formText(formData, "password"),
    confirmPassword: formText(formData, "confirmPassword"),
  });
  if (!parsed.success) {
    return { fieldErrors: firstFieldErrors(parsed.error) };
  }

  const supabase = await createClient();
  if (!(await hasRecoverySession(supabase))) {
    return { error: AUTH_MESSAGES.recoveryRequired, expired: true };
  }

  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) {
    if (error.code !== "same_password" && error.code !== "weak_password") {
      console.error("[auth] falha ao redefinir a senha", error.code ?? error.status);
    }
    return { error: updateErrorMessage(error) };
  }

  const { error: signOutError } = await supabase.auth.signOut({ scope: "global" });
  if (signOutError) console.error("[auth] falha ao encerrar sessões", signOutError.code);
  redirect("/login?aviso=senha-alterada");
}
