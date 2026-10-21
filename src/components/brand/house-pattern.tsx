import { clsx } from "clsx";

/**
 * Padrão de casas do manual: o símbolo repetido em grade alternada, tom sobre tom (laranja claro
 * sobre laranja-ede). Decorativo. Regras: nunca atrás de texto pequeno nem dentro da área de
 * proteção do logo — por isso ocupa só a faixa do meio do painel laranja.
 * Os traçados são os do arquivo ede-simbolo-*.svg (sem redesenho).
 */
export function HousePattern({ className }: { className?: string }) {
  return (
    <svg
      aria-hidden="true"
      focusable="false"
      className={clsx("text-brand-pattern", className)}
      width="100%"
      height="100%"
    >
      <defs>
        <symbol id="ede-casa" viewBox="7.5 2.7 85 92.8">
          <path d="M60.75,27.57L73.42,3.73L82.25,8.43L69.58,32.27Z" fill="currentColor" />
          <path
            d="M13,90L13,50L50,16L87,50L87,90Z"
            fill="none"
            stroke="currentColor"
            strokeWidth="9"
            strokeLinejoin="round"
          />
          <path
            d="M23.036 -10.972H29.276L29.172 0H1.248V-5.2L4.368 -6.448V-30.212L1.248 -31.46V-36.66L14.768 -36.92H28.652V-26.416H22.412L21.58 -29.38H15.028V-22.36H24.336V-15.08H15.028V-7.54H22.204Z"
            transform="translate(34.74,82.50)"
            fill="currentColor"
          />
        </symbol>
        <pattern id="ede-casas" width="120" height="128" patternUnits="userSpaceOnUse">
          <use href="#ede-casa" x="10" y="8" width="44" height="48" />
          <use href="#ede-casa" x="70" y="72" width="44" height="48" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill="url(#ede-casas)" />
    </svg>
  );
}
