import { type APIResponse, type Response, expect, test } from "@playwright/test";

import { USUARIOS, entrar } from "./fixtures/usuarios";

type WithHeaders = Pick<Response | APIResponse, "headers">;

function expectSecurityHeaders(response: WithHeaders) {
  const headers = response.headers();
  const csp = headers["content-security-policy"] ?? "";
  expect(csp).toMatch(/script-src 'self' 'nonce-[A-Za-z0-9+/=]{16,}' 'strict-dynamic'/);
  expect(csp).toContain("default-src 'self'");
  expect(csp).toContain("frame-ancestors 'none'");
  expect(csp).toContain("object-src 'none'");
  expect(csp).toContain("base-uri 'self'");
  expect(csp).toContain("form-action 'self'");
  expect(csp).not.toContain("unsafe-eval");
  expect(headers["strict-transport-security"]).toBe("max-age=63072000; includeSubDomains; preload");
  expect(headers["x-frame-options"]).toBe("DENY");
  expect(headers["x-content-type-options"]).toBe("nosniff");
  expect(headers["referrer-policy"]).toBe("strict-origin-when-cross-origin");
  expect(headers["permissions-policy"]).toBe(
    "camera=(self), geolocation=(self), microphone=(), payment=()",
  );
  expect(headers["x-powered-by"]).toBeUndefined();
  return csp;
}

test("/login tem CSP com nonce e os cabeçalhos de segurança", async ({ request }) => {
  const response = await request.get("/login");
  expect(response.status()).toBe(200);
  const csp = expectSecurityHeaders(response);

  // O nonce é novo a cada resposta e todos os <script> do HTML usam o nonce do cabeçalho.
  const nonce = csp.match(/'nonce-([^']+)'/)?.[1];
  const html = await response.text();
  const scripts = html.match(/<script\b[^>]*>/g) ?? [];
  expect(scripts.length).toBeGreaterThan(0);
  for (const tag of scripts) expect(tag).toContain(`nonce="${nonce}"`);

  const again = await request.get("/login");
  expect(again.headers()["content-security-policy"]).not.toBe(csp);
});

test("página protegida também tem CSP e cabeçalhos de segurança", async ({ page }) => {
  await entrar(page, USUARIOS.colaborador1Primavera);
  const response = await page.goto("/hoje");
  expect(response?.status()).toBe(200);
  expectSecurityHeaders(response!);
});

test("/login carrega sem violação de CSP no navegador", async ({ page }) => {
  const problems: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error" && /content security policy|csp/i.test(message.text())) {
      problems.push(message.text());
    }
  });
  page.on("pageerror", (error) => problems.push(error.message));
  await page.addInitScript(() => {
    document.addEventListener("securitypolicyviolation", (event) => {
      console.error(`CSP violation: ${event.violatedDirective} ${event.blockedURI}`);
    });
  });

  await page.goto("/login");
  await expect(page.getByRole("button", { name: "Entrar" })).toBeVisible();
  // O script inline do next-themes (com nonce) rodou e aplicou o tema claro.
  await expect(page.locator("html")).toHaveClass(/\blight\b/);
  // A página hidratou: a validação roda pela Server Action e devolve a mensagem.
  await page.getByRole("button", { name: "Entrar" }).click();
  await expect(page.getByText("Informe o e-mail.")).toBeVisible();
  await page.waitForLoadState("networkidle");

  expect(problems).toEqual([]);
});

// R2-APP-11: caminhos de um segmento com extensão pulavam o proxy e o 404 em HTML saía sem CSP.
for (const path of [
  "/nao-existe",
  "/nao-existe.js",
  "/robots.txt",
  "/sitemap.xml",
  "/favicon.ico",
  "/manifest.webmanifest",
  "/gerente.css",
  "/x.map",
  "/fonte.woff2",
  // R3-APP-07: a exclusão de /_next/image não era ancorada e levava junto qualquer prefixo.
  "/_next/imagex",
  "/_next/image-foo/bar",
  "/_next/imagens/logo.png",
  "/_next/image%2F..%2Flogin",
  // D110: só os logos que existem em public/brand/ ficam fora do proxy, nome a nome.
  "/brand/nao-existe.svg",
  "/brand/ede-horizontal-laranja.svgx",
  "/brand/ede-horizontal-laranja.svg/x",
  "/brand/ede-horizontal-verde.svg",
  "/brand/",
  // O catálogo de protótipo só existe com ENABLE_PROTOTYPES=1 (o E2E roda sem).
  "/prototipo/componentes",
  "/prototipo",
]) {
  test(`404 de ${path} também tem CSP e cabeçalhos de segurança`, async ({ request }) => {
    const response = await request.get(path);
    expect(response.status()).toBe(404);
    expectSecurityHeaders(response);
  });
}

test("/icon.svg (arquivo real fora do proxy) continua servido", async ({ request }) => {
  const response = await request.get("/icon.svg");
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("image/svg+xml");
  expect(response.headers()["x-content-type-options"]).toBe("nosniff");
});

test("logos de public/brand (fora do proxy) são servidos como SVG", async ({ request }) => {
  for (const name of [
    "ede-horizontal-laranja",
    "ede-horizontal-branco",
    "ede-horizontal-cacau",
    "ede-principal-laranja",
    "ede-principal-branco",
    "ede-icone-app",
    "ede-icone-circulo",
    "ede-simbolo-laranja",
    "ede-simbolo-branco",
    "ede-simbolo-cacau",
  ]) {
    const response = await request.get(`/brand/${name}.svg`);
    expect(response.status(), name).toBe(200);
    expect(response.headers()["content-type"], name).toContain("image/svg+xml");
    expect(response.headers()["x-content-type-options"], name).toBe("nosniff");
  }
});

test("fontes da marca são servidas pelo próprio app e pré-carregadas", async ({ request }) => {
  // O Next manda o preload das fontes no cabeçalho Link (e nas dicas do RSC), não em <link>.
  const response = await request.get("/login");
  const link = response.headers()["link"] ?? "";
  const fonts = [...link.matchAll(/<([^>]+\.woff2)>; rel=preload; as="font"/g)].map(
    (match) => match[1]!,
  );
  expect(fonts.length).toBe(7);
  for (const href of fonts) {
    expect(href, href).toMatch(/^\/_next\/static\/media\//);
    const font = await request.get(href);
    expect(font.status(), href).toBe(200);
    expect(font.headers()["content-type"], href).toContain("font/woff2");
  }
});
