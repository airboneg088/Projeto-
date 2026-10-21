import { cva } from "class-variance-authority";
import type { ComponentType, ReactNode } from "react";

import {
  IconAlert,
  IconApproved,
  IconCloudOff,
  IconInfo,
  type IconProps,
} from "@/components/icons";

export type NoticeTone = "error" | "success" | "info" | "warning";

const noticeVariants = cva("flex items-start gap-2.5 rounded-m px-4 py-3", {
  variants: {
    tone: {
      error: "bg-notice-error-bg text-notice-error-fg",
      success: "bg-notice-success-bg text-notice-success-fg",
      info: "bg-notice-info-bg text-notice-info-fg",
      warning: "bg-notice-warning-bg text-notice-warning-fg",
    },
  },
});

const ICON: Record<NoticeTone, ComponentType<IconProps>> = {
  error: IconAlert,
  success: IconApproved,
  info: IconInfo,
  warning: IconCloudOff,
};

type NoticeProps = {
  tone: NoticeTone;
  children: ReactNode;
  className?: string;
  /** "alert" para erros que a pessoa precisa ouvir na hora; "status" para confirmações. */
  role?: "alert" | "status";
  /** Ação de recuperação ao lado da mensagem (ex.: "Tentar de novo"). */
  action?: ReactNode;
};

/**
 * Aviso em bloco: ícone + texto (nunca só cor). O texto do aviso é todo o texto do elemento
 * (o ícone é decorativo), então `toHaveText` dos testes continua exato.
 */
export function Notice({ tone, children, className, role, action }: NoticeProps) {
  const Icon = ICON[tone];
  return (
    <div
      role={role ?? (tone === "error" ? "alert" : "status")}
      className={noticeVariants({ tone, className })}
    >
      <Icon size={20} className="mt-0.5 shrink-0" />
      <div className="min-w-0 flex-1">
        {children}
        {action ? <div className="mt-2">{action}</div> : null}
      </div>
    </div>
  );
}
