import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

import { type Page, expect, test } from "@playwright/test";

import { envLocal } from "./fixtures/env";
import { SENHA_SEED, USUARIOS, USUARIO_RECUPERACAO, entrar, sair } from "./fixtures/usuarios";

const MAIL_DIR = process.env.E2E_MAIL_DIR ?? "/home/user/Projeto-/.local/mail";
const MENSAGEM_ENVIO =
  "Se o e-mail estiver cadastrado, você vai receber um link para criar uma nova senha.";

/** Decodifica quoted-printable (RFC 2045): quebras suaves "=\r\n" e bytes "=XX" em UTF-8. */
function decodeQuotedPrintable(input: string): string {
  const withoutSoftBreaks = input.replace(/=\r?\n/g, "");
  const bytes: number[] = [];
  for (let i = 0; i < withoutSoftBreaks.length; i += 1) {
    const char = withoutSoftBreaks[i]!;
    const hex = withoutSoftBreaks.slice(i + 1, i + 3);
    if (char === "=" && /^[0-9A-F]{2}$/i.test(hex)) {
      bytes.push(parseInt(hex, 16));
      i += 2;
    } else {
      bytes.push(...Buffer.from(char, "utf8"));
    }
  }
  return Buffer.from(bytes).toString("utf8");
}

function listEml(): string[] {
  return readdirSync(MAIL_DIR).filter((name) => name.endsWith(".eml"));
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Assunto (decodificado) do e-mail novo para `to` com o texto `contains` no assunto. */
function newSubjectTo(
  to: string,
  before: ReadonlySet<string>,
  contains: string,
): string | undefined {
  for (const name of readdirSync(MAIL_DIR)) {
    if (!name.endsWith(".json") || before.has(name.replace(/\.json$/, ".eml"))) continue;
    const mail = JSON.parse(readFileSync(join(MAIL_DIR, name), "utf8")) as {
      subject?: string;
      to?: string[] | string;
    };
    if (String(mail.to ?? "").includes(to) && mail.subject?.includes(contains)) return mail.subject;
  }
  return undefined;
}

/** Corpo decodificado do .eml mais novo para `to` entre os arquivos que não estavam em `before`. */
function newMailTo(to: string, before: ReadonlySet<string>): string | undefined {
  const candidates = listEml()
    .filter((name) => !before.has(name))
    .map((name) => ({ path: join(MAIL_DIR, name), mtime: statSync(join(MAIL_DIR, name)).mtimeMs }))
    .sort((a, b) => b.mtime - a.mtime);
  for (const file of candidates) {
    const raw = readFileSync(file.path, "utf8");
    const headerEnd = raw.search(/\r?\n\r?\n/);
    const headers = raw.slice(0, headerEnd).replace(/\r?\n[ \t]+/g, " ");
    if (!new RegExp(`^To:.*${escapeRegExp(to)}`, "im").test(headers)) continue;
    return /quoted-printable/i.test(raw) ? decodeQuotedPrintable(raw) : raw;
  }
  return undefined;
}

/**
 * Pede o link em /recuperar-senha e devolve o link do e-mail novo. A tela responde sempre a
 * mesma mensagem (por desenho), mesmo quando o Auth segura o envio pelo intervalo mínimo entre
 * e-mails (max_frequency); por isso tenta de novo se o e-mail não chegar.
 */
async function pedirLink(page: Page, email: string): Promise<string> {
  for (let tentativa = 1; tentativa <= 3; tentativa += 1) {
    const before = new Set(listEml());
    await page.goto("/recuperar-senha");
    await page.getByLabel("E-mail").fill(email);
    await page.getByRole("button", { name: "Enviar link" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Se o e-mail" })).toHaveText(
      MENSAGEM_ENVIO,
    );
    let corpo: string | undefined;
    try {
      await expect
        .poll(() => (corpo = newMailTo(email, before)) !== undefined, { timeout: 5_000 })
        .toBe(true);
    } catch {
      await page.waitForTimeout(2_000);
      continue;
    }
    const link = corpo!.match(/https?:\/\/[^\s"'<>]+\/auth\/v1\/verify\?[^\s"'<>]+/)?.[0];
    expect(link, "link de recuperação no e-mail").toBeTruthy();
    return link!.replace(/&amp;/g, "&");
  }
  throw new Error(`nenhum e-mail de recuperação para ${email} em ${MAIL_DIR}`);
}

/** Pede o link, abre o link do e-mail e grava `novaSenha`. */
async function redefinirPeloEmail(page: Page, email: string, novaSenha: string) {
  const link = await pedirLink(page, email);
  await page.goto(link);
  await expect(page).toHaveURL(/\/redefinir-senha$/);
  // A tela diz de qual conta é a senha nova (troca de sessão nunca é silenciosa).
  await expect(page.getByTestId("conta-recuperacao")).toHaveText(email);
  await page.getByLabel("Nova senha", { exact: true }).fill(novaSenha);
  await page.getByLabel("Confirmar nova senha").fill(novaSenha);
  await page.getByRole("button", { name: "Salvar nova senha" }).click();
  await expect(page).toHaveURL(/\/login\?aviso=senha-alterada$/);
  await expect(page.getByRole("status").filter({ hasText: "Senha alterada" })).toHaveText(
    "Senha alterada. Entre com a nova senha.",
  );
}

test("recuperação de senha: pedir link, abrir, criar senha nova e entrar com ela", async ({
  page,
}) => {
  test.slow();
  // Letras e número garantidos (password_requirements = "letters_digits").
  const novaSenha = `NovaSenha#1${Date.now().toString(36)}`;

  await page.goto("/login");
  await page.getByRole("link", { name: "Esqueci minha senha" }).click();
  await expect(page).toHaveURL(/\/recuperar-senha$/);

  // Confirmação diferente da senha: a tela explica e não grava.
  await page.goto(await pedirLink(page, USUARIO_RECUPERACAO.email));
  await expect(page).toHaveURL(/\/redefinir-senha$/);
  await page.getByLabel("Nova senha", { exact: true }).fill(novaSenha);
  await page.getByLabel("Confirmar nova senha").fill(`${novaSenha}x`);
  await page.getByRole("button", { name: "Salvar nova senha" }).click();
  await expect(page.getByText("As senhas não são iguais.", { exact: false })).toBeVisible();
  await expect(page).toHaveURL(/\/redefinir-senha$/);

  // R2-APP-14: a política real (letras e números, 72 bytes) aparece com a mensagem certa.
  for (const [fraca, mensagem] of [
    ["12345678", "A senha precisa ter pelo menos uma letra de A a Z (sem acento)."],
    ["somenteletras", "A senha precisa ter pelo menos um número."],
    [
      `${"ç".repeat(40)}a1`,
      "A senha pode ter no máximo 72 caracteres (letras com acento, ç e emojis contam como mais de um).",
    ],
  ] as const) {
    await page.getByLabel("Nova senha", { exact: true }).fill(fraca);
    await page.getByLabel("Confirmar nova senha").fill(fraca);
    await page.getByRole("button", { name: "Salvar nova senha" }).click();
    await expect(page.getByText(mensagem)).toBeVisible();
    await expect(page).toHaveURL(/\/redefinir-senha$/);
  }

  // Fluxo completo com a senha nova; o Auth avisa a troca por e-mail (R2-APP-03).
  const antesDoAviso = new Set(listEml());
  await redefinirPeloEmail(page, USUARIO_RECUPERACAO.email, novaSenha);
  await expect
    .poll(() => newSubjectTo(USUARIO_RECUPERACAO.email, antesDoAviso, "foi alterada"), {
      timeout: 5_000,
    })
    .toBe("Sua senha do Éde Gestão foi alterada");
  await entrar(page, USUARIO_RECUPERACAO, novaSenha);
  await expect(page).toHaveURL(new RegExp(`${USUARIO_RECUPERACAO.inicio}$`));
  await sair(page);

  // Devolve a senha do seed para os outros testes (e o outro viewport) da mesma rodada.
  await redefinirPeloEmail(page, USUARIO_RECUPERACAO.email, SENHA_SEED);
  await entrar(page, USUARIO_RECUPERACAO);
  await expect(page).toHaveURL(new RegExp(`${USUARIO_RECUPERACAO.inicio}$`));
});

// R3-CRITERIOS-01: o e-mail é em pt-BR e só traz o link (o app não tem onde digitar código); o
// link aberto em outro navegador (outro celular, o app instalado) diz o motivo, não "expirou".
test("e-mail de recuperação em pt-BR e link aberto em outro navegador explica o que fazer", async ({
  page,
  browser,
}) => {
  const email = "colaborador2.parqueamerica@exemplo.local";
  const antes = new Set(listEml());
  const link = await pedirLink(page, email);

  expect(newSubjectTo(email, antes, "nova senha")).toBe("Crie uma nova senha do Éde Gestão");
  const corpo = newMailTo(email, antes) ?? "";
  expect(corpo).toContain("Criar nova senha");
  expect(corpo).toContain("no mesmo aparelho e navegador");
  // Sem o texto padrão do Auth em inglês e sem o código de 6 dígitos ("enter the code")
  expect(corpo).not.toMatch(/Reset|code|código/i);

  const outro = await browser.newContext();
  try {
    const outraAba = await outro.newPage();
    await outraAba.goto(link);
    await expect(outraAba).toHaveURL(/\/login\?erro=outro-navegador$/);
    await expect(
      outraAba.getByText("no mesmo aparelho e navegador em que você pediu a nova senha", {
        exact: false,
      }),
    ).toBeVisible();
  } finally {
    await outro.close();
  }
});

test("recuperar senha responde igual para e-mail que não existe", async ({ page }) => {
  await page.goto("/recuperar-senha");
  await page.getByLabel("E-mail").fill("ninguem.cadastrado@exemplo.local");
  await page.getByRole("button", { name: "Enviar link" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Se o e-mail" })).toHaveText(
    MENSAGEM_ENVIO,
  );
});

test("/redefinir-senha sem o link explica o que fazer", async ({ page }) => {
  await page.goto("/redefinir-senha");
  await expect(page.getByText("abra o link que enviamos para o seu e-mail")).toBeVisible();
  await expect(page.getByRole("link", { name: "Pedir um novo link" })).toHaveAttribute(
    "href",
    "/recuperar-senha",
  );
});

// R2-APP-06: /auth/confirm só aceita o fluxo PKCE de recuperação. O token_hash (que o Auth aceita
// como recovery mesmo quando é de um link de login) não cria mais sessão.
test("/auth/confirm recusa token_hash e não troca a sessão de quem está logado", async ({
  page,
  context,
}) => {
  const secret = envLocal("SUPABASE_SECRET_KEY");
  const api = envLocal("NEXT_PUBLIC_SUPABASE_URL");
  const gerado = await page.request.post(`${api}/auth/v1/admin/generate_link`, {
    headers: { apikey: secret, authorization: `Bearer ${secret}` },
    data: { type: "recovery", email: USUARIO_RECUPERACAO.email },
  });
  expect(gerado.status()).toBe(200);
  const { hashed_token: tokenHash } = (await gerado.json()) as { hashed_token: string };

  await entrar(page, USUARIOS.gerentePrimavera);
  for (const type of ["recovery", "magiclink", "email"]) {
    await page.goto(`/auth/confirm?token_hash=${tokenHash}&type=${type}&next=/gerente`);
    await expect(page).toHaveURL(/\/login\?erro=link-invalido$|\/gerente$/);
  }
  // Continua a mesma pessoa (a sessão do gerente não foi trocada pela da conta do link).
  await page.goto("/");
  await expect(page).toHaveURL(/\/gerente$/);
  await expect(page.getByTestId("usuario-papel")).toHaveText("Gerente");
  expect((await context.cookies()).some((c) => /^sb-.*-auth-token/.test(c.name))).toBe(true);
});

test("/auth/confirm sem sessão e com token_hash vai para o aviso de link inválido", async ({
  page,
}) => {
  await page.goto("/auth/confirm?token_hash=abc&type=recovery");
  await expect(page).toHaveURL(/\/login\?erro=link-invalido$/);
  await expect(page.getByText("O link expirou ou já foi usado.", { exact: false })).toBeVisible();
});

// R2-APP-02: com a chave publicável, /magiclink e /otp mandavam um e-mail de login (que o
// /auth/confirm aceitava) para qualquer conta. O login por link de e-mail está desligado.
test("login por link de e-mail (magic link) está desligado no Auth", async ({ request }) => {
  const api = envLocal("NEXT_PUBLIC_SUPABASE_URL");
  const apikey = envLocal("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
  const before = new Set(listEml());
  for (const [path, data] of [
    ["/auth/v1/magiclink", { email: USUARIOS.colaborador1Primavera.email }],
    ["/auth/v1/otp", { email: USUARIOS.colaborador1Primavera.email, create_user: false }],
  ] as const) {
    const response = await request.post(`${api}${path}`, { headers: { apikey }, data });
    expect(response.status(), path).toBe(422);
    expect(((await response.json()) as { error_code?: string }).error_code, path).toBe(
      "email_provider_disabled",
    );
  }
  await esperar(1_000);
  expect(newMailTo(USUARIOS.colaborador1Primavera.email, before)).toBeUndefined();
});

function esperar(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
