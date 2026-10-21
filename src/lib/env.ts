import { z } from "zod";

/**
 * Variáveis de ambiente PÚBLICAS (vão para o navegador). Validadas com zod na primeira leitura.
 * Segredos ficam em `env.server.ts`, que só roda no servidor.
 *
 * O Next só embute `process.env.NEXT_PUBLIC_*` no código do navegador quando o nome aparece
 * literalmente; por isso cada variável é lida pelo nome em `readPublicEnv()`.
 */

const httpUrl = (name: string) =>
  z
    .url({ protocol: /^https?$/, error: `${name} precisa ser uma URL http(s) válida.` })
    .transform((value) => value.replace(/\/+$/, ""));

/** Lê o campo `role` do payload de um JWT sem validar a assinatura (só para checagem local). */
function jwtRole(token: string): string | null {
  const parts = token.split(".");
  if (parts.length !== 3 || !parts[1]) return null;
  try {
    const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
    const payload: unknown = JSON.parse(atob(padded));
    if (payload && typeof payload === "object" && "role" in payload) {
      return typeof payload.role === "string" ? payload.role : null;
    }
    return null;
  } catch {
    return null;
  }
}

export const publicEnvSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: httpUrl("NEXT_PUBLIC_SUPABASE_URL"),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z
    .string({ error: "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY é obrigatória." })
    .trim()
    .min(1, { error: "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY é obrigatória." })
    .refine((key) => !key.startsWith("sb_secret_"), {
      error:
        "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY recebeu uma chave secreta. Use a chave publicável.",
    })
    .refine(
      (key) => {
        const role = jwtRole(key);
        return role === null || role === "anon";
      },
      {
        error:
          "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY precisa ser a chave publicável (anon), nunca a secreta.",
      },
    ),
  NEXT_PUBLIC_SITE_URL: httpUrl("NEXT_PUBLIC_SITE_URL"),
});

export type PublicEnv = z.infer<typeof publicEnvSchema>;

export class EnvError extends Error {
  override name = "EnvError";
}

/** Valida um conjunto de variáveis públicas. Lança EnvError com a lista do que falta. */
export function parsePublicEnv(source: Record<string, string | undefined>): PublicEnv {
  const result = publicEnvSchema.safeParse(source);
  if (!result.success) {
    const details = result.error.issues
      .map((issue) => `- ${issue.path.join(".") || "?"}: ${issue.message}`)
      .join("\n");
    throw new EnvError(
      `Variáveis de ambiente públicas ausentes ou inválidas:\n${details}\n` +
        "Local: rode `pnpm stack:up` (gera o .env.local). Produção: configure na Vercel.",
    );
  }
  return result.data;
}

function readPublicEnv(): Record<string, string | undefined> {
  return {
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL,
  };
}

let cached: PublicEnv | undefined;

/** Variáveis públicas validadas (lidas uma vez por processo). */
export function getPublicEnv(): PublicEnv {
  cached ??= parsePublicEnv(readPublicEnv());
  return cached;
}
