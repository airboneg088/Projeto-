/**
 * Papéis, áreas e regras de acesso por área (funções puras, testadas em roles.test.ts).
 * A proteção real dos dados é a RLS do banco; estas regras só decidem para onde navegar.
 */

export const ROLES = ["owner", "manager", "staff", "admin"] as const;
export type Role = (typeof ROLES)[number];

export const AREAS = ["hoje", "gerente", "painel", "admin"] as const;
export type Area = (typeof AREAS)[number];

/** Quem pode entrar em cada área. */
export const AREA_ACCESS: Readonly<Record<Area, readonly Role[]>> = {
  hoje: ["staff"],
  gerente: ["manager", "owner"],
  painel: ["owner"],
  admin: ["admin"],
};

/** Caminho raiz de cada área. */
export const AREA_PATH: Readonly<Record<Area, `/${Area}`>> = {
  hoje: "/hoje",
  gerente: "/gerente",
  painel: "/painel",
  admin: "/admin",
};

/** Ordem de prioridade para escolher o papel principal de quem tem mais de um. */
const ROLE_PRIORITY: readonly Role[] = ["owner", "manager", "staff", "admin"];

const HOME_BY_ROLE: Readonly<Record<Role, `/${Area}`>> = {
  owner: "/painel",
  manager: "/gerente",
  staff: "/hoje",
  admin: "/admin",
};

/** Rótulo do papel na interface. */
export const ROLE_LABEL: Readonly<Record<Role, string>> = {
  owner: "Proprietária",
  manager: "Gerente",
  staff: "Colaborador",
  admin: "Administração",
};

/** Nome curto de cada área na navegação. */
export const AREA_LABEL: Readonly<Record<Area, string>> = {
  hoje: "Hoje",
  gerente: "Gerência",
  painel: "Painel",
  admin: "Administração",
};

export function isRole(value: unknown): value is Role {
  return typeof value === "string" && (ROLES as readonly string[]).includes(value);
}

/** Papel principal: owner > manager > staff > admin. `null` se não houver papel. */
export function primaryRole(roles: readonly Role[]): Role | null {
  for (const role of ROLE_PRIORITY) {
    if (roles.includes(role)) return role;
  }
  return null;
}

/** Página inicial de cada papel. */
export function homeFor(role: Role): `/${Area}` {
  return HOME_BY_ROLE[role];
}

/** `true` se algum dos papéis dá acesso à área. */
export function canAccess(area: Area, roles: readonly Role[]): boolean {
  const allowed = AREA_ACCESS[area];
  return roles.some((role) => allowed.includes(role));
}

/** Áreas que a pessoa pode abrir, na ordem de AREAS. */
export function accessibleAreas(roles: readonly Role[]): Area[] {
  return AREAS.filter((area) => canAccess(area, roles));
}

// Caracteres de controle C0, DEL e C1. Escrito com escapes para não ter
// caracteres invisíveis no código-fonte.
const CONTROL_CHARS = /[\u0000-\u001f\u007f-\u009f]/;
const MAX_NEXT_LENGTH = 2048;
const MAX_DECODE_ROUNDS = 5;

function isSafeRelativePath(path: string): boolean {
  if (!path.startsWith("/")) return false;
  // "//host" e "/\host" viram URLs de outro domínio no navegador.
  if (path.startsWith("//")) return false;
  if (path.includes("\\")) return false;
  if (CONTROL_CHARS.test(path)) return false;
  return true;
}

/**
 * Valida o parâmetro `next` de redirecionamento. Aceita só caminhos relativos do próprio site
 * (começam com uma única "/"). Rejeita "//", "/\", esquemas ("https:", "javascript:"),
 * caracteres de controle e as mesmas armadilhas escondidas em codificação percentual
 * (ex.: "/%2F%2Fevil.com"). Em qualquer dúvida, devolve `fallback`.
 */
export function safeNextPath(input: unknown, fallback = "/"): string {
  if (typeof input !== "string") return fallback;
  if (input.length === 0 || input.length > MAX_NEXT_LENGTH) return fallback;

  // Confere o valor bruto e cada camada decodificada.
  let current = input;
  for (let round = 0; round <= MAX_DECODE_ROUNDS; round += 1) {
    if (!isSafeRelativePath(current)) return fallback;
    let decoded: string;
    try {
      decoded = decodeURIComponent(current);
    } catch {
      return fallback;
    }
    if (decoded === current) break;
    if (round === MAX_DECODE_ROUNDS) return fallback;
    current = decoded;
  }

  // Última defesa: o navegador tem de resolver para a mesma origem.
  try {
    const base = "http://ede.invalid";
    const resolved = new URL(input, base);
    if (resolved.origin !== base) return fallback;
  } catch {
    return fallback;
  }

  return input;
}
