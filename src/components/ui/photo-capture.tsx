import { clsx } from "clsx";

import { IconCamera, IconCloudOff, IconRetry, IconTrash } from "@/components/icons";

import { Button } from "./button";
import { Notice } from "./notice";
import { Spinner } from "./spinner";

export type PhotoCaptureState = "empty" | "preview" | "uploading" | "error" | "queued";

export type PhotoCaptureProps = {
  state: PhotoCaptureState;
  /** O que fotografar ("Foto do salão limpo"). */
  label: string;
  required?: boolean;
  /** URL da prévia (blob: do aparelho ou URL assinada de até 5 min, D77). */
  previewSrc?: string;
  /** Texto alternativo da prévia (obrigatório quando há prévia). */
  previewAlt?: string;
  /** Horário da captura já formatado no fuso da loja ("07:42"). */
  capturedAt?: string;
  /** 0 a 100 durante o envio. */
  progress?: number;
  errorMessage?: string;
  onCapture?: () => void;
  onRemove?: () => void;
  onRetry?: () => void;
  className?: string;
};

/**
 * Casca visual da captura de foto (Fase 2). A câmera de verdade (`capture="environment"`,
 * getUserMedia, compressão, marca d'água) entra na Fase 3 por trás de `onCapture`.
 * Estados: vazio, prévia, enviando (barra por transform), erro (com "Tentar de novo") e
 * guardada sem conexão.
 */
export function PhotoCapture({
  state,
  label,
  required = false,
  previewSrc,
  previewAlt,
  capturedAt,
  progress = 0,
  errorMessage = "Não deu para enviar a foto. Confira a internet e toque em Tentar de novo.",
  onCapture,
  onRemove,
  onRetry,
  className,
}: PhotoCaptureProps) {
  const hasPreview = state !== "empty" && !!previewSrc;
  const pct = Math.max(0, Math.min(100, Math.round(progress)));

  return (
    <section className={clsx("flex flex-col gap-3", className)}>
      <div className="flex items-baseline justify-between gap-3">
        <h3 className="type-body-strong text-text">{label}</h3>
        {required ? <span className="type-meta text-text-muted">Obrigatória</span> : null}
      </div>

      {hasPreview ? (
        <figure className="relative overflow-hidden rounded-m bg-surface-muted">
          {/* Prévia vem de blob: (aparelho) ou URL assinada; o otimizador de imagens não serve. */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={previewSrc}
            alt={previewAlt ?? label}
            className={clsx(
              "aspect-[4/3] w-full object-cover",
              state === "uploading" && "opacity-60",
            )}
          />
          {capturedAt ? (
            <figcaption className="absolute bottom-2 left-2 rounded-s bg-inverse px-2 py-0.5 type-meta tabular-nums text-inverse-fg">
              Tirada às {capturedAt}
            </figcaption>
          ) : null}
        </figure>
      ) : (
        <button
          type="button"
          onClick={onCapture}
          className="pressable-soft flex aspect-[4/3] w-full flex-col items-center justify-center gap-3 rounded-m border-2 border-dashed border-border-control bg-surface-muted px-4 text-center hover:bg-surface-pressed"
        >
          <span className="grid size-14 place-items-center rounded-full bg-surface text-accent-text">
            <IconCamera size={28} />
          </span>
          <span className="type-body-strong text-text">Tirar foto</span>
          <span className="max-w-64 text-text-muted">Use a câmera do celular, na hora.</span>
        </button>
      )}

      {state === "uploading" ? (
        <div className="flex flex-col gap-2" role="status">
          <div className="flex items-center justify-between gap-3 type-meta text-text">
            <span className="inline-flex items-center gap-2">
              <Spinner size={16} />
              Enviando foto…
            </span>
            <span className="tabular-nums">{pct}%</span>
          </div>
          <div
            role="progressbar"
            aria-label="Envio da foto"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={pct}
            className="h-2 overflow-hidden rounded-full bg-surface-muted"
          >
            <div
              className="progress-fill h-full w-full rounded-full bg-accent"
              style={{ transform: `scaleX(${pct / 100})` }}
            />
          </div>
        </div>
      ) : null}

      {state === "error" ? (
        <Notice
          tone="error"
          action={
            <Button variant="secondary" size="sm" onClick={onRetry}>
              <IconRetry size={18} />
              Tentar de novo
            </Button>
          }
        >
          {errorMessage}
        </Notice>
      ) : null}

      {state === "queued" ? (
        <p
          role="status"
          className="flex items-start gap-2.5 rounded-m bg-inverse px-4 py-3 text-inverse-fg"
        >
          <IconCloudOff size={20} className="mt-0.5 shrink-0" />
          <span>Foto guardada no celular. Ela vai sozinha quando a conexão voltar.</span>
        </p>
      ) : null}

      {hasPreview && state !== "uploading" ? (
        <div className="flex gap-2">
          <Button variant="secondary" size="sm" onClick={onCapture}>
            <IconCamera size={18} />
            Tirar outra
          </Button>
          <Button variant="ghost" size="sm" onClick={onRemove}>
            <IconTrash size={18} />
            Remover
          </Button>
        </div>
      ) : null}
    </section>
  );
}
