import { describe, expect, it } from "vitest";

import {
  firstFieldErrors,
  formText,
  loginSchema,
  recuperarSchema,
  redefinirSchema,
} from "./schemas";

describe("loginSchema", () => {
  it("aceita e normaliza o e-mail", () => {
    const result = loginSchema.safeParse({
      email: "  Gerente.Primavera@Exemplo.LOCAL ",
      password: "Exemplo#2026",
    });
    expect(result.success).toBe(true);
    expect(result.data?.email).toBe("gerente.primavera@exemplo.local");
  });

  it("não mexe na senha", () => {
    const result = loginSchema.safeParse({ email: "a@b.co", password: " com espaço " });
    expect(result.data?.password).toBe(" com espaço ");
  });

  it("explica e-mail vazio, e-mail inválido e senha vazia", () => {
    const empty = loginSchema.safeParse({ email: "", password: "" });
    expect(empty.success).toBe(false);
    expect(firstFieldErrors(empty.error!)).toEqual({
      email: "Informe o e-mail.",
      password: "Informe a senha.",
    });

    const invalid = loginSchema.safeParse({ email: "nome@", password: "x" });
    expect(firstFieldErrors(invalid.error!)).toEqual({
      email: "Confira o e-mail. Ele precisa ter o formato nome@exemplo.com.",
    });
  });

  it("rejeita tipos inesperados e senha longa demais", () => {
    expect(loginSchema.safeParse({ email: 1, password: null }).success).toBe(false);
    expect(loginSchema.safeParse({ email: "a@b.co", password: "x".repeat(73) }).success).toBe(
      false,
    );
  });
});

describe("recuperarSchema", () => {
  it("exige um e-mail válido", () => {
    expect(
      recuperarSchema.safeParse({ email: "colaborador1.primavera@exemplo.local" }).success,
    ).toBe(true);
    const result = recuperarSchema.safeParse({ email: "sem-arroba" });
    expect(firstFieldErrors(result.error!).email).toMatch(/Confira o e-mail/);
  });
});

describe("redefinirSchema", () => {
  it("aceita senhas iguais com 8+ caracteres", () => {
    expect(
      redefinirSchema.safeParse({ password: "NovaSenha#1", confirmPassword: "NovaSenha#1" })
        .success,
    ).toBe(true);
  });

  it("exige pelo menos 8 caracteres", () => {
    const result = redefinirSchema.safeParse({ password: "curta", confirmPassword: "curta" });
    expect(firstFieldErrors(result.error!).password).toBe(
      "A senha precisa ter pelo menos 8 caracteres.",
    );
  });

  it("limita a 72 caracteres", () => {
    const long = "a".repeat(73);
    const result = redefinirSchema.safeParse({ password: long, confirmPassword: long });
    expect(firstFieldErrors(result.error!).password).toBe(
      "A senha pode ter no máximo 72 caracteres.",
    );
  });

  it("aponta a confirmação quando as senhas não batem", () => {
    const result = redefinirSchema.safeParse({
      password: "NovaSenha#1",
      confirmPassword: "NovaSenha#2",
    });
    expect(result.success).toBe(false);
    expect(firstFieldErrors(result.error!)).toEqual({
      confirmPassword: "As senhas não são iguais. Digite a mesma senha nos dois campos.",
    });
  });

  it("pede a confirmação quando ela está vazia", () => {
    const result = redefinirSchema.safeParse({ password: "NovaSenha#1", confirmPassword: "" });
    expect(firstFieldErrors(result.error!).confirmPassword).toBe("Repita a nova senha.");
  });
});

describe("formText", () => {
  it("lê texto e trata ausência e arquivo como vazio", () => {
    const form = new FormData();
    form.set("email", "a@b.co");
    form.set("arquivo", new Blob(["x"]), "x.txt");
    expect(formText(form, "email")).toBe("a@b.co");
    expect(formText(form, "arquivo")).toBe("");
    expect(formText(form, "faltando")).toBe("");
  });
});
