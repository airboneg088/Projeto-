import { clsx } from "clsx";
import type { ReactNode } from "react";

/**
 * Barra de ação inferior fixa (execução da tarefa): a ação principal fica ao alcance do polegar.
 * Respeita a área segura do aparelho (barra de gestos) e reserva o próprio espaço no fim da
 * página, para nada ficar escondido atrás dela. Sem sombra: degrau de tom + divisória de 1px.
 *
 * `fixed={false}` mostra a barra no fluxo (catálogo de componentes).
 */
export function BottomActionBar({
  children,
  hint,
  fixed = true,
  className,
}: {
  children: ReactNode;
  /** Linha curta acima das ações ("3 de 5 itens marcados"). */
  hint?: ReactNode;
  fixed?: boolean;
  className?: string;
}) {
  const bar = (
    <div
      className={clsx(
        "border-t border-border bg-surface px-4 pt-3",
        fixed
          ? "fixed inset-x-0 bottom-0 z-30 pb-[max(env(safe-area-inset-bottom),0.75rem)] pl-[max(env(safe-area-inset-left),1rem)] pr-[max(env(safe-area-inset-right),1rem)]"
          : "rounded-m pb-3",
        className,
      )}
    >
      <div className="mx-auto flex w-full max-w-3xl flex-col gap-2">
        {hint ? <div className="type-meta tabular-nums text-text-muted">{hint}</div> : null}
        <div className="flex gap-3 *:flex-1">{children}</div>
      </div>
    </div>
  );

  if (!fixed) return bar;
  return (
    <>
      {/* Reserva a altura da barra (botão de 56px + respiros + área segura). */}
      <div
        aria-hidden="true"
        className="h-[calc(var(--bar-height)+2.5rem+env(safe-area-inset-bottom))]"
      />
      {bar}
    </>
  );
}
