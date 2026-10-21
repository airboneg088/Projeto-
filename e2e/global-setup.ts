import { execFileSync } from "node:child_process";

/**
 * Recria o banco principal com o seed antes da suíte (`pnpm db:reset`), para todo teste partir
 * dos mesmos dados. E2E_SKIP_DB_RESET=1 pula este passo (ex.: rodando contra outra stack).
 */
export default function globalSetup() {
  if (process.env.E2E_SKIP_DB_RESET === "1") {
    console.log("[e2e] E2E_SKIP_DB_RESET=1: banco não foi recriado.");
    return;
  }
  const env = { ...process.env, DB_NAME: "postgres" };
  execFileSync("pnpm", ["db:reset"], { stdio: "inherit", env });
}
