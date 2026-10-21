"use server";

import type { AuthError } from "@supabase/supabase-js";
import { redirect } from "next/navigation";

import { auditAdminLogin } from "@/lib/auth/admin-login.server";
import { AUTH_MESSAGES } from "@/lib/auth/messages";
import { safeNextPath } from "@/lib/auth/roles";
import { type FieldErrors, firstFieldErrors, formText, loginSchema } from "@/lib/auth/schemas";
import { createClient } from "@/lib/supabase/server";

export type LoginState = {
  error?: string;
  fieldErrors?: FieldErrors<"email" | "password">;
  email?: string;
};

function signInErrorMessage(error: AuthError): string {
  if (error.status === 429 || error.code === "over_request_rate_limit") {
    return AUTH_MESSAGES.tooManyAttempts;
  }
  if (error.code === "user_banned") {
    return AUTH_MESSAGES.noAccess;
  }
  if (error.status && error.status >= 400 && error.status < 500) {
    return AUTH_MESSAGES.invalidCredentials;
  }
  return AUTH_MESSAGES.signInUnavailable;
}

/** Login com e-mail e senha. Valida no servidor e volta para `next` (só caminhos do próprio site). */
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

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({
    email: parsed.data.email,
    password: parsed.data.password,
  });
  if (error) {
    if (!error.status || error.status >= 500) {
      console.error("[auth] falha no login", error.code ?? error.message);
    }
    return { error: signInErrorMessage(error), email: typedEmail };
  }

  // Login de admin fica no audit_log, registrado aqui no servidor
  await auditAdminLogin(supabase, data.user.id);

  redirect(safeNextPath(parsed.data.next));
}
