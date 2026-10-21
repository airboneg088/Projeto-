import { clsx } from "clsx";

/**
 * Bloco de esqueleto: pulso de opacidade (sem brilho correndo; parado com movimento reduzido).
 * Decorativo: quem anuncia o carregamento é o contêiner (role="status").
 */
export function Skeleton({ className }: { className?: string }) {
  return <span aria-hidden="true" className={clsx("skeleton block rounded-s", className)} />;
}

/** Esqueleto com a mesma forma do TaskCard (sem salto quando o conteúdo chega). */
export function TaskCardSkeleton() {
  return (
    <div className="flex flex-col gap-3 rounded-m bg-surface p-4" aria-hidden="true">
      <div className="flex items-start justify-between gap-3">
        <Skeleton className="h-7 w-32 rounded-full" />
        <Skeleton className="h-5 w-16" />
      </div>
      <Skeleton className="h-6 w-3/4" />
      <div className="flex gap-4">
        <Skeleton className="h-5 w-24" />
        <Skeleton className="h-5 w-28" />
      </div>
    </div>
  );
}

/** Lista de tarefas carregando. Nunca spinner de página inteira. */
export function TaskListSkeleton({
  count = 3,
  label = "Carregando tarefas…",
}: {
  count?: number;
  label?: string;
}) {
  return (
    <div role="status" aria-live="polite" className="flex flex-col gap-3">
      <span className="sr-only">{label}</span>
      {Array.from({ length: count }, (_, index) => (
        <TaskCardSkeleton key={index} />
      ))}
    </div>
  );
}
