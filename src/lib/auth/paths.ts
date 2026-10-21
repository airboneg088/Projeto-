import { AREA_PATH } from "./roles";

/**
 * Normaliza um caminho para decidir proteção de rota: decodifica a codificação percentual,
 * junta barras repetidas, troca "\" por "/", tira a barra final e passa para minúsculas.
 * Assim "/Gerente/", "//gerente" e "/%67erente" contam como "/gerente".
 */
export function normalizePath(pathname: string): string {
  let path = pathname;
  for (let round = 0; round < 3; round += 1) {
    let decoded: string;
    try {
      decoded = decodeURIComponent(path);
    } catch {
      break;
    }
    if (decoded === path) break;
    path = decoded;
  }
  path = path
    .replace(/\\/g, "/")
    .replace(/\/{2,}/g, "/")
    .toLowerCase();
  if (!path.startsWith("/")) path = `/${path}`;
  if (path.length > 1) path = path.replace(/\/+$/, "");
  return path || "/";
}

const PROTECTED_PREFIXES: readonly string[] = Object.values(AREA_PATH);

/** Caminhos que exigem sessão: "/" e tudo abaixo de /hoje, /gerente, /painel e /admin. */
export function isProtectedPath(pathname: string): boolean {
  const path = normalizePath(pathname);
  if (path === "/") return true;
  return PROTECTED_PREFIXES.some((prefix) => path === prefix || path.startsWith(`${prefix}/`));
}

/** Página de login (qualquer variação de maiúsculas ou barra final). */
export function isLoginPath(pathname: string): boolean {
  return normalizePath(pathname) === "/login";
}
