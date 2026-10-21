import { readFileSync } from "node:fs";

/** Variáveis do .env.local da stack local (chaves de desenvolvimento). */
export function envLocal(name: string): string {
  const match = new RegExp(`^\\s*${name}\\s*=\\s*(.+?)\\s*$`, "m").exec(
    readFileSync(".env.local", "utf8"),
  );
  if (!match?.[1]) throw new Error(`${name} ausente no .env.local`);
  return match[1];
}
