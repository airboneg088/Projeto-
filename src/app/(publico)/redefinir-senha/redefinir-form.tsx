"use client";

import Link from "next/link";
import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/notice";
import { TextField } from "@/components/ui/text-field";
import { redefinirSchema } from "@/lib/auth/schemas";
import { useClientValidation } from "@/lib/auth/use-client-validation";

import { type RedefinirState, updatePassword } from "./actions";

const initialState: RedefinirState = {};
const FIELDS = ["password", "confirmPassword"] as const;

export function RedefinirForm() {
  const [state, formAction, pending] = useActionState(updatePassword, initialState);
  const { clientErrors, onSubmit } = useClientValidation(redefinirSchema, FIELDS);

  return (
    <form action={formAction} onSubmit={onSubmit} noValidate className="flex flex-col gap-5">
      {state.error ? (
        <Notice tone="error">
          {state.error}
          {state.expired ? (
            <>
              {" "}
              <Link href="/recuperar-senha" className="font-semibold underline underline-offset-4">
                Pedir um novo link
              </Link>
            </>
          ) : null}
        </Notice>
      ) : null}
      <TextField
        id="password"
        name="password"
        type="password"
        label="Nova senha"
        autoComplete="new-password"
        hint="Pelo menos 8 caracteres, com letras (A a Z) e números."
        minLength={8}
        maxLength={72}
        required
        error={clientErrors.password ?? state.fieldErrors?.password}
      />
      <TextField
        id="confirmPassword"
        name="confirmPassword"
        type="password"
        label="Confirmar nova senha"
        autoComplete="new-password"
        minLength={8}
        maxLength={72}
        required
        error={clientErrors.confirmPassword ?? state.fieldErrors?.confirmPassword}
      />
      <Button type="submit" block loading={pending} loadingLabel="Salvando…">
        Salvar nova senha
      </Button>
    </form>
  );
}
