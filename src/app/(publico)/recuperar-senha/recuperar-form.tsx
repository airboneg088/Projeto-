"use client";

import Link from "next/link";
import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/notice";
import { TextField } from "@/components/ui/text-field";
import { AUTH_MESSAGES } from "@/lib/auth/messages";
import { recuperarSchema } from "@/lib/auth/schemas";
import { useClientValidation } from "@/lib/auth/use-client-validation";

import { type RecuperarState, requestPasswordReset } from "./actions";

const initialState: RecuperarState = {};
const FIELDS = ["email"] as const;

export function RecuperarForm() {
  const [state, formAction, pending] = useActionState(requestPasswordReset, initialState);
  const { clientErrors, onSubmit } = useClientValidation(recuperarSchema, FIELDS);

  return (
    <form action={formAction} onSubmit={onSubmit} noValidate className="flex flex-col gap-5">
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
        error={clientErrors.email ?? state.fieldErrors?.email}
      />
      <Button type="submit" block loading={pending} loadingLabel="Enviando…">
        Enviar link
      </Button>
      <Link href="/login" className="link self-center">
        Voltar para o login
      </Link>
    </form>
  );
}
