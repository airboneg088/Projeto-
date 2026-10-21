import "server-only";

import { z } from "zod";

import { EnvError } from "./env";

/**
 * Segredos do servidor. Este arquivo nunca pode ser importado por código de cliente
 * (`import "server-only"` quebra o build se isso acontecer; `pnpm check:secrets` também confere).
 */

/** Lê o campo `role` do payload de um JWT sem validar a assinatura. */
function jwtRole(token: string): string | null {
  const parts = token.split(".");
  if (parts.length !== 3 || !parts[1]) return null;
  try {
    const payload: unknown = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    if (payload && typeof payload === "object" && "role" in payload) {
      return typeof payload.role === "string" ? payload.role : null;
    }
    return null;
  } catch {
    return null;
  }
}

export const serverEnvSchema = z.object({
  SUPABASE_SECRET_KEY: z
    .string({ error: "SUPABASE_SECRET_KEY é obrigatória no servidor." })
    .trim()
    .min(1, { error: "SUPABASE_SECRET_KEY é obrigatória no servidor." })
    .refine(
      (key) => {
        if (key.startsWith("sb_secret_")) return true;
        return jwtRole(key) === "service_role";
      },
      {
        error: "SUPABASE_SECRET_KEY precisa ser a chave secreta (sb_secret_… ou JWT service_role).",
      },
    ),
});

export type ServerEnv = z.infer<typeof serverEnvSchema>;

export function parseServerEnv(source: Record<string, string | undefined>): ServerEnv {
  const result = serverEnvSchema.safeParse(source);
  if (!result.success) {
    const details = result.error.issues.map((issue) => `- ${issue.message}`).join("\n");
    throw new EnvError(`Variáveis de ambiente do servidor ausentes ou inválidas:\n${details}`);
  }
  return result.data;
}

let cached: ServerEnv | undefined;

export function getServerEnv(): ServerEnv {
  cached ??= parseServerEnv({ SUPABASE_SECRET_KEY: process.env.SUPABASE_SECRET_KEY });
  return cached;
}
