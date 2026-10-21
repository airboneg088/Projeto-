import type { ReactNode, SVGProps } from "react";

/**
 * Ícones de linha do Éde Gestão (DESIGN.md › Iconografia): traço arredondado de 2px numa grade
 * de 24, o mesmo peso relativo do traço da casa do logo. Cor = currentColor (cacau, laranja-brasa
 * ou a cor do status). Sem biblioteca: só os ícones que a interface usa.
 *
 * Acessibilidade: sem `title`, o ícone é decorativo (aria-hidden) e o texto ao lado diz o que é.
 * Com `title`, vira imagem com nome (role="img" + aria-label), para ícone sozinho.
 */
export type IconProps = Omit<SVGProps<SVGSVGElement>, "children"> & {
  /** Tamanho em px (largura = altura). Padrão 20. */
  size?: number;
  /** Nome acessível quando o ícone aparece sem texto ao lado. */
  title?: string;
};

function createIcon(displayName: string, paths: ReactNode) {
  function Icon({ size = 20, title, strokeWidth = 2, ...props }: IconProps) {
    return (
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        width={size}
        height={size}
        fill="none"
        stroke="currentColor"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
        focusable="false"
        {...(title ? { role: "img", "aria-label": title } : { "aria-hidden": true })}
        {...props}
      >
        {paths}
      </svg>
    );
  }
  Icon.displayName = displayName;
  return Icon;
}

/* Status da tarefa: silhuetas diferentes, não só cores diferentes. */

/** Pendente: círculo vazio (ainda não começou). */
export const IconPending = createIcon("IconPending", <circle cx="12" cy="12" r="8.25" />);

/** Em andamento: círculo meio cheio. */
export const IconInProgress = createIcon(
  "IconInProgress",
  <>
    <circle cx="12" cy="12" r="8.25" />
    <path d="M12 7.25a4.75 4.75 0 0 1 0 9.5Z" fill="currentColor" />
  </>,
);

/** Aguardando aprovação: ampulheta. */
export const IconAwaiting = createIcon(
  "IconAwaiting",
  <>
    <path d="M6.5 3.75h11" />
    <path d="M6.5 20.25h11" />
    <path d="M7.75 3.75c0 4.25 4.25 5.25 4.25 8.25s-4.25 4-4.25 8.25" />
    <path d="M16.25 3.75c0 4.25-4.25 5.25-4.25 8.25s4.25 4 4.25 8.25" />
  </>,
);

/** Aprovada: círculo com check. */
export const IconApproved = createIcon(
  "IconApproved",
  <>
    <circle cx="12" cy="12" r="8.25" />
    <path d="m8.25 12.25 2.5 2.5 5-5.25" />
  </>,
);

/** Correção solicitada: seta de retorno (volta para quem fez). */
export const IconReturn = createIcon(
  "IconReturn",
  <>
    <path d="M9 14.5 4.5 10 9 5.5" />
    <path d="M4.5 10H14a5.25 5.25 0 0 1 0 10.5h-3" />
  </>,
);

/** Atrasada: despertador. */
export const IconAlarm = createIcon(
  "IconAlarm",
  <>
    <circle cx="12" cy="13" r="7.25" />
    <path d="M12 9.5V13l2.25 1.75" />
    <path d="M4.75 3.75 2.75 5.75" />
    <path d="m19.25 3.75 2 2" />
  </>,
);

/** Cancelada: círculo cortado. */
export const IconCancelled = createIcon(
  "IconCancelled",
  <>
    <circle cx="12" cy="12" r="8.25" />
    <path d="m6.25 6.25 11.5 11.5" />
  </>,
);

/* Ações e informação */

export const IconCheck = createIcon("IconCheck", <path d="m5 12.5 4.5 4.5L19 7.5" />);

export const IconClose = createIcon(
  "IconClose",
  <>
    <path d="m6.5 6.5 11 11" />
    <path d="m17.5 6.5-11 11" />
  </>,
);

export const IconCamera = createIcon(
  "IconCamera",
  <>
    <path d="M3.75 8.75A1.75 1.75 0 0 1 5.5 7h2.25l1.5-2.25h5.5L16.25 7h2.25a1.75 1.75 0 0 1 1.75 1.75v8.5A1.75 1.75 0 0 1 18.5 19h-13a1.75 1.75 0 0 1-1.75-1.75Z" />
    <circle cx="12" cy="12.75" r="3.25" />
  </>,
);

export const IconImage = createIcon(
  "IconImage",
  <>
    <rect x="3.75" y="4.75" width="16.5" height="14.5" rx="2" />
    <circle cx="9" cy="10" r="1.5" />
    <path d="m20.25 15.5-4.75-4.75L6 19.25" />
  </>,
);

export const IconCloudOff = createIcon(
  "IconCloudOff",
  <>
    <path d="m3.5 3.5 17 17" />
    <path d="M9.1 5.9A5.5 5.5 0 0 1 17 9.75a4.25 4.25 0 0 1 3 6.9" />
    <path d="M16.75 18.25H7a4.5 4.5 0 0 1-1.6-8.7" />
  </>,
);

export const IconCloudUpload = createIcon(
  "IconCloudUpload",
  <>
    <path d="M7.25 18.25A4.5 4.5 0 0 1 6.5 9.3a5.5 5.5 0 0 1 10.5.45 4.25 4.25 0 0 1 0 8.5" />
    <path d="M12 12.25v7" />
    <path d="m9.25 14.75 2.75-2.75 2.75 2.75" />
  </>,
);

export const IconRetry = createIcon(
  "IconRetry",
  <>
    <path d="M19.5 11A7.5 7.5 0 0 0 6.2 6.95L4.5 8.5" />
    <path d="M4.5 4.5v4h4" />
    <path d="M4.5 13a7.5 7.5 0 0 0 13.3 4.05l1.7-1.55" />
    <path d="M19.5 19.5v-4h-4" />
  </>,
);

export const IconAlert = createIcon(
  "IconAlert",
  <>
    <path d="M10.3 4.3 2.95 17.1A2 2 0 0 0 4.7 20.1h14.6a2 2 0 0 0 1.75-3L13.7 4.3a2 2 0 0 0-3.4 0Z" />
    <path d="M12 9.5v4" />
    <path d="M12 16.75h.01" />
  </>,
);

export const IconInfo = createIcon(
  "IconInfo",
  <>
    <circle cx="12" cy="12" r="8.25" />
    <path d="M12 11v5" />
    <path d="M12 7.75h.01" />
  </>,
);

export const IconClock = createIcon(
  "IconClock",
  <>
    <circle cx="12" cy="12" r="8.25" />
    <path d="M12 7.5V12l3 2" />
  </>,
);

/** Item ou tarefa crítica. */
export const IconFlag = createIcon(
  "IconFlag",
  <>
    <path d="M5.75 20.5V4.25" />
    <path d="M5.75 4.25h11.5l-2.75 4.25 2.75 4.25H5.75" />
  </>,
);

/** Prioridade alta. */
export const IconArrowUp = createIcon(
  "IconArrowUp",
  <>
    <path d="M12 19V5.5" />
    <path d="m6.5 11 5.5-5.5 5.5 5.5" />
  </>,
);

/** Prioridade urgente. */
export const IconChevronsUp = createIcon(
  "IconChevronsUp",
  <>
    <path d="m6.5 12 5.5-5.5 5.5 5.5" />
    <path d="m6.5 18 5.5-5.5 5.5 5.5" />
  </>,
);

/** Prioridade baixa. */
export const IconArrowDown = createIcon(
  "IconArrowDown",
  <>
    <path d="M12 5v13.5" />
    <path d="m17.5 13-5.5 5.5L6.5 13" />
  </>,
);

/** Prioridade normal. */
export const IconMinus = createIcon("IconMinus", <path d="M6 12h12" />);

/** Setor da loja. */
export const IconPin = createIcon(
  "IconPin",
  <>
    <path d="M12 20.75s-6.25-5.4-6.25-10.5a6.25 6.25 0 0 1 12.5 0c0 5.1-6.25 10.5-6.25 10.5Z" />
    <circle cx="12" cy="10.25" r="2.25" />
  </>,
);

/** Loja. */
export const IconStore = createIcon(
  "IconStore",
  <>
    <path d="M4 9.25 5.5 4.75h13L20 9.25" />
    <path d="M4 9.25h16v1a2.75 2.75 0 0 1-5.33.95 2.75 2.75 0 0 1-5.34 0A2.75 2.75 0 0 1 4 10.25Z" />
    <path d="M5.25 12.75v6.5h13.5v-6.5" />
  </>,
);

export const IconUser = createIcon(
  "IconUser",
  <>
    <circle cx="12" cy="8.5" r="3.75" />
    <path d="M4.75 20a7.25 7.25 0 0 1 14.5 0" />
  </>,
);

export const IconSun = createIcon(
  "IconSun",
  <>
    <circle cx="12" cy="12" r="3.75" />
    <path d="M12 2.75v1.5M12 19.75v1.5M2.75 12h1.5M19.75 12h1.5M5.45 5.45l1.06 1.06M17.49 17.49l1.06 1.06M5.45 18.55l1.06-1.06M17.49 6.51l1.06-1.06" />
  </>,
);

export const IconMoon = createIcon(
  "IconMoon",
  <path d="M19.75 14.25A7.75 7.75 0 1 1 9.75 4.25a6.25 6.25 0 0 0 10 10Z" />,
);

export const IconLogOut = createIcon(
  "IconLogOut",
  <>
    <path d="M14.25 4.25h3.5A1.75 1.75 0 0 1 19.5 6v12a1.75 1.75 0 0 1-1.75 1.75h-3.5" />
    <path d="M9.5 16.25 5.25 12 9.5 7.75" />
    <path d="M5.25 12h9.5" />
  </>,
);

export const IconChevronRight = createIcon(
  "IconChevronRight",
  <path d="m9.5 5.75 6.25 6.25-6.25 6.25" />,
);

/** Lista vazia. */
export const IconInbox = createIcon(
  "IconInbox",
  <>
    <path d="M3.75 13.25 6.4 5.5a1.5 1.5 0 0 1 1.42-1h8.36a1.5 1.5 0 0 1 1.42 1l2.65 7.75v5a1.75 1.75 0 0 1-1.75 1.75H5.5a1.75 1.75 0 0 1-1.75-1.75Z" />
    <path d="M3.75 13.25h4.5l1.25 2.25h5l1.25-2.25h4.5" />
  </>,
);

/** Observação. */
export const IconNote = createIcon(
  "IconNote",
  <>
    <path d="M15.25 4.75 19.25 8.75 9.5 18.5H5.5v-4Z" />
    <path d="m13 7 4 4" />
  </>,
);

export const IconTrash = createIcon(
  "IconTrash",
  <>
    <path d="M4.75 7h14.5" />
    <path d="M9.75 7V4.75h4.5V7" />
    <path d="m6.75 7 .9 12.25a1.5 1.5 0 0 0 1.5 1.25h5.7a1.5 1.5 0 0 0 1.5-1.25L17.25 7" />
  </>,
);

/** Checklist (contagem de itens). */
export const IconListChecks = createIcon(
  "IconListChecks",
  <>
    <path d="m4 6.75 1.5 1.5 2.75-2.75" />
    <path d="m4 13.75 1.5 1.5 2.75-2.75" />
    <path d="M11.75 7.25h8.25" />
    <path d="M11.75 14.25h8.25" />
    <path d="M11.75 19.25h8.25" />
  </>,
);
