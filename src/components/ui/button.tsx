import { type VariantProps, cva } from "class-variance-authority";
import type { ComponentProps } from "react";

/**
 * Botão base (provisório até a Fase 2). Estilos em globals.css (.btn*): alvo de toque >= 44px,
 * escala 0.97 ao pressionar, hover só com mouse e sem movimento em prefers-reduced-motion.
 */
export const buttonVariants = cva("btn", {
  variants: {
    variant: {
      primary: "btn-primary",
      secondary: "btn-secondary",
      ghost: "btn-ghost",
    },
    size: {
      md: "",
      sm: "btn-sm",
    },
    block: {
      true: "btn-block",
      false: "",
    },
  },
  defaultVariants: {
    variant: "primary",
    size: "md",
    block: false,
  },
});

export type ButtonProps = ComponentProps<"button"> & VariantProps<typeof buttonVariants>;

export function Button({
  className,
  variant,
  size,
  block,
  type = "button",
  ...props
}: ButtonProps) {
  return (
    <button
      type={type}
      className={buttonVariants({ variant, size, block, className })}
      {...props}
    />
  );
}
