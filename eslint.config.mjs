import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";
import prettier from "eslint-config-prettier/flat";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Desliga regras de estilo que conflitam com o Prettier (formatação é do Prettier).
  prettier,
  {
    // Áreas logadas: metadados só depois do guard (D70). `export const metadata` é resolvido
    // mesmo quando o pedido é negado; use generateMetadata com areaMetadata(área).
    files: ["src/app/(app)/**/*.{ts,tsx}"],
    rules: {
      "no-restricted-syntax": [
        "error",
        {
          selector:
            "ExportNamedDeclaration > VariableDeclaration > VariableDeclarator[id.name='metadata']",
          message:
            "Área logada: use `export function generateMetadata() { return areaMetadata(área) }` (D70).",
        },
      ],
    },
  },
  globalIgnores([
    // Padrões do eslint-config-next
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // Stack local, relatórios de teste e artefatos
    ".local/**",
    "coverage/**",
    "playwright-report/**",
    "test-results/**",
    "blob-report/**",
    "supabase/.temp/**",
    "supabase/.branches/**",
  ]),
]);

export default eslintConfig;
