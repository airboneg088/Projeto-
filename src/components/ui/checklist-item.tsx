"use client";

import { clsx } from "clsx";
import { useEffect, useId, useRef } from "react";

import { IconCamera, IconClose, IconFlag } from "@/components/icons";

import { Button } from "./button";
import { TextArea } from "./text-field";

/**
 * Resposta de um item (D47): marcado = feito; desmarcado com observação = não conforme;
 * desmarcado sem observação = ainda não respondido.
 */
export type ChecklistValue = "pending" | "done" | "not_ok";

export type ChecklistItemProps = {
  text: string;
  value: ChecklistValue;
  note?: string;
  critical?: boolean;
  requiresPhoto?: boolean;
  disabled?: boolean;
  /** Erro da observação (ex.: tentou enviar com "não conforme" sem texto). */
  noteError?: string;
  onChange?: (value: ChecklistValue) => void;
  onNoteChange?: (note: string) => void;
  className?: string;
};

/**
 * Item do checklist. A linha inteira (>= 56px) marca e desmarca; a caixa encolhe ao pressionar
 * e o check é desenhado em 180ms (com movimento reduzido, só aparece). "Não conforme" é ação
 * separada e pede a observação, com <label> real.
 */
export function ChecklistItem({
  text,
  value,
  note = "",
  critical = false,
  requiresPhoto = false,
  disabled = false,
  noteError,
  onChange,
  onNoteChange,
  className,
}: ChecklistItemProps) {
  const id = useId();
  const textId = `${id}-texto`;
  const metaId = `${id}-meta`;
  const noteId = `${id}-obs`;
  const noteRef = useRef<HTMLTextAreaElement>(null);
  const previous = useRef(value);

  // Ao marcar "não conforme" pelo toque, leva o foco para a observação.
  useEffect(() => {
    if (previous.current !== "not_ok" && value === "not_ok") noteRef.current?.focus();
    previous.current = value;
  }, [value]);

  const hasMeta = critical || requiresPhoto || value === "not_ok";
  const notOk = value === "not_ok";

  return (
    <div
      data-state={value}
      className={clsx(
        "rounded-m bg-surface",
        notOk && "outline-2 -outline-offset-2 outline-danger-text outline-solid",
        className,
      )}
    >
      <button
        type="button"
        role="checkbox"
        aria-checked={value === "done"}
        aria-labelledby={textId}
        aria-describedby={hasMeta ? metaId : undefined}
        disabled={disabled}
        onClick={() => onChange?.(value === "done" ? "pending" : "done")}
        className="check-row flex min-h-14 w-full touch-manipulation items-start gap-3 rounded-m px-3 py-3.5 text-left select-none hover:bg-surface-pressed active:bg-surface-pressed disabled:cursor-not-allowed"
      >
        <span
          aria-hidden="true"
          className={clsx(
            "check-box grid size-7 shrink-0 place-items-center rounded-s border-2",
            value === "done" && "border-accent bg-accent text-accent-fg",
            value === "pending" && "border-border-control bg-surface",
            notOk && "border-danger-text bg-surface text-danger-text",
          )}
        >
          {notOk ? (
            <IconClose size={18} strokeWidth={2.75} />
          ) : (
            <svg viewBox="0 0 24 24" width={20} height={20} fill="none" focusable="false">
              <path
                className="check-path"
                pathLength={1}
                d="m5 12.5 4.5 4.5L19 7.5"
                stroke="currentColor"
                strokeWidth={3}
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          )}
        </span>
        <span className="min-w-0 flex-1 pt-0.5">
          <span id={textId} className="block text-text">
            {text}
          </span>
          {hasMeta ? (
            <span
              id={metaId}
              className="mt-1 flex flex-wrap gap-x-3 gap-y-1 type-meta text-text-muted"
            >
              {notOk ? (
                <span className="inline-flex items-center gap-1 font-semibold text-danger-text">
                  Não conforme
                </span>
              ) : null}
              {critical ? (
                <span className="inline-flex items-center gap-1 font-semibold text-text">
                  <IconFlag size={16} className="text-accent-text" />
                  Item crítico
                </span>
              ) : null}
              {requiresPhoto ? (
                <span className="inline-flex items-center gap-1">
                  <IconCamera size={16} />
                  Foto obrigatória
                </span>
              ) : null}
            </span>
          ) : null}
        </span>
      </button>

      {value === "pending" && !disabled ? (
        <div className="pb-1.5 pl-[3.25rem]">
          <Button
            variant="ghost"
            size="sm"
            className="-ml-3.5 text-text-muted"
            onClick={() => onChange?.("not_ok")}
          >
            <IconClose size={18} />
            Não está conforme
          </Button>
        </div>
      ) : null}

      {notOk ? (
        <div className="flex flex-col gap-2 px-3 pb-3 pl-[3.25rem]">
          <TextArea
            ref={noteRef}
            id={noteId}
            name={noteId}
            label="O que não está conforme?"
            hint="Conte o que viu. Sem a observação, o item fica sem resposta."
            value={note}
            error={noteError}
            disabled={disabled}
            rows={2}
            onChange={(event) => onNoteChange?.(event.target.value)}
          />
          {!disabled ? (
            <Button
              variant="ghost"
              size="sm"
              className="-ml-3.5 self-start"
              onClick={() => onChange?.("pending")}
            >
              Desfazer
            </Button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
