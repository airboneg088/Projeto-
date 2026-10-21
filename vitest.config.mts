import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
      // No Next, "server-only" é resolvido pelo bundler; nos testes de unidade (Node) é um módulo vazio.
      "server-only": fileURLToPath(
        new URL("./node_modules/next/dist/compiled/server-only/empty.js", import.meta.url),
      ),
    },
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts", "scripts/**/*.test.{ts,mjs}"],
    exclude: ["node_modules/**", ".next/**", ".local/**", "e2e/**"],
  },
});
