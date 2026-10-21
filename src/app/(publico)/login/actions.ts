"use server";

import { redirect } from "next/navigation";

import { auditAdminLogin } from "@/lib/auth/admin-login.server";
import { signInErrorMessage } from "@/lib/auth/errors";
import { safeNextPath } from "@/lib/auth/roles";
import { type FieldErrors, firstFieldErrors, formText, loginSchema } from "@/lib/auth/schemas";
import { SIGN_IN_FAILURE_MIN_MS, startTimer, waitUntilElapsed } from "@/lib/auth/timing";
import { createClient } from "@/lib/supabase/server";

export type LoginState = {
  error?: string;
  fieldErrors?: FieldErrors<"email" | "password">;
  email?: string;
};

/**
 * Login com e-mail e senha. Valida no servidor e volta para `next` (só caminhos do próprio site,
 * normalizados). Toda recusa do Auth tem o mesmo texto e o mesmo tempo mínimo de resposta, exista
 * ou não a conta (D67).
 */
export async function signIn(_previous: LoginState, formData: FormData): Promise<LoginState> {
  const parsed = loginSchema.safeParse({
    email: formText(formData, "email"),
    password: formText(formData, "password"),
    next: formText(formData, "next") || undefined,
  });
  const typedEmail = formText(formData, "email").trim().slice(0, 254);
  if (!parsed.success) {
    return { fieldErrors: firstFieldErrors(parsed.error), email: typedEmail };
  }

  const startedAt = startTimer();
  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({
    email: parsed.data.email,
    password: parsed.data.password,
  });
  if (error) {
    if (!error.status || error.status >= 500) {
      console.error("[auth] falha no login", error.code ?? error.message);
    }
    await waitUntilElapsed(startedAt, SIGN_IN_FAILURE_MIN_MS);
    return { error: signInErrorMessage(error), email: typedEmail };
  }

  // Login de admin fica no audit_log, registrado aqui no servidor
  await auditAdminLogin(supabase, data.user.id);

  redirect(safeNextPath(parsed.data.next));
}
