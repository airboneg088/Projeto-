import { z } from "zod";

/**
 * Esquemas de validação dos formulários de autenticação. Usados no cliente (dicas imediatas)
 * e SEMPRE de novo no servidor, dentro das Server Actions.
 */

const MSG = {
  emailRequired: "Informe o e-mail.",
  emailInvalid: "Confira o e-mail. Ele precisa ter o formato nome@exemplo.com.",
  passwordRequired: "Informe a senha.",
  passwordMin: "A senha precisa ter pelo menos 8 caracteres.",
  passwordMax: "A senha pode ter no máximo 72 caracteres.",
  confirmRequired: "Repita a nova senha.",
  mismatch: "As senhas não são iguais. Digite a mesma senha nos dois campos.",
} as const;

export const PASSWORD_MIN_LENGTH = 8;
/** Limite do GoTrue (bcrypt usa no máximo 72 bytes). */
export const PASSWORD_MAX_LENGTH = 72;

export const emailField = z
  .string({ error: MSG.emailRequired })
  .trim()
  .min(1, { error: MSG.emailRequired })
  .max(254, { error: MSG.emailInvalid })
  .toLowerCase()
  .pipe(z.email({ error: MSG.emailInvalid }));

export const loginSchema = z.object({
  email: emailField,
  password: z
    .string({ error: MSG.passwordRequired })
    .min(1, { error: MSG.passwordRequired })
    .max(PASSWORD_MAX_LENGTH, { error: MSG.passwordMax }),
  next: z.string().max(2048).optional(),
});
export type LoginInput = z.infer<typeof loginSchema>;

export const recuperarSchema = z.object({
  email: emailField,
});
export type RecuperarInput = z.infer<typeof recuperarSchema>;

export const redefinirSchema = z
  .object({
    password: z
      .string({ error: MSG.passwordRequired })
      .min(PASSWORD_MIN_LENGTH, { error: MSG.passwordMin })
      .max(PASSWORD_MAX_LENGTH, { error: MSG.passwordMax }),
    confirmPassword: z
      .string({ error: MSG.confirmRequired })
      .min(1, { error: MSG.confirmRequired }),
  })
  .refine((data) => data.password === data.confirmPassword, {
    path: ["confirmPassword"],
    error: MSG.mismatch,
  });
export type RedefinirInput = z.infer<typeof redefinirSchema>;

/** Lê um campo de texto do FormData (arquivos e ausência viram string vazia). */
export function formText(formData: FormData, name: string): string {
  const value = formData.get(name);
  return typeof value === "string" ? value : "";
}

export type FieldErrors<T extends string> = Partial<Record<T, string>>;

/** Primeira mensagem de erro de cada campo. */
export function firstFieldErrors<T extends string>(error: z.ZodError): FieldErrors<T> {
  const result: Partial<Record<string, string>> = {};
  for (const issue of error.issues) {
    const key = issue.path[0];
    if (typeof key === "string" && result[key] === undefined) {
      result[key] = issue.message;
    }
  }
  return result as FieldErrors<T>;
}
