import type { CookieOptions } from "@supabase/ssr";

/**
 * Opções dos cookies da sessão do Supabase (D63), aplicadas a TODA gravação pelo `setAll` dos
 * clientes do servidor (src/lib/supabase/server.ts e src/proxy.ts):
 * - `httpOnly`: o JavaScript da página não lê o token (nenhum código do navegador usa a sessão;
 *   tudo passa pelo servidor). Um script injetado não leva o token para fora.
 * - `secure` em produção (só HTTPS); `sameSite: "lax"`; `path: "/"`.
 * - `maxAge` de 7 dias, renovado a cada gravação (o token de acesso dura 10 min, então quem usa o
 *   app renova o prazo). Funciona como "sair depois de 7 dias sem usar neste aparelho".
 *   O @supabase/ssr 0.12 força 400 dias e ignora o `maxAge` de `cookieOptions`; por isso o prazo
 *   é imposto aqui.
 * A remoção (`maxAge: 0`) continua remoção.
 */
export const SESSION_COOKIE_MAX_AGE_SECONDS = 7 * 24 * 60 * 60;

export function sessionCookieOptions(
  options: CookieOptions,
  isProduction = process.env.NODE_ENV === "production",
): CookieOptions {
  const removing =
    options.maxAge === 0 ||
    (options.expires instanceof Date && options.expires.getTime() <= Date.now());
  // `expires` sai: o prazo é sempre o `maxAge` abaixo.
  const rest = { ...options };
  delete rest.expires;
  return {
    ...rest,
    path: "/",
    sameSite: "lax",
    httpOnly: true,
    secure: isProduction,
    maxAge: removing ? 0 : SESSION_COOKIE_MAX_AGE_SECONDS,
  };
}
