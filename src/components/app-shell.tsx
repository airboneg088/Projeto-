import { clsx } from "clsx";
import Link from "next/link";
import type { ReactNode } from "react";

import { LogoHorizontal } from "@/components/brand/logo";
import { IconLogOut } from "@/components/icons";
import { ThemeToggle } from "@/components/theme-toggle";
import { Button } from "@/components/ui/button";
import { signOut } from "@/lib/auth/actions";
import type { UserContext } from "@/lib/auth/context";
import {
  AREA_LABEL,
  AREA_PATH,
  type Area,
  ROLE_LABEL,
  accessibleAreas,
  primaryRole,
} from "@/lib/auth/roles";

function storesLabel(ctx: UserContext): string {
  if (ctx.networkWide) return "Todas as lojas";
  if (ctx.stores.length === 0) return "Sem loja";
  return ctx.stores.map((store) => store.name).join(", ");
}

/**
 * Cabeçalho das áreas logadas: logo horizontal (link para o início), tema, Sair, quem está
 * logado (nome · papel · loja) e as áreas que a pessoa pode abrir. Branco sobre o creme da
 * página (degrau de tom), sem sombra.
 */
export function AppHeader({
  name,
  role,
  stores,
  areas,
  current,
  signOutAction,
}: {
  name: string;
  role: string;
  stores: string;
  areas: readonly Area[];
  current?: Area;
  /** Server Action de sair. Sem ela (catálogo), o botão é só visual. */
  signOutAction?: () => Promise<void>;
}) {
  return (
    <header className="bg-surface pt-[env(safe-area-inset-top)]">
      <div className="mx-auto flex w-full max-w-5xl items-center justify-between gap-3 px-4 pt-3">
        <Link href="/" className="-ml-1 inline-flex min-h-11 items-center rounded-s px-1">
          <LogoHorizontal priority />
          <span className="sr-only"> Gestão: ir para o início</span>
        </Link>
        <div className="flex items-center gap-1">
          <ThemeToggle />
          <form action={signOutAction}>
            <Button type={signOutAction ? "submit" : "button"} variant="ghost" size="sm">
              <IconLogOut size={20} />
              Sair
            </Button>
          </form>
        </div>
      </div>
      <div className="mx-auto w-full max-w-5xl px-4 pt-1 pb-3">
        <p className="truncate type-body-strong text-text" data-testid="usuario-nome">
          {name}
        </p>
        <p className="truncate type-meta text-text-muted">
          <span data-testid="usuario-papel">{role}</span>
          <span aria-hidden="true"> · </span>
          <span data-testid="usuario-lojas">{stores}</span>
        </p>
      </div>
      {areas.length > 1 ? (
        <nav aria-label="Áreas" className="mx-auto w-full max-w-5xl px-4 pb-3">
          <ul className="flex gap-1 rounded-m bg-surface-muted p-1">
            {areas.map((area) => (
              <li key={area} className="flex-1 sm:flex-none">
                <Link
                  href={AREA_PATH[area]}
                  aria-current={area === current ? "page" : undefined}
                  className={clsx(
                    "flex min-h-11 items-center justify-center rounded-s px-4 type-body-strong",
                    area === current
                      ? "bg-surface text-text"
                      : "text-text-muted hover:bg-surface-pressed hover:text-text",
                  )}
                >
                  {AREA_LABEL[area]}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      ) : null}
    </header>
  );
}

/** Casca das áreas logadas: pulo para o conteúdo, cabeçalho e conteúdo. */
export function AppShell({
  ctx,
  current,
  children,
}: {
  ctx: UserContext;
  current: Area;
  children: ReactNode;
}) {
  const role = primaryRole(ctx.roles);

  return (
    <div className="flex min-h-dvh flex-col">
      <a
        href="#conteudo"
        className="sr-only z-50 rounded-m bg-surface px-4 py-3 type-body-strong text-text focus:not-sr-only focus:fixed focus:top-2 focus:left-2"
      >
        Pular para o conteúdo
      </a>
      <AppHeader
        name={ctx.profile?.full_name || ctx.user.email || "Usuário"}
        role={role ? ROLE_LABEL[role] : "Sem papel"}
        stores={storesLabel(ctx)}
        areas={accessibleAreas(ctx.roles)}
        current={current}
        signOutAction={signOut}
      />
      <main id="conteudo" className="mx-auto w-full max-w-5xl flex-1 px-4 pt-6 pb-12">
        {children}
      </main>
    </div>
  );
}
