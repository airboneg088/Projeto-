import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

import { type Page, expect, test } from "@playwright/test";

import { SENHA_SEED, USUARIO_RECUPERACAO, entrar, sair } from "./fixtures/usuarios";

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
  const novaSenha = `NovaSenha#${Date.now().toString(36)}`;

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

  // Fluxo completo com a senha nova.
  await redefinirPeloEmail(page, USUARIO_RECUPERACAO.email, novaSenha);
  await entrar(page, USUARIO_RECUPERACAO, novaSenha);
  await expect(page).toHaveURL(new RegExp(`${USUARIO_RECUPERACAO.inicio}$`));
  await sair(page);

  // Devolve a senha do seed para os outros testes (e o outro viewport) da mesma rodada.
  await redefinirPeloEmail(page, USUARIO_RECUPERACAO.email, SENHA_SEED);
  await entrar(page, USUARIO_RECUPERACAO);
  await expect(page).toHaveURL(new RegExp(`${USUARIO_RECUPERACAO.inicio}$`));
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
