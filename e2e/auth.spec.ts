import { expect, test } from "@playwright/test";

import { envLocal } from "./fixtures/env";
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

test.describe("parâmetros da URL do login", () => {
  // R2-APP-01: "/.//evil.com" passava pela validação e o navegador saía para http://evil.com/
  // depois do login (x-action-redirect da Server Action).
  for (const next of ["/.//evil.com", "/x/..//evil.com", "/%2E//evil.com", "/.%2e//evil.com"]) {
    test(`next=${next} não sai do site depois do login`, async ({ page }) => {
      const externos: string[] = [];
      page.on("request", (request) => {
        const url = new URL(request.url());
        if (url.hostname !== "localhost" && url.hostname !== "127.0.0.1") externos.push(url.href);
      });
      await page.goto(`/login?next=${encodeURIComponent(next)}`);
      await expect(page.locator('input[name="next"]')).toHaveValue("/");
      await page.getByLabel("E-mail").fill(USUARIOS.gerentePrimavera.email);
      await page.getByLabel("Senha", { exact: true }).fill(SENHA_SEED);
      await page.getByRole("button", { name: "Entrar" }).click();
      await expect(page).toHaveURL(/^http:\/\/localhost:\d+\/gerente$/);
      expect(externos).toEqual([]);
    });
  }

  // R2-APP-10: caractere fora do Latin-1 no next dava 500 depois de criar a sessão.
  test("next com caracteres fora do Latin-1 entra sem erro", async ({ page }) => {
    await page.goto(`/login?next=${encodeURIComponent("/hoje?busca=ação。")}`);
    await expect(page.locator('input[name="next"]')).toHaveValue(
      "/hoje?busca=a%C3%A7%C3%A3o%E3%80%82",
    );
    await page.getByLabel("E-mail").fill(USUARIOS.colaborador1Primavera.email);
    await page.getByLabel("Senha", { exact: true }).fill(SENHA_SEED);
    await page.getByRole("button", { name: "Entrar" }).click();
    await expect(page).toHaveURL(/\/hoje\?busca=a%C3%A7%C3%A3o%E3%80%82$/);
    await expect(page.getByTestId("usuario-papel")).toHaveText("Colaborador");
  });

  // R2-APP-15: chaves do protótipo de Object quebravam a página com 500.
  for (const query of [
    "erro=__proto__",
    "erro=constructor",
    "erro=toString",
    "aviso=__proto__",
    "aviso=valueOf",
    "erro=hasOwnProperty&aviso=toString",
  ]) {
    test(`/login?${query} mostra o formulário`, async ({ page }) => {
      const response = await page.goto(`/login?${query}`);
      expect(response?.status()).toBe(200);
      await expect(page.getByRole("heading", { name: "Entrar" })).toBeVisible();
      await expect(page.getByRole("button", { name: "Entrar" })).toBeVisible();
    });
  }

  test("erro conhecido continua aparecendo", async ({ page }) => {
    await page.goto("/login?erro=sem-acesso");
    await expect(page.getByText("Seu acesso não está ativo.", { exact: false })).toBeVisible();
  });
});

// R2-APP-04: o padrão do @supabase/ssr era httpOnly false, sem Secure e 400 dias.
test("cookie da sessão: HttpOnly, Secure, SameSite=Lax, path / e 7 dias", async ({
  page,
  context,
}) => {
  await entrar(page, USUARIOS.colaborador1Primavera);
  const cookies = (await context.cookies()).filter((c) => /^sb-.*-auth-token/.test(c.name));
  expect(cookies.length).toBeGreaterThan(0);
  const now = Date.now() / 1000;
  for (const cookie of cookies) {
    expect(cookie.httpOnly, cookie.name).toBe(true);
    expect(cookie.secure, cookie.name).toBe(true);
    expect(cookie.sameSite, cookie.name).toBe("Lax");
    expect(cookie.path, cookie.name).toBe("/");
    const days = (cookie.expires - now) / 86400;
    expect(days, cookie.name).toBeGreaterThan(6.9);
    expect(days, cookie.name).toBeLessThanOrEqual(7.01);
  }
  // O JavaScript da página não enxerga o token.
  expect(await page.evaluate(() => document.cookie)).not.toMatch(/sb-.*-auth-token/);
});

// R2-APP-13: pedido negado recebia o título da área no HTML e no RSC.
test("área negada não devolve os metadados da área", async ({ page }) => {
  await entrar(page, USUARIOS.colaborador1Primavera);
  for (const [path, titulo] of [
    ["/gerente", "Gerência"],
    ["/painel", "Painel"],
    ["/admin", "Administração"],
  ] as const) {
    const html = await page.request.get(path, { maxRedirects: 0 });
    expect(html.status(), path).toBe(307);
    expect(html.headers()["location"], path).toMatch(/\/hoje$/);
    expect(await html.text(), `${path} (HTML)`).not.toContain(titulo);
    // O pedido RSC passa pelo redirecionamento "?_rsc" do Next; o corpo final também não leva.
    const rsc = await page.request.get(path, { headers: { RSC: "1" } });
    const rscBody = await rsc.text();
    expect(rscBody.length, `${path} (RSC)`).toBeGreaterThan(0);
    expect(rscBody, `${path} (RSC)`).not.toContain(titulo);
  }
  // A própria área continua com o título.
  await page.goto("/hoje");
  await expect(page).toHaveTitle("Hoje · Éde Gestão");
});

// R2-APP-08/09: a mesma mensagem e o mesmo tempo mínimo para conta existente e inexistente.
test("login recusado: mesma mensagem e tempo mínimo, exista ou não a conta", async ({ page }) => {
  const tempos: Record<string, number> = {};
  for (const email of [USUARIOS.gerentePrimavera.email, "ninguem.cadastrado@exemplo.local"]) {
    await page.goto("/login");
    await page.getByLabel("E-mail").fill(email);
    await page.getByLabel("Senha", { exact: true }).fill("senha-errada-1");
    const inicio = Date.now();
    await page.getByRole("button", { name: "Entrar" }).click();
    await expect(
      page.getByRole("alert").filter({ hasText: "E-mail ou senha incorretos" }),
    ).toHaveText("E-mail ou senha incorretos. Confira e tente de novo.");
    tempos[email] = Date.now() - inicio;
  }
  for (const [email, ms] of Object.entries(tempos)) expect(ms, email).toBeGreaterThanOrEqual(800);
});

// R3-CRITERIOS-04: zod também no cliente. Entrada inválida mostra o erro sem ir ao servidor.
test("e-mail inválido é recusado no navegador, sem enviar o formulário", async ({ page }) => {
  const posts: string[] = [];
  page.on("request", (request) => {
    if (request.method() === "POST") posts.push(request.url());
  });
  for (const [path, button] of [
    ["/login", "Entrar"],
    ["/recuperar-senha", "Enviar link"],
  ] as const) {
    await page.goto(path);
    await page.getByLabel("E-mail").fill("nao-e-email");
    if (path === "/login") await page.getByLabel("Senha", { exact: true }).fill("qualquer");
    await page.getByRole("button", { name: button }).click();
    await expect(
      page.getByText("Confira o e-mail. Ele precisa ter o formato nome@exemplo.com."),
    ).toBeVisible();
    await expect(page.getByLabel("E-mail")).toHaveValue("nao-e-email");
  }
  expect(posts).toEqual([]);
});

// R3-APP-05: o login de admin feito direto na API pública do Auth (sem passar pelo app) também
// fica no audit_log, gravado pelo próprio Auth (hook Custom Access Token, D79).
test("login de admin direto na API do Auth fica no audit_log", async ({ request }) => {
  const api = envLocal("NEXT_PUBLIC_SUPABASE_URL");
  const apikey = envLocal("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
  const secret = envLocal("SUPABASE_SECRET_KEY");

  const login = await request.post(`${api}/auth/v1/token?grant_type=password`, {
    headers: { apikey },
    data: { email: USUARIOS.admin.email, password: SENHA_SEED },
  });
  expect(login.status()).toBe(200);
  const { user, access_token: accessToken } = (await login.json()) as {
    user: { id: string };
    access_token: string;
  };
  // A sessão deste login, pelas claims do token que o Auth acabou de emitir
  const claims = JSON.parse(
    Buffer.from(accessToken.split(".")[1] ?? "", "base64url").toString("utf8"),
  ) as { session_id?: string };
  expect(claims.session_id).toBeTruthy();

  // Um registro por sessão (D102): este login tem o seu, com o método e a sessão
  const desde = new Date(Date.now() - 65_000).toISOString();
  const registros = await request.get(
    `${api}/rest/v1/audit_log?select=action,diff&action=eq.admin_login&actor_id=eq.${user.id}` +
      `&occurred_at=gte.${encodeURIComponent(desde)}`,
    { headers: { apikey: secret, authorization: `Bearer ${secret}` } },
  );
  expect(registros.status()).toBe(200);
  const linhas = (await registros.json()) as {
    action: string;
    diff: { metodo?: string; sessao?: string };
  }[];
  expect(linhas.length).toBeGreaterThanOrEqual(1);
  expect(linhas.every((linha) => linha.diff.metodo === "password")).toBe(true);
  expect(linhas.filter((linha) => linha.diff.sessao === claims.session_id)).toHaveLength(1);
});
