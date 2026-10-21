"use client";

import Link from "next/link";
import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/notice";
import { TextField } from "@/components/ui/text-field";
import { loginSchema } from "@/lib/auth/schemas";
import { useClientValidation } from "@/lib/auth/use-client-validation";

import { type LoginState, signIn } from "./actions";

const initialState: LoginState = {};
const FIELDS = ["email", "password"] as const;

export function LoginForm({ next }: { next: string }) {
  const [state, formAction, pending] = useActionState(signIn, initialState);
  const { clientErrors, onSubmit } = useClientValidation(loginSchema, FIELDS);

  return (
    <form action={formAction} onSubmit={onSubmit} noValidate className="flex flex-col gap-5">
      <input type="hidden" name="next" value={next} />
      {state.error ? <Notice tone="error">{state.error}</Notice> : null}
      <TextField
        id="email"
        name="email"
        type="email"
        label="E-mail"
        autoComplete="username"
        inputMode="email"
        autoCapitalize="none"
        spellCheck={false}
        required
        defaultValue={state.email}
        error={clientErrors.email ?? state.fieldErrors?.email}
      />
      <TextField
        id="password"
        name="password"
        type="password"
        label="Senha"
        autoComplete="current-password"
        required
        error={clientErrors.password ?? state.fieldErrors?.password}
      />
      <Button type="submit" block disabled={pending}>
        {pending ? "Entrando…" : "Entrar"}
      </Button>
      <Link href="/recuperar-senha" className="link self-center">
        Esqueci minha senha
      </Link>
    </form>
  );
}
