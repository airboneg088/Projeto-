import type { Metadata } from "next";
import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";
import { AUTH_MESSAGES } from "@/lib/auth/messages";
import { getRecoverySession } from "@/lib/auth/recovery.server";
import { createClient } from "@/lib/supabase/server";

import { RedefinirForm } from "./redefinir-form";

export const metadata: Metadata = { title: "Nova senha" };

export default async function RedefinirSenhaPage() {
  const supabase = await createClient();
  const recovery = await getRecoverySession(supabase);

  if (!recovery) {
    return (
      <>
        <h1 className="type-title-1 text-text">Criar nova senha</h1>
        <p className="mt-1.5 mb-6 text-text-muted">{AUTH_MESSAGES.recoveryRequired}</p>
        <Link href="/recuperar-senha" className={buttonVariants({ block: true })}>
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
      <h1 className="type-title-1 text-text">Criar nova senha</h1>
      <p className="mt-1.5 mb-6 text-text-muted">
        {recovery.email ? (
          <>
            Escolha uma senha nova para a conta{" "}
            <strong className="break-all text-text" data-testid="conta-recuperacao">
              {recovery.email}
            </strong>
            .
          </>
        ) : (
          "Escolha uma senha nova para a sua conta."
        )}
      </p>
      <RedefinirForm />
    </>
  );
}
