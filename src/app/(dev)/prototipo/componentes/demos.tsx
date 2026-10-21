"use client";

import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { type ChecklistValue, ChecklistItem } from "@/components/ui/checklist-item";
import { ReasonDialog } from "@/components/ui/reason-dialog";
import { type SubmitState, SubmitButton } from "@/components/ui/submit-button";

import { CHECKLIST_ABERTURA, PESSOA_CURTA } from "../_fixtures";

/** Checklist da abertura: toque para marcar, "Não está conforme" pede a observação. */
export function ChecklistDemo() {
  const [items, setItems] = useState(() =>
    CHECKLIST_ABERTURA.map((item) => ({ ...item, note: item.note ?? "" })),
  );
  const answered = items.filter(
    (item) => item.value === "done" || (item.value === "not_ok" && item.note.trim() !== ""),
  ).length;

  function update(index: number, patch: Partial<{ value: ChecklistValue; note: string }>) {
    setItems((current) => current.map((item, i) => (i === index ? { ...item, ...patch } : item)));
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="type-meta tabular-nums text-text-muted" aria-live="polite">
        {answered} de {items.length} itens respondidos
      </p>
      <ul className="flex flex-col gap-2">
        {items.map((item, index) => (
          <li key={item.text}>
            <ChecklistItem
              text={item.text}
              value={item.value}
              note={item.note}
              critical={item.critical}
              requiresPhoto={item.requiresPhoto}
              onChange={(value) => update(index, { value })}
              onNoteChange={(note) => update(index, { note })}
            />
          </li>
        ))}
      </ul>
    </div>
  );
}

/** Enviar → Enviando… → Enviada, com "Recomeçar" para ver de novo. */
export function SubmitDemo({ block = true }: { block?: boolean }) {
  const [state, setState] = useState<SubmitState>("idle");
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);

  return (
    <div className="flex flex-col gap-2">
      <SubmitButton
        type="button"
        block={block}
        state={state}
        sentAnnouncement="Tarefa enviada para aprovação."
        onClick={() => {
          setState("sending");
          timer.current = setTimeout(() => setState("sent"), 1100);
        }}
      />
      {state === "sent" ? (
        <Button variant="ghost" size="sm" className="self-start" onClick={() => setState("idle")}>
          Recomeçar
        </Button>
      ) : null}
    </div>
  );
}

/** Reprovar com motivo obrigatório. O dialog monta dentro do quadro (herda o tema dele). */
export function ReasonDialogDemo() {
  const container = useRef<HTMLDivElement>(null);
  return (
    <div ref={container}>
      <ReasonDialog
        container={container}
        trigger={<Button variant="danger">Reprovar</Button>}
        title="Reprovar a tarefa"
        description={`${PESSOA_CURTA} vai ver o motivo e refazer a tarefa.`}
        label="O que precisa ser corrigido?"
        confirmLabel="Reprovar"
        requiredMessage="Escreva o motivo para reprovar. Ele aparece para quem fez a tarefa."
        onConfirm={() => toast.success("Correção solicitada. O motivo foi para quem fez a tarefa.")}
      />
    </div>
  );
}
