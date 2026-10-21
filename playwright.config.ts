import { existsSync } from "node:fs";

import { chromium, defineConfig, devices } from "@playwright/test";

/**
 * Chromium dos testes. O @playwright/test instalado espera uma revisão que não está baixada
 * neste ambiente (e não dá para rodar `playwright install`), então usa o Chromium 1194 já
 * instalado. PLAYWRIGHT_CHROMIUM_EXECUTABLE sobrepõe tudo.
 */
const INSTALLED_CHROMIUM = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";

function chromiumExecutable(): string | undefined {
  if (process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE) return process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  try {
    if (existsSync(chromium.executablePath())) return undefined;
  } catch {
    // revisão esperada não instalada
  }
  return existsSync(INSTALLED_CHROMIUM) ? INSTALLED_CHROMIUM : undefined;
}

/** E2E_BASE_URL aponta para um servidor já rodando (sem subir o `pnpm start`). */
const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:3000";

export default defineConfig({
  testDir: "./e2e",
  // Um worker: os testes compartilham o mesmo banco e a mesma caixa de e-mails.
  workers: 1,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: [["list"]],
  globalSetup: "./e2e/global-setup.ts",
  timeout: 30_000,
  expect: { timeout: 10_000 },
  use: {
    baseURL,
    locale: "pt-BR",
    timezoneId: "America/Sao_Paulo",
    trace: "retain-on-failure",
    launchOptions: { executablePath: chromiumExecutable() },
  },
  projects: [
    {
      name: "mobile-390",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 390, height: 844 },
        isMobile: true,
        hasTouch: true,
      },
    },
    {
      name: "desktop-1440",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } },
    },
  ],
  // Exige `pnpm build` antes (a suíte roda contra o build de produção, com a CSP real).
  webServer: process.env.E2E_BASE_URL
    ? undefined
    : {
        command: "pnpm start --port 3000",
        url: "http://localhost:3000/login",
        reuseExistingServer: true,
        timeout: 120_000,
      },
});
