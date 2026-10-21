import type { ComponentProps, ReactNode } from "react";

import { IconCheck, IconCloudUpload } from "@/components/icons";

import { type ButtonVariants, buttonVariants } from "./button";
import { Spinner } from "./spinner";

export type SubmitState = "idle" | "sending" | "sent";

type SubmitButtonProps = Omit<ComponentProps<"button">, "children"> &
  Pick<ButtonVariants, "size" | "block"> & {
    state: SubmitState;
    idleLabel?: ReactNode;
    sendingLabel?: ReactNode;
    sentLabel?: ReactNode;
    /** Frase anunciada ao leitor de tela quando termina (ex.: "Tarefa enviada para aprovação."). */
    sentAnnouncement?: string;
  };

/**
 * Botão de envio que troca de rótulo no lugar: Enviar → Enviando… → Enviada.
 * Os três rótulos ocupam a mesma célula (a largura não pula); a troca é opacidade + escala
 * 0.96 + blur de 2px (DESIGN.md › Movimento), 200ms ease-out. Só o rótulo ativo tem nome
 * acessível; o fim é anunciado por uma região role="status".
 */
export function SubmitButton({
  state,
  idleLabel = "Enviar",
  sendingLabel = "Enviando…",
  sentLabel = "Enviada",
  sentAnnouncement,
  size = "lg",
  block = true,
  className,
  type = "submit",
  disabled,
  ...props
}: SubmitButtonProps) {
  const labels: Array<[SubmitState, ReactNode, ReactNode]> = [
    ["idle", idleLabel, <IconCloudUpload key="icon" />],
    ["sending", sendingLabel, <Spinner key="icon" />],
    ["sent", sentLabel, <IconCheck key="icon" />],
  ];
  const busy = state !== "idle";

  return (
    <>
      <button
        type={type}
        disabled={disabled || busy}
        data-state={state}
        className={buttonVariants({
          variant: state === "sent" ? "success" : "primary",
          size,
          block,
          busy,
          className,
        })}
        {...props}
      >
        <span className="grid">
          {labels.map(([key, label, icon]) => (
            <span
              key={key}
              data-active={state === key}
              aria-hidden={state === key ? undefined : true}
              className="morph-label col-start-1 row-start-1 inline-flex items-center justify-center gap-2"
            >
              {icon}
              {label}
            </span>
          ))}
        </span>
      </button>
      <span role="status" className="sr-only">
        {state === "sent" ? (sentAnnouncement ?? sentLabel) : ""}
      </span>
    </>
  );
}
