import { clsx } from "clsx";
import type { ComponentProps, ReactNode } from "react";

import { IconAlert } from "@/components/icons";

/** Contorno, fundo e altura de todo campo (input e textarea). */
export const fieldClass =
  "block w-full rounded-m border border-border-control bg-surface px-3.5 text-base text-text aria-invalid:border-2 aria-invalid:border-danger-text disabled:cursor-not-allowed disabled:bg-surface-muted";

type FieldShellProps = {
  id: string;
  label: string;
  hint?: ReactNode;
  error?: string;
  className?: string;
  children: (describedBy: string | undefined) => ReactNode;
};

/** <label> real, dica e erro ligados por aria-describedby (erro com ícone + texto). */
function FieldShell({ id, label, hint, error, className, children }: FieldShellProps) {
  const hintId = hint ? `${id}-dica` : undefined;
  const errorId = error ? `${id}-erro` : undefined;
  const describedBy = [hintId, errorId].filter(Boolean).join(" ") || undefined;

  return (
    <div className={clsx("flex flex-col gap-1.5", className)}>
      <label htmlFor={id} className="type-body-strong text-text">
        {label}
      </label>
      {children(describedBy)}
      {hint ? (
        <p id={hintId} className="text-text-muted">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={errorId} className="flex items-start gap-1.5 font-medium text-danger-text">
          <IconAlert size={18} className="mt-0.5 shrink-0" />
          <span>{error}</span>
        </p>
      ) : null}
    </div>
  );
}

type TextFieldProps = Omit<ComponentProps<"input">, "id" | "name"> & {
  id: string;
  name: string;
  label: string;
  hint?: ReactNode;
  error?: string;
};

/** Campo de texto: 48px de altura, 16px de texto (evita o zoom automático do iOS). */
export function TextField({ id, name, label, hint, error, className, ...props }: TextFieldProps) {
  return (
    <FieldShell id={id} label={label} hint={hint} error={error} className={className}>
      {(describedBy) => (
        <input
          id={id}
          name={name}
          className={clsx(fieldClass, "min-h-12")}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          {...props}
        />
      )}
    </FieldShell>
  );
}

type TextAreaProps = Omit<ComponentProps<"textarea">, "id" | "name"> & {
  id: string;
  name: string;
  label: string;
  hint?: ReactNode;
  error?: string;
};

/** Campo de várias linhas (observação, motivo da reprovação). */
export function TextArea({
  id,
  name,
  label,
  hint,
  error,
  className,
  rows = 3,
  ...props
}: TextAreaProps) {
  return (
    <FieldShell id={id} label={label} hint={hint} error={error} className={className}>
      {(describedBy) => (
        <textarea
          id={id}
          name={name}
          rows={rows}
          className={clsx(fieldClass, "min-h-24 resize-y py-3 leading-6")}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          {...props}
        />
      )}
    </FieldShell>
  );
}
