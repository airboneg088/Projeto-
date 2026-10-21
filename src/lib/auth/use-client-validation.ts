"use client";

import { type FormEvent, useState } from "react";
import type { z } from "zod";

import { type FieldErrors, validateFormFields } from "./schemas";

/**
 * Validação no cliente antes de chamar a Server Action (D91): com entrada inválida, o formulário
 * não é enviado e os erros aparecem na hora, com os mesmos textos do servidor. Com entrada válida,
 * segue para a Server Action, que valida de novo.
 */
export function useClientValidation<T extends string>(schema: z.ZodType, fields: readonly T[]) {
  const [clientErrors, setClientErrors] = useState<FieldErrors<T>>({});

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    const errors = validateFormFields(schema, new FormData(event.currentTarget), fields);
    if (errors) {
      // O React não chama a action de um <form> cujo submit foi cancelado
      event.preventDefault();
      setClientErrors(errors);
      return;
    }
    setClientErrors({});
  }

  return { clientErrors, onSubmit };
}
