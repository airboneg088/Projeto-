import { cva } from "class-variance-authority";
import type { ComponentType } from "react";

import {
  IconAlarm,
  IconApproved,
  IconAwaiting,
  IconCancelled,
  IconInProgress,
  IconPending,
  type IconProps,
  IconReturn,
} from "@/components/icons";
import { STATUS_ICON, type StatusIconName } from "@/lib/design/status";
import { STATUS, type StatusKey } from "@/lib/design/tokens";

const ICONS: Record<StatusIconName, ComponentType<IconProps>> = {
  pending: IconPending,
  "in-progress": IconInProgress,
  awaiting: IconAwaiting,
  approved: IconApproved,
  return: IconReturn,
  alarm: IconAlarm,
  cancelled: IconCancelled,
};

/**
 * Cores e forma por status (tokens `status-*`). Classes escritas por extenso para o Tailwind
 * encontrar. Forma: pendente com contorno, cancelada tracejada, atrasada cheia (DESIGN.md).
 */
const badgeVariants = cva(
  "inline-flex max-w-full items-center gap-1.5 rounded-full border type-meta font-semibold whitespace-nowrap",
  {
    variants: {
      status: {
        pendente: "border-status-pendente-border bg-status-pendente-bg text-status-pendente-fg",
        "em-andamento":
          "border-status-em-andamento-border bg-status-em-andamento-bg text-status-em-andamento-fg",
        "aguardando-aprovacao":
          "border-status-aguardando-aprovacao-border bg-status-aguardando-aprovacao-bg text-status-aguardando-aprovacao-fg",
        aprovada: "border-status-aprovada-border bg-status-aprovada-bg text-status-aprovada-fg",
        "correcao-solicitada":
          "border-status-correcao-solicitada-border bg-status-correcao-solicitada-bg text-status-correcao-solicitada-fg",
        atrasada: "border-status-atrasada-border bg-status-atrasada-bg text-status-atrasada-fg",
        cancelada:
          "border-dashed border-status-cancelada-border bg-status-cancelada-bg text-status-cancelada-fg",
      },
      size: {
        sm: "min-h-7 px-2.5",
        md: "min-h-8 px-3",
      },
    },
    defaultVariants: { size: "sm" },
  },
);

const ICON_COLOR: Record<StatusKey, string> = {
  pendente: "text-status-pendente-icon",
  "em-andamento": "text-status-em-andamento-icon",
  "aguardando-aprovacao": "text-status-aguardando-aprovacao-icon",
  aprovada: "text-status-aprovada-icon",
  "correcao-solicitada": "text-status-correcao-solicitada-icon",
  atrasada: "text-status-atrasada-icon",
  cancelada: "text-status-cancelada-icon",
};

/** Selo de status: cor + ícone + texto, sempre os três. */
export function StatusBadge({
  status,
  size = "sm",
  className,
}: {
  status: StatusKey;
  size?: "sm" | "md";
  className?: string;
}) {
  const Icon = ICONS[STATUS_ICON[status]];
  return (
    <span className={badgeVariants({ status, size, className })} data-status={status}>
      <Icon size={size === "md" ? 18 : 16} className={`shrink-0 ${ICON_COLOR[status]}`} />
      <span className="truncate">{STATUS[status].label}</span>
    </span>
  );
}
