import { redirect } from "next/navigation";
import type { NextRequest } from "next/server";
import { z } from "zod";

import { auditAdminLogin } from "@/lib/auth/admin-login.server";
import { recoveryLinkError } from "@/lib/auth/recovery";
import { hasRecoverySession } from "@/lib/auth/recovery.server";
import { createClient } from "@/lib/supabase/server";

const querySchema = z.object({
  code: z.string().min(1).max(512),
});

const INVALID_LINK = "/login?erro=link-invalido";
/** Único destino: o link de e-mail que o app envia hoje é só o de recuperação de senha. */
const RECOVERY_PAGE = "/redefinir-senha";

/**
 * Destino do link de recuperação de senha enviado por e-mail (D62).
 *
 * Aceita só o fluxo PKCE (`?code=`) iniciado por `resetPasswordForEmail` neste navegador: a troca
 * do código exige o `code_verifier` gravado no cookie de quem pediu o link, então um link aberto
 * em outro navegador (ou mandado por outra pessoa) não cria sessão; a tela de login diz que o link
 * precisa ser aberto no mesmo aparelho e navegador (D80). O caminho `token_hash` saiu:
 * não é amarrado ao navegador e o Auth aceita o token de um link de login por e-mail ("magic
 * link") como `type=recovery`, o que permitia trocar a sessão de quem abrisse o link.
 *
 * Depois da troca, confere no Auth que a sessão é de recuperação (`amr` "recovery"); qualquer
 * outra é encerrada. O destino é sempre /redefinir-senha (o `next` da URL é ignorado).
 */
export async function GET(request: NextRequest) {
  const parsed = querySchema.safeParse({
    code: request.nextUrl.searchParams.get("code") ?? undefined,
  });
  if (!parsed.success) redirect(INVALID_LINK);

  const supabase = await createClient();
  const { data, error } = await supabase.auth.exchangeCodeForSession(parsed.data.code);
  if (error) {
    console.error("[auth] link inválido (code)", error.code ?? error.status);
    // Código sem o code_verifier deste navegador: o link foi aberto em outro aparelho/navegador
    // (ou já foi usado aqui). A mensagem diz isso, em vez de "expirou" (D80).
    redirect(`/login?erro=${recoveryLinkError(error.code)}`);
  }

  if (!(await hasRecoverySession(supabase))) {
    console.error("[auth] link de e-mail que não é de recuperação; sessão encerrada");
    const { error: signOutError } = await supabase.auth.signOut({ scope: "local" });
    if (signOutError) console.error("[auth] falha ao encerrar a sessão", signOutError.code);
    redirect(INVALID_LINK);
  }

  // Entrar por link de e-mail também é login: o de admin fica no audit_log
  await auditAdminLogin(supabase, data.user.id);
  redirect(RECOVERY_PAGE);
}
