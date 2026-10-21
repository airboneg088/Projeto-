import type { Metadata } from "next";
import Link from "next/link";

import { AUTH_MESSAGES } from "@/lib/auth/messages";
import { hasRecoverySession } from "@/lib/auth/recovery.server";
import { createClient } from "@/lib/supabase/server";

import { RedefinirForm } from "./redefinir-form";

export const metadata: Metadata = { title: "Nova senha" };

export default async function RedefinirSenhaPage() {
  const supabase = await createClient();
  const allowed = await hasRecoverySession(supabase);

  if (!allowed) {
    return (
      <>
        <h1 className="mb-2 text-2xl font-semibold">Criar nova senha</h1>
        <p className="mb-6 text-text-muted">{AUTH_MESSAGES.recoveryRequired}</p>
        <Link href="/recuperar-senha" className="btn btn-primary btn-block">
          Pedir um novo link
        </Link>
        <p className="mt-4 text-center">
          <Link href="/login" className="link">
            Voltar para o login
          </Link>
        </p>
      </>
    );
  }

  return (
    <>
      <h1 className="mb-2 text-2xl font-semibold">Criar nova senha</h1>
      <p className="mb-6 text-text-muted">Escolha uma senha nova para a sua conta.</p>
      <RedefinirForm />
    </>
  );
}
