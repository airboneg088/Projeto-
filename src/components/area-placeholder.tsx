import { clsx } from "clsx";

/** Corpo provisório de cada área: diz o que vem e em qual fase. */
export function AreaPlaceholder({
  title,
  phase,
  description,
  className,
}: {
  title: string;
  phase: string;
  description: string;
  className?: string;
}) {
  return (
    <section className={clsx("flex flex-col gap-3", className)}>
      <h1 className="text-2xl font-semibold">{title}</h1>
      <p className="max-w-prose">{description}</p>
      <p className="max-w-prose rounded-md bg-surface-1 px-4 py-3 text-text-muted">
        Esta área será entregue na <strong className="text-text">{phase}</strong>. Por enquanto,
        este é só o ponto de entrada.
      </p>
    </section>
  );
}
