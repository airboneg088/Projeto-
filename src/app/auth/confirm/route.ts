import type { EmailOtpType } from "@supabase/supabase-js";
import { redirect } from "next/navigation";
import type { NextRequest } from "next/server";
import { z } from "zod";

import { auditAdminLogin } from "@/lib/auth/admin-login.server";
import { safeNextPath } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

const OTP_TYPES = [
  "recovery",
  "email",
  "invite",
  "magiclink",
  "signup",
  "email_change",
] as const satisfies readonly EmailOtpType[];

const querySchema = z.object({
  code: z.string().min(1).max(512).optional(),
  token_hash: z.string().min(1).max(512).optional(),
  type: z.enum(OTP_TYPES).optional(),
  next: z.string().max(2048).optional(),
});

const INVALID_LINK = "/login?erro=link-invalido";

/**
 * Destino dos links enviados por e-mail (recuperação de senha e afins).
 * - `?code=` (fluxo PKCE padrão do Supabase): troca o código pela sessão;
 * - `?token_hash=&type=` (modelo de e-mail com TokenHash): valida o token.
 * Depois vai para `next` (só caminhos do próprio site); em falha, volta ao login com aviso.
 */
export async function GET(request: NextRequest) {
  const parsed = querySchema.safeParse(Object.fromEntries(request.nextUrl.searchParams));
  if (!parsed.success) redirect(INVALID_LINK);

  const { code, token_hash: tokenHash, type } = parsed.data;
  const next = safeNextPath(parsed.data.next);
  const supabase = await createClient();

  // Entrar por link de e-mail também é login: o de admin fica no audit_log
  if (code) {
    const { data, error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      await auditAdminLogin(supabase, data.user.id);
      redirect(next);
    }
    console.error("[auth] link inválido (code)", error.code ?? error.status);
  } else if (tokenHash && type) {
    const { data, error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
    if (!error) {
      if (data.user) await auditAdminLogin(supabase, data.user.id);
      redirect(next);
    }
    console.error("[auth] link inválido (token_hash)", error.code ?? error.status);
  }

  redirect(INVALID_LINK);
}
