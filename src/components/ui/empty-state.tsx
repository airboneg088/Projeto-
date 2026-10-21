import { clsx } from "clsx";
import type { ComponentType, ReactNode } from "react";

import { IconInbox, type IconProps } from "@/components/icons";

type EmptyStateProps = {
  title: string;
  /** O que a pessoa pode fazer agora (orientação, não só "nada aqui"). */
  children: ReactNode;
  icon?: ComponentType<IconProps>;
  /** Ação opcional (botão ou link). */
  action?: ReactNode;
  /** Nível do título (padrão h2). */
  headingLevel?: "h2" | "h3";
  className?: string;
};

/**
 * Estado vazio com orientação. Bloco areia (degrau de tom) alinhado à esquerda, ícone de linha
 * pequeno ao lado do texto: nada de ilustração grande nem cartão com ícone no topo.
 */
export function EmptyState({
  title,
  children,
  icon: Icon = IconInbox,
  action,
  headingLevel: Heading = "h2",
  className,
}: EmptyStateProps) {
  return (
    <section className={clsx("flex gap-4 rounded-m bg-surface-muted p-5", className)}>
      <span className="grid size-11 shrink-0 place-items-center rounded-full bg-surface text-accent-text">
        <Icon size={22} />
      </span>
      <div className="flex min-w-0 flex-col items-start gap-1.5">
        <Heading className="type-lead text-text">{title}</Heading>
        <div className="max-w-prose text-text-muted">{children}</div>
        {action ? <div className="mt-2">{action}</div> : null}
      </div>
    </section>
  );
}
