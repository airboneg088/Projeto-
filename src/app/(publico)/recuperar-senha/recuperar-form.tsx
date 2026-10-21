"use client";

import Link from "next/link";
import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/notice";
import { TextField } from "@/components/ui/text-field";
import { AUTH_MESSAGES } from "@/lib/auth/messages";

import { type RecuperarState, requestPasswordReset } from "./actions";

const initialState: RecuperarState = {};

export function RecuperarForm() {
  const [state, formAction, pending] = useActionState(requestPasswordReset, initialState);

  return (
    <form action={formAction} noValidate className="flex flex-col gap-5">
      {state.sent ? <Notice tone="success">{AUTH_MESSAGES.resetSent}</Notice> : null}
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
        error={state.fieldErrors?.email}
      />
      <Button type="submit" block disabled={pending}>
        {pending ? "Enviando…" : "Enviar link"}
      </Button>
      <Link href="/login" className="link self-center">
        Voltar para o login
      </Link>
    </form>
  );
}
