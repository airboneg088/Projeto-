/**
 * Indicador de "trabalhando" DENTRO de um controle (botão, envio de foto). Nunca de página
 * inteira: tela carregando usa Skeleton. Com movimento reduzido, pulsa em vez de girar.
 */
export function Spinner({ size = 18 }: { size?: number }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      aria-hidden="true"
      focusable="false"
      className="spinner shrink-0"
    >
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.3" strokeWidth="2.5" />
      <path
        d="M21 12a9 9 0 0 0-9-9"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
      />
    </svg>
  );
}
