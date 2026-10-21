import { clsx } from "clsx";
import Link from "next/link";
import type { ComponentType } from "react";

import {
  IconArrowDown,
  IconArrowUp,
  IconCamera,
  IconChevronsUp,
  IconClock,
  IconFlag,
  IconListChecks,
  IconMinus,
  IconPin,
  type IconProps,
  IconUser,
} from "@/components/icons";
import type { StatusKey } from "@/lib/design/tokens";

import { StatusBadge } from "./status-badge";

export type TaskPriority = "low" | "normal" | "high" | "urgent";

const PRIORITY: Record<
  TaskPriority,
  { label: string; icon: ComponentType<IconProps>; className: string }
> = {
  low: { label: "Baixa", icon: IconArrowDown, className: "text-text-muted" },
  normal: { label: "Normal", icon: IconMinus, className: "text-text-muted" },
  high: { label: "Alta", icon: IconArrowUp, className: "font-semibold text-accent-text" },
  urgent: { label: "Urgente", icon: IconChevronsUp, className: "font-semibold text-danger-text" },
};

export type TaskCardProps = {
  title: string;
  status: StatusKey;
  /** Início e fim da janela já formatados no fuso da loja ("07:30", "08:15"). */
  windowStart: string;
  windowEnd: string;
  sector: string;
  priority: TaskPriority;
  /** Tarefa crítica (escala para gerente e proprietária quando não feita na janela). */
  critical?: boolean;
  requiresPhoto?: boolean;
  /** Itens marcados do checklist. */
  progress?: { done: number; total: number };
  /** Frase curta do prazo ("Venceu às 08:15", "Faltam 25 min"). */
  deadlineNote?: string;
  assignee?: string;
  /** Destino ao tocar no cartão. Sem href, o cartão é só leitura. */
  href?: string;
  className?: string;
};

/**
 * Cartão de tarefa da lista do dia. O título é o link e cobre o cartão inteiro (o nome
 * acessível é só o título; o resto é lido como conteúdo). Números com tabular-nums.
 * Sem sombra e sem borda: o degrau de tom (branco sobre creme) separa do fundo.
 */
export function TaskCard({
  title,
  status,
  windowStart,
  windowEnd,
  sector,
  priority,
  critical = false,
  requiresPhoto = false,
  progress,
  deadlineNote,
  assignee,
  href,
  className,
}: TaskCardProps) {
  const prio = PRIORITY[priority];
  const PrioIcon = prio.icon;
  const late = status === "atrasada";

  return (
    <article
      data-status={status}
      className={clsx(
        "relative flex flex-col gap-3 rounded-m bg-surface p-4",
        href &&
          "pressable-soft hover:bg-surface-pressed has-focus-visible:outline-3 has-focus-visible:outline-offset-2 has-focus-visible:outline-focus has-focus-visible:outline-solid",
        status === "cancelada" && "text-text-muted",
        className,
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <StatusBadge status={status} />
        <span className={clsx("inline-flex min-h-7 items-center gap-1 type-meta", prio.className)}>
          <PrioIcon size={16} />
          <span>
            <span className="sr-only">Prioridade </span>
            {prio.label}
          </span>
        </span>
      </div>

      <h3 className="type-lead text-text">
        {href ? (
          <Link
            href={href}
            className="after:absolute after:inset-0 after:rounded-m focus-visible:outline-none"
          >
            {title}
          </Link>
        ) : (
          title
        )}
      </h3>

      <dl className="flex flex-wrap gap-x-4 gap-y-1.5 type-meta text-text-muted">
        <div>
          <dt className="sr-only">Janela</dt>
          <dd className="inline-flex items-center gap-1.5 tabular-nums">
            <IconClock size={16} />
            {windowStart}–{windowEnd}
          </dd>
        </div>
        <div>
          <dt className="sr-only">Setor</dt>
          <dd className="inline-flex items-center gap-1.5">
            <IconPin size={16} />
            {sector}
          </dd>
        </div>
        {progress ? (
          <div>
            <dt className="sr-only">Checklist</dt>
            <dd className="inline-flex items-center gap-1.5 tabular-nums">
              <IconListChecks size={16} />
              {progress.done} de {progress.total}
            </dd>
          </div>
        ) : null}
        {requiresPhoto ? (
          <div>
            <dt className="sr-only">Evidência</dt>
            <dd className="inline-flex items-center gap-1.5">
              <IconCamera size={16} />
              Com foto
            </dd>
          </div>
        ) : null}
        {assignee ? (
          <div>
            <dt className="sr-only">Responsável</dt>
            <dd className="inline-flex items-center gap-1.5">
              <IconUser size={16} />
              {assignee}
            </dd>
          </div>
        ) : null}
      </dl>

      {deadlineNote || critical ? (
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 type-meta">
          {critical ? (
            <span className="inline-flex items-center gap-1.5 font-semibold text-text">
              <IconFlag size={16} className="text-accent-text" />
              Tarefa crítica
            </span>
          ) : null}
          {deadlineNote ? (
            <span
              className={clsx(
                "tabular-nums",
                late ? "font-semibold text-danger-text" : "text-text-muted",
              )}
            >
              {deadlineNote}
            </span>
          ) : null}
        </div>
      ) : null}
    </article>
  );
}
