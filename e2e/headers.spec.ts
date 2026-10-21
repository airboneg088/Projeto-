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
