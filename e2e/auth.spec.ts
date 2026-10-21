import { expect, test } from "@playwright/test";

import { SENHA_SEED, TODOS_OS_USUARIOS, USUARIOS, entrar, sair } from "./fixtures/usuarios";

test.describe("login por papel", () => {
  for (const usuario of [
    USUARIOS.proprietaria,
    USUARIOS.admin,
    USUARIOS.gerentePrimavera,
    USUARIOS.colaborador1Primavera,
  ]) {
    test(`${usuario.papel} entra e cai em ${usuario.inicio}`, async ({ page }) => {
      await entrar(page, usuario);
      await expect(page).toHaveURL(new RegExp(`${usuario.inicio}$`));
      await expect(page.getByTestId("usuario-papel")).toHaveText(usuario.rotulo);
      if (usuario.loja) await expect(page.getByTestId("usuario-lojas")).toHaveText(usuario.loja);
      await expect(page.getByRole("button", { name: "Sair" })).toBeVisible();
    });
  }

  test("todos os usuários do seed entram e caem na página do papel", async ({ page }) => {
    test.slow();
    for (const usuario of TODOS_OS_USUARIOS) {
      await entrar(page, usuario);
      await expect(page, usuario.email).toHaveURL(new RegExp(`${usuario.inicio}$`));
      await sair(page);
    }
  });
});

test("senha errada mostra a mensagem de erro", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("E-mail").fill(USUARIOS.gerentePrimavera.email);
  await page.getByLabel("Senha", { exact: true }).fill("senha-errada");
  await page.getByRole("button", { name: "Entrar" }).click();
  // Filtra pelo texto: o anunciador de rotas do Next também tem role="alert".
  await expect(
    page.getByRole("alert").filter({ hasText: "E-mail ou senha incorretos" }),
  ).toHaveText("E-mail ou senha incorretos. Confira e tente de novo.");
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByLabel("E-mail")).toHaveValue(USUARIOS.gerentePrimavera.email);
});

test("sem login, /gerente leva ao login e volta para /gerente depois", async ({ page }) => {
  await page.goto("/gerente");
  await expect(page).toHaveURL(/\/login\?next=%2Fgerente$/);
  await page.getByLabel("E-mail").fill(USUARIOS.gerentePrimavera.email);
  await page.getByLabel("Senha", { exact: true }).fill(SENHA_SEED);
  await page.getByRole("button", { name: "Entrar" }).click();
  await expect(page).toHaveURL(/\/gerente$/);
});

test("variações de maiúsculas e barra final não escapam da proteção", async ({ page }) => {
  for (const path of ["/GERENTE", "/Painel/", "/admin/", "/hoje/qualquer"]) {
    await page.goto(path);
    await expect(page, path).toHaveURL(/\/login\?next=/);
  }
});

test("colaborador não entra em /gerente, /painel nem /admin", async ({ page }) => {
  await entrar(page, USUARIOS.colaborador1Primavera);
  for (const path of ["/gerente", "/painel", "/admin"]) {
    await page.goto(path);
    await expect(page, path).toHaveURL(/\/hoje$/);
  }
});

test("gerente não entra em /painel nem /admin", async ({ page }) => {
  await entrar(page, USUARIOS.gerentePrimavera);
  for (const path of ["/painel", "/admin"]) {
    await page.goto(path);
    await expect(page, path).toHaveURL(/\/gerente$/);
  }
});

test("quem já está logado e abre /login vai para a sua página", async ({ page }) => {
  await entrar(page, USUARIOS.colaborador1Primavera);
  await page.goto("/login");
  await expect(page).toHaveURL(/\/hoje$/);
});

test("sair volta ao login e as páginas protegidas voltam a pedir login", async ({ page }) => {
  await entrar(page, USUARIOS.gerentePrimavera);
  await expect(page).toHaveURL(/\/gerente$/);
  await sair(page);
  for (const path of ["/gerente", "/hoje", "/"]) {
    await page.goto(path);
    await expect(page, path).toHaveURL(/\/login(\?next=.*)?$/);
  }
});

test("com a sessão perdida, Sair (Server Action) ainda leva ao login", async ({
  page,
  context,
}) => {
  await entrar(page, USUARIOS.colaborador1Primavera);
  await expect(page).toHaveURL(/\/hoje$/);
  await context.clearCookies();
  await page.getByRole("button", { name: "Sair" }).click();
  await expect(page).toHaveURL(/\/login\?next=%2Fhoje$/);
  await expect(page.getByRole("button", { name: "Entrar" })).toBeVisible();
});
