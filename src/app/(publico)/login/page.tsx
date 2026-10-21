import type { Metadata } from "next";

import { Notice } from "@/components/ui/notice";
import { AUTH_MESSAGES, lookupMessage } from "@/lib/auth/messages";
import { safeNextPath } from "@/lib/auth/roles";

import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Entrar" };

const ERRORS: Readonly<Record<string, string>> = {
  "sem-acesso": AUTH_MESSAGES.noAccess,
  "link-invalido": AUTH_MESSAGES.invalidLink,
  "outro-navegador": AUTH_MESSAGES.linkOtherBrowser,
};

const NOTICES: Readonly<Record<string, string>> = {
  "senha-alterada": AUTH_MESSAGES.passwordChanged,
};

function single(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

export default async function LoginPage({ searchParams }: PageProps<"/login">) {
  const params = await searchParams;
  const erro = single(params.erro);
  const aviso = single(params.aviso);
  const next = safeNextPath(single(params.next));
  const errorMessage = lookupMessage(ERRORS, erro);
  const noticeMessage = lookupMessage(NOTICES, aviso);

  return (
    <>
      <h1 className="type-title-1 text-text">Entrar</h1>
      <p className="mt-1.5 mb-6 text-text-muted">Use o e-mail e a senha da sua conta.</p>
      {errorMessage ? (
        <Notice tone="error" className="mb-5">
          {errorMessage}
        </Notice>
      ) : null}
      {noticeMessage ? (
        <Notice tone="success" className="mb-5">
          {noticeMessage}
        </Notice>
      ) : null}
      <LoginForm next={next} />
    </>
  );
}
