import { clsx } from "clsx";
import type { ReactNode } from "react";

type NoticeProps = {
  tone: "error" | "success" | "info";
  children: ReactNode;
  className?: string;
  /** "alert" para erros que a pessoa precisa ouvir na hora; "status" para confirmações. */
  role?: "alert" | "status";
};

/** Aviso em bloco (texto + cor; nunca só cor). */
export function Notice({ tone, children, className, role }: NoticeProps) {
  return (
    <div
      role={role ?? (tone === "error" ? "alert" : "status")}
      className={clsx("notice", `notice-${tone}`, className)}
    >
      {children}
    </div>
  );
}
