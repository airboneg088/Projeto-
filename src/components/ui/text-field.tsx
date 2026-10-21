import { clsx } from "clsx";
import type { ComponentProps } from "react";

type TextFieldProps = Omit<ComponentProps<"input">, "id" | "name"> & {
  id: string;
  name: string;
  label: string;
  hint?: string;
  error?: string;
};

/** Campo de texto com <label> real, dica e erro ligados por aria-describedby. */
export function TextField({ id, name, label, hint, error, className, ...props }: TextFieldProps) {
  const hintId = hint ? `${id}-dica` : undefined;
  const errorId = error ? `${id}-erro` : undefined;
  const describedBy = [hintId, errorId].filter(Boolean).join(" ") || undefined;

  return (
    <div className={clsx("flex flex-col gap-1.5", className)}>
      <label htmlFor={id} className="field-label">
        {label}
      </label>
      <input
        id={id}
        name={name}
        className="field-input"
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy}
        {...props}
      />
      {hint ? (
        <p id={hintId} className="field-hint">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={errorId} className="field-error">
          {error}
        </p>
      ) : null}
    </div>
  );
}
