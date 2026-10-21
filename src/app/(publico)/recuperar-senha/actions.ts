"use server";

import { getPublicEnv } from "@/lib/env";
import { type FieldErrors, firstFieldErrors, formText, recuperarSchema } from "@/lib/auth/schemas";
import { createClient } from "@/lib/supabase/server";

export type RecuperarState = {
  sent?: boolean;
  fieldErrors?: FieldErrors<"email">;
  email?: string;
};

/**
 * Pede o link de recuperação. A resposta é SEMPRE a mesma mensagem neutra, exista ou não a
 * conta, para não revelar quais e-mails estão cadastrados.
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

  const supabase = await createClient();
  const { NEXT_PUBLIC_SITE_URL } = getPublicEnv();
  const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
    redirectTo: `${NEXT_PUBLIC_SITE_URL}/auth/confirm?next=/redefinir-senha`,
  });
  if (error) {
    // Sem o e-mail no log (dado pessoal). A resposta ao usuário não muda.
    console.error("[auth] falha ao pedir recuperação de senha", error.code ?? error.status);
  }
  return { sent: true, email: typedEmail };
}
