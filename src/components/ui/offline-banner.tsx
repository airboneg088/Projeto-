import { clsx } from "clsx";

import { IconCloudOff } from "@/components/icons";

import { Spinner } from "./spinner";

export type ConnectionStatus = "online" | "offline" | "syncing";

/** "1 envio aguardando conexão" / "3 envios aguardando conexão". */
export function pendingLabel(count: number): string {
  return count === 1 ? "1 envio aguardando conexão" : `${count} envios aguardando conexão`;
}

/** "Enviando 1 envio guardado…" / "Enviando 3 envios guardados…". */
export function syncingLabel(count: number): string {
  return count === 1 ? "Enviando 1 envio guardado…" : `Enviando ${count} envios guardados…`;
}

/**
 * Faixa de conexão (offline é o caso normal para quem executa). Cacau sobre creme no claro e o
 * inverso no escuro: o maior contraste da paleta, legível no sol. Online e sem fila: não aparece.
 */
export function OfflineBanner({
  status,
  pending,
  className,
}: {
  status: ConnectionStatus;
  pending: number;
  className?: string;
}) {
  if (status === "online" && pending === 0) return null;

  const syncing = status === "syncing" || (status === "online" && pending > 0);
  const title = syncing
    ? syncingLabel(pending)
    : pending > 0
      ? pendingLabel(pending)
      : "Você está sem conexão";
  const detail = syncing
    ? "Pode continuar usando. Avisamos se algo não passar."
    : pending > 0
      ? "Pode continuar. Enviamos sozinhos quando a internet voltar."
      : "Pode continuar. O que você fizer fica guardado no celular.";

  return (
    <div
      role="status"
      className={clsx(
        "flex items-start gap-3 rounded-m bg-inverse px-4 py-3 text-inverse-fg",
        className,
      )}
    >
      {syncing ? (
        <span className="mt-0.5 shrink-0">
          <Spinner size={20} />
        </span>
      ) : (
        <IconCloudOff size={22} className="mt-0.5 shrink-0" />
      )}
      <div className="min-w-0">
        <p className="font-semibold tabular-nums">{title}</p>
        <p>{detail}</p>
      </div>
    </div>
  );
}
