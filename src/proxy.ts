import { type CookieMethodsServer as CookieMethods, createServerClient } from "@supabase/ssr";
import { type NextRequest, NextResponse } from "next/server";

import { loginPathFor } from "@/lib/auth/access";
import { isLoginPath, isProtectedPath } from "@/lib/auth/paths";
import { getPublicEnv } from "@/lib/env";
import { buildCsp, createNonce } from "@/lib/security/csp";

import type { Database } from "@/lib/supabase/database.types";

/**
 * Proxy (antigo middleware) que roda antes de cada página:
 * 1. gera um nonce e aplica a Content-Security-Policy;
 * 2. renova os cookies da sessão do Supabase;
 * 3. manda quem não está logado de uma rota protegida para /login?next=…;
 * 4. manda quem já está logado de /login para "/".
 *
 * É só a primeira barreira: cada layout de área chama requireArea() e o banco aplica a RLS.
 */
export async function proxy(request: NextRequest) {
  const env = getPublicEnv();
  const nonce = createNonce();
  const csp = buildCsp({
    nonce,
    supabaseUrl: env.NEXT_PUBLIC_SUPABASE_URL,
    isDev: process.env.NODE_ENV === "development",
    upgradeInsecureRequests:
      process.env.NODE_ENV === "production" && env.NEXT_PUBLIC_SITE_URL.startsWith("https://"),
  });

  // Cabeçalhos repassados para a renderização: o Next lê o nonce da CSP do pedido e o aplica
  // aos próprios scripts; o layout lê x-nonce para o script do next-themes.
  const forwardHeaders = () => {
    const headers = new Headers(request.headers);
    headers.set("x-nonce", nonce);
    headers.set("content-security-policy", csp);
    return headers;
  };

  let response = NextResponse.next({ request: { headers: forwardHeaders() } });
  // Acumula tudo o que o Supabase pedir para gravar (cookies e cabeçalhos anti-cache, que só
  // vêm na primeira gravação), para não perder nada se setAll for chamado mais de uma vez.
  type CookieToSet = Parameters<NonNullable<CookieMethods["setAll"]>>[0][number];
  const pendingCookies = new Map<string, CookieToSet>();
  const sessionHeaders: Record<string, string> = {};

  const supabase = createServerClient<Database>(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet, headers) {
          for (const cookie of cookiesToSet) {
            request.cookies.set(cookie.name, cookie.value);
            pendingCookies.set(cookie.name, cookie);
          }
          Object.assign(sessionHeaders, headers);
          response = NextResponse.next({ request: { headers: forwardHeaders() } });
          for (const { name, value, options } of pendingCookies.values()) {
            response.cookies.set(name, value, options);
          }
          for (const [key, value] of Object.entries(sessionHeaders)) {
            response.headers.set(key, value);
          }
        },
      },
    },
  );

  // Valida o token no Auth (não confia só no cookie). Se a sessão foi encerrada no servidor,
  // o cliente apaga os cookies via setAll.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname, search } = request.nextUrl;
  let redirectTo: URL | null = null;
  if (!user && isProtectedPath(pathname)) {
    redirectTo = new URL(loginPathFor(`${pathname}${search}`), request.url);
  } else if (user && isLoginPath(pathname)) {
    redirectTo = new URL("/", request.url);
  }

  if (redirectTo) {
    const redirect = redirectResponse(request, redirectTo);
    for (const cookie of response.cookies.getAll()) redirect.cookies.set(cookie);
    for (const [key, value] of Object.entries(sessionHeaders)) redirect.headers.set(key, value);
    redirect.headers.set("Content-Security-Policy", csp);
    return redirect;
  }

  response.headers.set("Content-Security-Policy", csp);
  return response;
}

/**
 * Redirecionamento adequado a cada tipo de pedido:
 * - Server Action chamada pelo JavaScript (header next-action): o cliente do Next não segue um
 *   302/307 comum; responde com `x-action-redirect` e corpo vazio, e ele navega para o destino;
 * - outros POST (formulário sem JavaScript): 303, para o navegador abrir o destino com GET;
 * - GET/HEAD: 307.
 */
function redirectResponse(request: NextRequest, to: URL): NextResponse {
  const isGetOrHead = request.method === "GET" || request.method === "HEAD";
  if (!isGetOrHead && request.headers.has("next-action")) {
    return new NextResponse(null, {
      status: 200,
      headers: {
        "content-type": "text/plain",
        "x-action-redirect": `${to.pathname}${to.search};replace`,
      },
    });
  }
  return NextResponse.redirect(to, isGetOrHead ? 307 : 303);
}

export const config = {
  matcher: [
    /*
     * Todas as rotas, exceto:
     * - _next/static e _next/image (arquivos do build e imagens otimizadas);
     * - arquivos estáticos na raiz de public/ e ícones de metadados (favicon.ico, icon.svg…).
     * Rotas com extensão em subpastas continuam passando pelo proxy.
     */
    "/((?!_next/static|_next/image|[^/]+\\.(?:ico|png|svg|jpg|jpeg|gif|webp|avif|txt|xml|webmanifest|js|css|map|woff2?)$).*)",
  ],
};
