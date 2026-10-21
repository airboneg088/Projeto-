import { clsx } from "clsx";
import type { ComponentType } from "react";

import type { IconProps } from "@/components/icons";
import { EmptyState } from "@/components/ui/empty-state";

/**
 * Corpo provisório de cada área: título da página, o que a área vai ter e em qual fase chega.
 * Usa o mesmo EmptyState das telas reais (estado vazio com orientação).
 */
export function AreaPlaceholder({
  title,
  subtitle,
  phase,
  description,
  icon,
  className,
}: {
  title: string;
  /** Linha abaixo do título (ex.: data de hoje e loja). */
  subtitle?: string;
  phase: string;
  description: string;
  icon?: ComponentType<IconProps>;
  className?: string;
}) {
  return (
    <section className={clsx("flex flex-col gap-6", className)}>
      <div>
        <h1 className="type-title-1 text-text">{title}</h1>
        {subtitle ? (
          <p className="mt-1 text-text-muted first-letter:uppercase">{subtitle}</p>
        ) : null}
      </div>
      <EmptyState title={`Esta área chega na ${phase}`} icon={icon}>
        <p>{description}</p>
        <p className="mt-1">Por enquanto, este é só o ponto de entrada.</p>
      </EmptyState>
    </section>
  );
}
