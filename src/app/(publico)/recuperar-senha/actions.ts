"use server";

import { getPublicEnv } from "@/lib/env";
import { type FieldErrors, firstFieldErrors, formText, recuperarSchema } from "@/lib/auth/schemas";
import { PASSWORD_RESET_MIN_MS, startTimer, waitUntilElapsed } from "@/lib/auth/timing";
import { createClient } from "@/lib/supabase/server";

export type RecuperarState = {
  sent?: boolean;
  fieldErrors?: FieldErrors<"email">;
  email?: string;
};

/**
 * Pede o link de recuperação. A resposta é SEMPRE a mesma mensagem neutra, exista ou não a
 * conta, e leva sempre o mesmo tempo mínimo (o Auth demora mais quando envia o e-mail), para não
 * revelar quais e-mails estão cadastrados (D67).
 */
export async function requestPasswordReset(
  _previous: RecuperarState,
  formData: FormData,
): Promise<RecuperarState> {
  const typedEmail = formText(formData, "email").trim().slice(0, 254);
  const parsed = recuperarSchema.safeParse({ email: formText(formData, "email") });
  if (!parsed.success) {
    return { fieldErrors: firstFieldErrors(parsed.error), email: typedEmail };
  }

  const startedAt = startTimer();
  const supabase = await createClient();
  const { NEXT_PUBLIC_SITE_URL } = getPublicEnv();
  // O link volta para /auth/confirm, que só aceita a recuperação e sempre leva a /redefinir-senha.
  const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
    redirectTo: `${NEXT_PUBLIC_SITE_URL}/auth/confirm`,
  });
  if (error) {
    // Sem o e-mail no log (dado pessoal). A resposta ao usuário não muda.
    console.error("[auth] falha ao pedir recuperação de senha", error.code ?? error.status);
  }
  await waitUntilElapsed(startedAt, PASSWORD_RESET_MIN_MS);
  return { sent: true, email: typedEmail };
}
