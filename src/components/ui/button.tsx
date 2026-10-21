import { type VariantProps, cva } from "class-variance-authority";
import type { ComponentProps, ReactNode } from "react";

import { Spinner } from "./spinner";

/**
 * Botão (DESIGN.md › Componentes). Alvo de toque >= 44px em todos os tamanhos; escala 0.97 ao
 * pressionar (.pressable, 160ms ease-out); hover só com mouse; sem movimento com
 * prefers-reduced-motion. Para um link com cara de botão, use `buttonVariants()` no <Link>.
 */
export const buttonVariants = cva(
  "pressable inline-flex items-center justify-center gap-2 rounded-m text-center type-body-strong",
  {
    variants: {
      variant: {
        primary: "bg-accent text-accent-fg hover:bg-accent-hover",
        secondary: "border border-border-control bg-surface text-text hover:bg-surface-pressed",
        ghost: "bg-transparent text-text hover:bg-surface-pressed",
        danger: "bg-danger text-danger-fg hover:bg-danger-hover",
        /** Só para o estado final do envio ("Enviada"). */
        success: "bg-success text-success-fg",
      },
      size: {
        /** 44px: ações secundárias, cabeçalho. */
        sm: "min-h-11 px-3.5",
        /** 48px: padrão de formulário. */
        md: "min-h-12 px-5",
        /** 56px: barra de ação inferior (ação principal ao alcance do polegar). */
        lg: "min-h-14 px-6",
        /** 44 × 44: só ícone (exige aria-label). */
        icon: "size-11 shrink-0 p-0",
      },
      block: { true: "w-full", false: "" },
      /** Ocupado: não esmaece como "desabilitado"; mostra o indicador. */
      busy: {
        true: "cursor-progress",
        false:
          "disabled:cursor-not-allowed disabled:opacity-55 aria-disabled:cursor-not-allowed aria-disabled:opacity-55",
      },
    },
    defaultVariants: { variant: "primary", size: "md", block: false, busy: false },
  },
);

export type ButtonVariants = Omit<VariantProps<typeof buttonVariants>, "busy">;

export type ButtonProps = ComponentProps<"button"> &
  ButtonVariants & {
    /** Mostra o indicador e bloqueia novo toque (sem esmaecer). */
    loading?: boolean;
    /** Rótulo durante o carregamento (ex.: "Entrando…"). Padrão: o próprio rótulo. */
    loadingLabel?: ReactNode;
  };

export function Button({
  className,
  variant,
  size,
  block,
  loading = false,
  loadingLabel,
  disabled,
  type = "button",
  children,
  ...props
}: ButtonProps) {
  return (
    <button
      type={type}
      disabled={disabled || loading}
      data-loading={loading || undefined}
      className={buttonVariants({ variant, size, block, busy: loading, className })}
      {...props}
    >
      {loading ? (
        <>
          <Spinner />
          {loadingLabel ?? children}
        </>
      ) : (
        children
      )}
    </button>
  );
}
