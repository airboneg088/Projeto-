"use client";

import Link from "next/link";
import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/notice";
import { TextField } from "@/components/ui/text-field";

import { type RedefinirState, updatePassword } from "./actions";

const initialState: RedefinirState = {};

export function RedefinirForm() {
  const [state, formAction, pending] = useActionState(updatePassword, initialState);

  return (
    <form action={formAction} noValidate className="flex flex-col gap-5">
      {state.error ? (
        <Notice tone="error">
          {state.error}
          {state.expired ? (
            <>
              {" "}
              <Link href="/recuperar-senha" className="underline underline-offset-2">
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
        hint="Pelo menos 8 caracteres."
        minLength={8}
        maxLength={72}
        required
        error={state.fieldErrors?.password}
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
        error={state.fieldErrors?.confirmPassword}
      />
      <Button type="submit" block disabled={pending}>
        {pending ? "Salvando…" : "Salvar nova senha"}
      </Button>
    </form>
  );
}
