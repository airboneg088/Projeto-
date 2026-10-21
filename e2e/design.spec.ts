import { type Page, expect, test } from "@playwright/test";

import { USUARIOS, entrar } from "./fixtures/usuarios";

/**
 * Fase 2 (fundação visual): alvos de toque, fontes da marca, logo e tema escuro nas telas reais.
 * O catálogo /prototipo/componentes não roda aqui (o E2E sobe sem ENABLE_PROTOTYPES).
 */

/** Controles visíveis com altura (e, para botões, largura) menor que 44px. */
async function smallTargets(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    const MIN = 44;
    const selector = "button, a[href], input:not([type=hidden]), textarea, select, [role=checkbox]";
    const problems: string[] = [];
    for (const element of Array.from(document.querySelectorAll<HTMLElement>(selector))) {
      const style = getComputedStyle(element);
      // Link "esticado" (::after absoluto cobrindo o cartão): o alvo é o cartão inteiro.
      const stretched =
        element.tagName === "A" && getComputedStyle(element, "::after").position === "absolute";
      const target = stretched ? (element.closest("article") ?? element) : element;
      const box = target.getBoundingClientRect();
      if (style.visibility === "hidden" || style.display === "none") continue;
      if (box.width === 0 || box.height === 0) continue;
      // Link de "pular para o conteúdo" só aparece com foco do teclado.
      if (element.classList.contains("sr-only")) continue;
      const isButton = element.tagName === "BUTTON" || element.getAttribute("role") === "checkbox";
      if (box.height < MIN || (isButton && box.width < MIN)) {
        const name = (element.getAttribute("aria-label") ?? element.textContent ?? "").trim();
        problems.push(
          `${element.tagName.toLowerCase()} "${name.slice(0, 40)}" ${Math.round(box.width)}×${Math.round(box.height)}`,
        );
      }
    }
    return problems;
  });
}

test.describe("alvos de toque >= 44px em 390px", () => {
  test.skip(({ viewport }) => (viewport?.width ?? 0) > 500, "só no celular (390px)");

  for (const path of ["/login", "/recuperar-senha", "/redefinir-senha"]) {
    test(`${path}`, async ({ page }) => {
      await page.goto(path);
      await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
      expect(await smallTargets(page)).toEqual([]);
    });
  }

  test("casca da área logada (/hoje)", async ({ page }) => {
    await entrar(page, USUARIOS.colaborador1Primavera);
    await expect(page).toHaveURL(/\/hoje$/);
    expect(await smallTargets(page)).toEqual([]);
  });

  test("casca com navegação entre áreas (proprietária)", async ({ page }) => {
    await entrar(page, USUARIOS.proprietaria);
    await expect(page.getByRole("navigation", { name: "Áreas" })).toBeVisible();
    expect(await smallTargets(page)).toEqual([]);
  });
});

test("fontes da marca (Figtree no texto, Bitter no título) carregam do próprio app", async ({
  page,
}) => {
  await page.goto("/login");
  await page.evaluate(() => document.fonts.ready);
  const fonts = await page.evaluate(() => ({
    body: getComputedStyle(document.body).fontFamily,
    title: getComputedStyle(document.querySelector("h1")!).fontFamily,
    loaded: Array.from(document.fonts)
      .filter((face) => face.status === "loaded")
      .map((face) => `${face.family} ${face.weight}`),
  }));
  expect(fonts.body).toMatch(/figtree/i);
  expect(fonts.title).toMatch(/bitter/i);
  expect(fonts.loaded.some((face) => /figtree/i.test(face))).toBe(true);
  expect(fonts.loaded.some((face) => /bitter/i.test(face))).toBe(true);
});

test("logo da marca aparece com texto alternativo", async ({ page }) => {
  await page.goto("/login");
  const logo = page.locator('img[alt="Éde Utilidades"]:visible').first();
  await expect(logo).toBeVisible();
  expect(await logo.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(
    true,
  );
});

test("tema escuro troca os tokens e volta ao claro", async ({ page }) => {
  await entrar(page, USUARIOS.colaborador1Primavera);
  const background = () => page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  expect(await background()).toBe("rgb(255, 244, 232)"); // creme
  const toggle = page.getByRole("button", { name: "Tema escuro" });
  await expect(toggle).toHaveAttribute("aria-pressed", "false");
  await toggle.click();
  await expect(page.locator("html")).toHaveClass(/\bdark\b/);
  await expect(toggle).toHaveAttribute("aria-pressed", "true");
  expect(await background()).toBe("rgb(23, 14, 9)");
  await toggle.click();
  await expect(page.locator("html")).toHaveClass(/\blight\b/);
  expect(await background()).toBe("rgb(255, 244, 232)");
});
