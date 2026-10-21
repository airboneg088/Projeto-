"use client";

import { Dialog } from "@base-ui/react/dialog";
import { type FormEvent, type ReactElement, type RefObject, useId, useRef, useState } from "react";

import { Button } from "./button";
import { TextArea } from "./text-field";

type ReasonDialogProps = {
  /** Elemento que abre o dialog (normalmente um <Button>). */
  trigger: ReactElement;
  title: string;
  description: string;
  label: string;
  confirmLabel: string;
  /** Mensagem quando o motivo está em branco: diz o que fazer. */
  requiredMessage: string;
  minLength?: number;
  /** Recebe o motivo já sem espaços nas pontas. */
  onConfirm: (reason: string) => void;
  /** Onde montar o dialog (o catálogo monta dentro do quadro de cada tema). */
  container?: RefObject<HTMLElement | null>;
};

/**
 * Dialog com motivo obrigatório (reprovar, cancelar). Sem "segurar para confirmar": o campo
 * obrigatório já é a pausa. Centralizado (modal), entra com opacidade + escala 0.96 → 1 em
 * 240ms ease-out e sai mais rápido. Foco vai para o campo ao abrir e volta ao gatilho ao fechar.
 */
export function ReasonDialog({
  trigger,
  title,
  description,
  label,
  confirmLabel,
  requiredMessage,
  minLength = 3,
  onConfirm,
  container,
}: ReasonDialogProps) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string>();
  const fieldRef = useRef<HTMLTextAreaElement>(null);
  const id = useId();

  function reset(next: boolean) {
    setOpen(next);
    if (!next) {
      setReason("");
      setError(undefined);
    }
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    const value = reason.trim();
    if (value.length < minLength) {
      setError(requiredMessage);
      fieldRef.current?.focus();
      return;
    }
    onConfirm(value);
    reset(false);
  }

  return (
    <Dialog.Root open={open} onOpenChange={reset}>
      <Dialog.Trigger render={trigger} />
      <Dialog.Portal container={container}>
        <Dialog.Backdrop className="dialog-backdrop fixed inset-0 z-40 min-h-dvh" />
        <Dialog.Popup
          initialFocus={fieldRef}
          className="dialog-popup fixed top-1/2 left-1/2 z-50 flex max-h-[calc(100dvh-2rem)] w-[min(28rem,calc(100vw-2rem))] flex-col gap-5 overflow-y-auto rounded-l bg-surface p-6 text-text shadow-dialog"
        >
          <div className="flex flex-col gap-1.5">
            <Dialog.Title className="type-title-2">{title}</Dialog.Title>
            <Dialog.Description className="text-text-muted">{description}</Dialog.Description>
          </div>
          <form onSubmit={submit} noValidate className="flex flex-col gap-5">
            <TextArea
              ref={fieldRef}
              id={`${id}-motivo`}
              name="motivo"
              label={label}
              required
              rows={4}
              value={reason}
              error={error}
              onChange={(event) => {
                setReason(event.target.value);
                if (error) setError(undefined);
              }}
            />
            <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
              <Dialog.Close render={<Button variant="secondary" />}>Voltar</Dialog.Close>
              <Button type="submit" variant="danger">
                {confirmLabel}
              </Button>
            </div>
          </form>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
