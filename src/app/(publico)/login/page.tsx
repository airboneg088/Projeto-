import type { Metadata } from "next";

import { Notice } from "@/components/ui/notice";
import { AUTH_MESSAGES } from "@/lib/auth/messages";
import { safeNextPath } from "@/lib/auth/roles";

import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Entrar" };

const ERRORS: Readonly<Record<string, string>> = {
  "sem-acesso": AUTH_MESSAGES.noAccess,
  "link-invalido": AUTH_MESSAGES.invalidLink,
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
  const errorMessage = erro ? ERRORS[erro] : undefined;
  const noticeMessage = aviso ? NOTICES[aviso] : undefined;

  return (
    <>
      <h1 className="mb-6 text-2xl font-semibold">Entrar</h1>
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
