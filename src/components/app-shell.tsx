import Link from "next/link";
import type { ReactNode } from "react";

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
 * Casca mínima das áreas logadas (provisória até a Fase 2): nome, papel, loja(s), navegação
 * entre as áreas que a pessoa pode abrir e "Sair".
 */
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
  const name = ctx.profile?.full_name || ctx.user.email || "Usuário";
  const areas = accessibleAreas(ctx.roles);

  return (
    <div className="flex min-h-dvh flex-col">
      <header className="border-b border-border bg-surface-1">
        <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center justify-between gap-x-4 gap-y-2 px-4 py-3">
          <div className="min-w-0">
            <p className="truncate font-semibold" data-testid="usuario-nome">
              {name}
            </p>
            <p className="text-text-muted">
              <span data-testid="usuario-papel">{role ? ROLE_LABEL[role] : "Sem papel"}</span>
              <span aria-hidden="true"> · </span>
              <span data-testid="usuario-lojas">{storesLabel(ctx)}</span>
            </p>
          </div>
          <div className="flex items-center gap-2">
            <ThemeToggle />
            <form action={signOut}>
              <Button type="submit" variant="secondary" size="sm">
                Sair
              </Button>
            </form>
          </div>
        </div>
        {areas.length > 1 ? (
          <nav aria-label="Áreas" className="mx-auto w-full max-w-5xl px-2 pb-1">
            <ul className="flex gap-1">
              {areas.map((area) => (
                <li key={area}>
                  <Link
                    href={AREA_PATH[area]}
                    aria-current={area === current ? "page" : undefined}
                    className="link px-2 font-semibold aria-[current=page]:text-text aria-[current=page]:no-underline"
                  >
                    {AREA_LABEL[area]}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
        ) : null}
      </header>
      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-6">{children}</main>
    </div>
  );
}
