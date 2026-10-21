import { z } from "zod";

/**
 * Esquemas de validação dos formulários de autenticação. Usados no cliente (dicas imediatas)
 * e SEMPRE de novo no servidor, dentro das Server Actions.
 */

// Sem o modo JIT do zod 4: ele testa `new Function("")` para compilar o parser, e a CSP do app não
// tem 'unsafe-eval' (no navegador isso vira uma violação de CSP reportada). Os esquemas são
// pequenos; a diferença de desempenho não aparece.
z.config({ jitless: true });

const MSG = {
  emailRequired: "Informe o e-mail.",
  emailInvalid: "Confira o e-mail. Ele precisa ter o formato nome@exemplo.com.",
  passwordRequired: "Informe a senha.",
  passwordMin: "A senha precisa ter pelo menos 8 caracteres.",
  passwordMax: "A senha pode ter no máximo 72 caracteres.",
  passwordBytes:
    "A senha pode ter no máximo 72 caracteres (letras com acento, ç e emojis contam como mais de um).",
  passwordLetter: "A senha precisa ter pelo menos uma letra de A a Z (sem acento).",
  passwordDigit: "A senha precisa ter pelo menos um número.",
  confirmRequired: "Repita a nova senha.",
  mismatch: "As senhas não são iguais. Digite a mesma senha nos dois campos.",
} as const;

export const PASSWORD_MIN_LENGTH = 8;
/** Limite do GoTrue (bcrypt usa no máximo 72 bytes; o GoTrue recusa senha maior). */
export const PASSWORD_MAX_LENGTH = 72;

/** Tamanho da senha em bytes UTF-8 (o limite do Auth é em bytes, não em caracteres). */
export function utf8Length(value: string): number {
  return new TextEncoder().encode(value).length;
}

/**
 * Senha nova: as mesmas regras do Auth (`minimum_password_length = 8` e
 * `password_requirements = "letters_digits"` no supabase/config.toml; D65). "Letra" para o Auth é
 * só de A a Z: "ç" e letras acentuadas não contam.
 */
export const newPasswordField = z
  .string({ error: MSG.passwordRequired })
  .min(PASSWORD_MIN_LENGTH, { error: MSG.passwordMin })
  .max(PASSWORD_MAX_LENGTH, { error: MSG.passwordMax })
  .refine((value) => utf8Length(value) <= PASSWORD_MAX_LENGTH, { error: MSG.passwordBytes })
  .refine((value) => /[A-Za-z]/.test(value), { error: MSG.passwordLetter })
  .refine((value) => /[0-9]/.test(value), { error: MSG.passwordDigit });

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
    password: newPasswordField,
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

/**
 * Valida no cliente, com o mesmo esquema do servidor, os campos `fields` do formulário (zod no
 * cliente e no servidor; D91). Devolve os erros por campo, ou `null` se estiver tudo certo. O
 * servidor valida de novo sempre (a Server Action não confia no cliente).
 */
export function validateFormFields<T extends string>(
  schema: z.ZodType,
  formData: FormData,
  fields: readonly T[],
): FieldErrors<T> | null {
  const parsed = schema.safeParse(
    Object.fromEntries(fields.map((field) => [field, formText(formData, field)])),
  );
  return parsed.success ? null : firstFieldErrors<T>(parsed.error);
}

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
