import Image from "next/image";

/**
 * Logos do manual da marca, servidos de public/brand/ (fora do proxy, D110). Nunca redesenhe
 * nem redigite o nome: use sempre estes arquivos.
 *
 * Proporções (viewBox dos SVGs): horizontal 767 × 120; principal 498 × 276.
 * Tamanho mínimo do manual: horizontal 150px, principal 110px de largura.
 */
const HORIZONTAL_RATIO = 119.59 / 767.07;
const PRINCIPAL_RATIO = 276.16 / 497.8;

type Tone = "laranja" | "branco" | "cacau";

export function LogoHorizontal({
  tone = "laranja",
  width = 150,
  className,
  priority = false,
}: {
  tone?: Tone;
  width?: number;
  className?: string;
  priority?: boolean;
}) {
  const w = Math.max(150, width);
  return (
    <Image
      src={`/brand/ede-horizontal-${tone}.svg`}
      alt="Éde Utilidades"
      width={w}
      height={Math.round(w * HORIZONTAL_RATIO)}
      className={className}
      priority={priority}
    />
  );
}

export function LogoPrincipal({
  tone = "laranja",
  width = 180,
  className,
}: {
  tone?: Exclude<Tone, "cacau">;
  width?: number;
  className?: string;
}) {
  const w = Math.max(110, width);
  return (
    <Image
      src={`/brand/ede-principal-${tone}.svg`}
      alt="Éde Utilidades"
      width={w}
      height={Math.round(w * PRINCIPAL_RATIO)}
      className={className}
    />
  );
}
