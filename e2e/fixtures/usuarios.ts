import { type Page, expect } from "@playwright/test";

/** Senha de todos os usuários do seed (somente local/dev). */
export const SENHA_SEED = "Exemplo#2026";

export type Usuario = {
  email: string;
  papel: "owner" | "admin" | "manager" | "staff";
  /** Página inicial esperada após o login. */
  inicio: "/painel" | "/admin" | "/gerente" | "/hoje";
  /** Rótulo do papel no cabeçalho. */
  rotulo: "Proprietária" | "Administração" | "Gerente" | "Colaborador";
  /** Parte do nome da loja exibida no cabeçalho (vínculos de loja). */
  loja?: RegExp;
};

const gerente = (slug: string, loja: RegExp): Usuario => ({
  email: `gerente.${slug}@exemplo.local`,
  papel: "manager",
  inicio: "/gerente",
  rotulo: "Gerente",
  loja,
});

const colaborador = (n: number, slug: string, loja: RegExp): Usuario => ({
  email: `colaborador${n}.${slug}@exemplo.local`,
  papel: "staff",
  inicio: "/hoje",
  rotulo: "Colaborador",
  loja,
});

const LOJAS = [
  { slug: "primavera", loja: /Primavera/ },
  { slug: "castroalves", loja: /Castro Alves/ },
  { slug: "parqueamerica", loja: /Parque Am[eé]rica/ },
] as const;

/** Usuários do seed (contrato da stack local). */
const proprietaria: Usuario = {
  email: "proprietaria@exemplo.local",
  papel: "owner",
  inicio: "/painel",
  rotulo: "Proprietária",
};

const admin: Usuario = {
  email: "admin@exemplo.local",
  papel: "admin",
  inicio: "/admin",
  rotulo: "Administração",
};

export const USUARIOS = {
  proprietaria,
  admin,
  gerentePrimavera: gerente("primavera", /Primavera/),
  gerenteCastroAlves: gerente("castroalves", /Castro Alves/),
  gerenteParqueAmerica: gerente("parqueamerica", /Parque Am[eé]rica/),
  colaborador1Primavera: colaborador(1, "primavera", /Primavera/),
} as const;

/** Todos os 14 usuários do seed. */
export const TODOS_OS_USUARIOS: Usuario[] = [
  USUARIOS.proprietaria,
  USUARIOS.admin,
  ...LOJAS.map(({ slug, loja }) => gerente(slug, loja)),
  ...LOJAS.flatMap(({ slug, loja }) => [1, 2, 3].map((n) => colaborador(n, slug, loja))),
];

/**
 * Usuário reservado ao teste de recuperação de senha. O teste troca a senha e depois a devolve
 * para SENHA_SEED pelo mesmo fluxo; o `pnpm db:reset` do globalSetup também a restaura.
 */
export const USUARIO_RECUPERACAO: Usuario = colaborador(3, "parqueamerica", /Parque Am[eé]rica/);

/** Faz login pela tela e espera sair de /login. */
export async function entrar(page: Page, usuario: Pick<Usuario, "email">, senha = SENHA_SEED) {
  await page.goto("/login");
  await page.getByLabel("E-mail").fill(usuario.email);
  await page.getByLabel("Senha", { exact: true }).fill(senha);
  await page.getByRole("button", { name: "Entrar" }).click();
  await expect(page).not.toHaveURL(/\/login(\?|$)/);
}

/** Sai pela tela e espera chegar ao login. */
export async function sair(page: Page) {
  await page.getByRole("button", { name: "Sair" }).click();
  await expect(page).toHaveURL(/\/login$/);
}
