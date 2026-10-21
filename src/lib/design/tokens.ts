/**
 * Tokens de design do Éde Gestão: fonte única dos valores.
 *
 * - O CSS (src/app/tokens.css) e as tabelas do DESIGN.md são GERADOS daqui por `pnpm tokens`
 *   (render.ts). O teste tokens-sync.test.ts falha se os arquivos estiverem desatualizados.
 * - contrast.test.ts confere cada par de CONTRAST_PAIRS nos dois temas (WCAG AA).
 *
 * A identidade é o manual da marca da Éde Utilidades (cores, Bitter + Figtree, raios, espaços).
 * Os tokens de interface (superfícies, estados, status) são derivados dela para o modo Operate.
 * Este arquivo não importa nada: é lido pelo app, pelos testes e pelo gerador.
 */

export const THEMES = ["light", "dark"] as const;
export type ThemeName = (typeof THEMES)[number];

/** Paleta do manual da marca (marca-README.md), sem alteração. */
export const BRAND = {
  "laranja-ede": "#EE5D06",
  "laranja-brasa": "#C2470A",
  cacau: "#2A1810",
  "cacau-suave": "#6B5A50",
  creme: "#FFF4E8",
  areia: "#F3E6D6",
  branco: "#FFFFFF",
  "amarelo-oferta": "#FFC233",
} as const;

type ThemeValue = { light: string; dark: string; usage: string };

/**
 * Papéis de cor da interface. Cada um vira a variável CSS `--<nome>` (muda com o tema) e a cor
 * `--color-<nome>` do Tailwind (utilitários `bg-<nome>`, `text-<nome>`, `border-<nome>`…).
 */
export const COLORS = {
  bg: {
    light: BRAND.creme,
    dark: "#170E09",
    usage: "Fundo da página (creme da marca no claro; cacau quase preto no escuro).",
  },
  surface: {
    light: BRAND.branco,
    dark: "#221610",
    usage: "Cartões, cabeçalho, campos, barra de ação: um degrau acima do fundo.",
  },
  "surface-muted": {
    light: BRAND.areia,
    dark: "#2E2018",
    usage: "Blocos que se separam do fundo (areia da marca): estados vazios, esqueleto, faixas.",
  },
  "surface-pressed": {
    light: "#EADAC6",
    dark: "#3B2A20",
    usage: "Degrau seguinte: hover (só com mouse) e item pressionado.",
  },
  text: {
    light: BRAND.cacau,
    dark: BRAND.creme,
    usage: "Texto principal.",
  },
  "text-muted": {
    light: BRAND["cacau-suave"],
    dark: "#CDBBAC",
    usage: "Texto secundário: horário, setor, legenda, dica de campo.",
  },
  brand: {
    light: BRAND["laranja-ede"],
    dark: BRAND["laranja-ede"],
    usage:
      "Laranja da marca: logo e marcas grandes. Nunca texto pequeno nem fundo de texto pequeno branco.",
  },
  "brand-fg": {
    light: BRAND.branco,
    dark: BRAND.branco,
    usage: "Logo e título sobre laranja-ede: só texto de 24px+ ou negrito de 19px+ (3,39:1).",
  },
  "brand-pattern": {
    light: "#F3711F",
    dark: "#F3711F",
    usage:
      "Padrão de casas tom sobre tom no painel laranja das páginas públicas. Decorativo, nunca atrás de texto pequeno.",
  },
  accent: {
    light: BRAND["laranja-brasa"],
    dark: BRAND["laranja-ede"],
    usage: "Ação principal (fundo do botão primário), item marcado do checklist, seleção.",
  },
  "accent-hover": {
    light: "#A63B07",
    dark: "#FF7A2E",
    usage: "Botão primário com o mouse em cima.",
  },
  "accent-fg": {
    light: BRAND.branco,
    dark: BRAND.cacau,
    usage: "Texto e ícone sobre `accent` (branco sobre brasa; cacau sobre laranja no escuro).",
  },
  "accent-text": {
    light: "#A83C07",
    dark: "#FF9A5E",
    usage:
      "Laranja de texto pequeno: links e números de destaque. Brasa um pouco mais escura para passar também sobre areia.",
  },
  focus: {
    light: BRAND["laranja-brasa"],
    dark: "#FF9A5E",
    usage: "Anel de foco (3px, afastado 2px do elemento).",
  },
  border: {
    light: "#E6D5C0",
    dark: "#3B2A20",
    usage: "Divisória decorativa: degrau de tom, 1px. Nunca linha grossa.",
  },
  "border-control": {
    light: "#8C7868",
    dark: "#8F7A6B",
    usage: "Contorno de campo, caixa de seleção e botão secundário (>= 3:1 com o fundo).",
  },
  danger: {
    light: "#B3261E",
    dark: "#F2877D",
    usage: "Fundo do botão de perigo.",
  },
  "danger-hover": {
    light: "#951E17",
    dark: "#F59D94",
    usage: "Botão de perigo com o mouse em cima.",
  },
  "danger-fg": {
    light: BRAND.branco,
    dark: "#2B0B07",
    usage: "Texto sobre `danger`.",
  },
  "danger-text": {
    light: "#A8241B",
    dark: "#FF9C92",
    usage: "Erro de campo e item não conforme sobre qualquer superfície.",
  },
  success: {
    light: "#1F6E3A",
    dark: "#79C58C",
    usage: "Confirmação forte (botão que virou “Enviada”).",
  },
  "success-fg": {
    light: BRAND.branco,
    dark: "#0E2416",
    usage: "Texto sobre `success`.",
  },
  inverse: {
    light: BRAND.cacau,
    dark: BRAND.areia,
    usage: "Faixa invertida (aviso de conexão): o maior contraste possível no sol.",
  },
  "inverse-fg": {
    light: BRAND.creme,
    dark: BRAND.cacau,
    usage: "Texto sobre `inverse`.",
  },
  "notice-error-bg": {
    light: "#FBE4E1",
    dark: "#3E1A16",
    usage: "Aviso de erro (fundo).",
  },
  "notice-error-fg": {
    light: "#8E1F17",
    dark: "#FFB3AA",
    usage: "Aviso de erro (texto e ícone).",
  },
  "notice-success-bg": {
    light: "#DFEFE1",
    dark: "#163421",
    usage: "Aviso de sucesso (fundo).",
  },
  "notice-success-fg": {
    light: "#1B5B2E",
    dark: "#ABDDB6",
    usage: "Aviso de sucesso (texto e ícone).",
  },
  "notice-info-bg": {
    light: "#E1EBF5",
    dark: "#1B2D42",
    usage: "Aviso informativo (fundo).",
  },
  "notice-info-fg": {
    light: "#1C4A78",
    dark: "#BBD6F2",
    usage: "Aviso informativo (texto e ícone).",
  },
  "notice-warning-bg": {
    light: "#FBEDC4",
    dark: "#3B2D0C",
    usage: "Aviso de atenção (fundo).",
  },
  "notice-warning-fg": {
    light: "#664500",
    dark: "#F4D58E",
    usage: "Aviso de atenção (texto e ícone).",
  },
  selection: {
    light: "#F9D2B8",
    dark: "#5A2E14",
    usage: "Texto selecionado.",
  },
} as const satisfies Record<string, ThemeValue>;

export type ColorRole = keyof typeof COLORS;

/**
 * Status da tarefa (interface ↔ banco, PRODUCT.md §7). Ordem = ordem de exibição.
 * Sempre cor + ícone + texto; a cor nunca decide sozinha.
 */
export const STATUS_KEYS = [
  "pendente",
  "em-andamento",
  "aguardando-aprovacao",
  "aprovada",
  "correcao-solicitada",
  "atrasada",
  "cancelada",
] as const;
export type StatusKey = (typeof STATUS_KEYS)[number];

export type StatusShape = "outline" | "tint" | "strong" | "solid" | "dashed";

type StatusColors = { bg: string; fg: string; icon: string; border: string };

/**
 * Cores dos 7 status. Além do matiz e do ícone, a FORMA e a CLAREZA separam os grupos
 * (legível em escala de cinza e para daltonismo):
 * - `outline`  pendente: fundo quase igual ao da página, contorno contínuo (ainda não começou);
 * - `tint`     em andamento, aguardando aprovação, aprovada: fundo claro, matizes distintos;
 * - `strong`   correção solicitada: fundo de clareza média (pede ação de quem executa);
 * - `solid`    atrasada: fundo cheio e escuro no claro / claro no escuro (o que mais pede ação);
 * - `dashed`   cancelada: contorno tracejado e texto apagado (fora do fluxo).
 */
export const STATUS = {
  pendente: {
    label: "Pendente",
    db: "pending",
    shape: "outline",
    light: { bg: "#F7F0E8", fg: "#4A3A30", icon: BRAND["cacau-suave"], border: "#B9A797" },
    dark: { bg: "#2B2019", fg: "#EDE1D6", icon: "#C9B7A8", border: "#6E5D51" },
  },
  "em-andamento": {
    label: "Em andamento",
    db: "in_progress",
    shape: "tint",
    light: { bg: "#E1EBF5", fg: "#1C4A78", icon: "#2D5F96", border: "#E1EBF5" },
    dark: { bg: "#1B2D42", fg: "#BBD6F2", icon: "#8EB8E6", border: "#1B2D42" },
  },
  "aguardando-aprovacao": {
    label: "Aguardando aprovação",
    db: "submitted",
    shape: "tint",
    light: { bg: "#FBEDC4", fg: "#664500", icon: "#8A5D00", border: "#FBEDC4" },
    dark: { bg: "#3B2D0C", fg: "#F4D58E", icon: "#E3B851", border: "#3B2D0C" },
  },
  aprovada: {
    label: "Aprovada",
    db: "approved",
    shape: "tint",
    light: { bg: "#DFEFE1", fg: "#1B5B2E", icon: "#2A773F", border: "#DFEFE1" },
    dark: { bg: "#163421", fg: "#ABDDB6", icon: "#79C58C", border: "#163421" },
  },
  "correcao-solicitada": {
    label: "Correção solicitada",
    db: "rejected",
    shape: "strong",
    light: { bg: "#E6C3E0", fg: "#5A1F56", icon: "#7E3478", border: "#E6C3E0" },
    dark: { bg: "#5E2D59", fg: "#FBE3F7", icon: "#E8A9DF", border: "#5E2D59" },
  },
  atrasada: {
    label: "Atrasada",
    db: "overdue",
    shape: "solid",
    light: { bg: "#B3261E", fg: BRAND.branco, icon: BRAND.branco, border: "#B3261E" },
    dark: { bg: "#F2877D", fg: "#2B0B07", icon: "#2B0B07", border: "#F2877D" },
  },
  cancelada: {
    label: "Cancelada",
    db: "cancelled",
    shape: "dashed",
    light: { bg: "#F1ECE7", fg: "#5C514A", icon: "#7A6D64", border: "#A39486" },
    dark: { bg: "#2A221D", fg: "#BFB2A7", icon: "#A6988C", border: "#6E6158" },
  },
} as const satisfies Record<
  StatusKey,
  {
    label: string;
    db: string;
    shape: StatusShape;
    light: StatusColors;
    dark: StatusColors;
  }
>;

export type StatusPart = keyof StatusColors;
export type TokenRef = ColorRole | `status.${StatusKey}.${StatusPart}`;

/** Valor de um token num tema. */
export function resolveToken(ref: TokenRef, theme: ThemeName): string {
  if (ref.startsWith("status.")) {
    const [, key, part] = ref.split(".") as [string, StatusKey, StatusPart];
    return STATUS[key][theme][part];
  }
  return COLORS[ref as ColorRole][theme];
}

/** 4,5:1 para texto; 3:1 para texto grande, ícones, contornos de controle e anel de foco. */
export const AA_TEXT = 4.5;
export const AA_UI = 3;

export type ContrastPair = { fg: TokenRef; bg: TokenRef; min: number; usage: string };

const SURFACES = ["bg", "surface", "surface-muted", "surface-pressed"] as const;

function onSurfaces(
  fg: TokenRef,
  min: number,
  usage: string,
  surfaces: readonly ColorRole[] = SURFACES,
): ContrastPair[] {
  return surfaces.map((bg) => ({ fg, bg, min, usage }));
}

/**
 * Todo par texto/fundo (e ícone/contorno/fundo) que a interface usa. Par novo na interface =
 * linha nova aqui; o teste confere nos dois temas.
 */
export const CONTRAST_PAIRS: readonly ContrastPair[] = [
  ...onSurfaces("text", AA_TEXT, "Texto principal"),
  ...onSurfaces("text-muted", AA_TEXT, "Texto secundário"),
  ...onSurfaces("accent-text", AA_TEXT, "Link e número em laranja"),
  ...onSurfaces("danger-text", AA_TEXT, "Erro de campo, item não conforme"),
  { fg: "accent-fg", bg: "accent", min: AA_TEXT, usage: "Botão primário" },
  { fg: "accent-fg", bg: "accent-hover", min: AA_TEXT, usage: "Botão primário (hover)" },
  { fg: "danger-fg", bg: "danger", min: AA_TEXT, usage: "Botão de perigo" },
  { fg: "danger-fg", bg: "danger-hover", min: AA_TEXT, usage: "Botão de perigo (hover)" },
  { fg: "success-fg", bg: "success", min: AA_TEXT, usage: "Botão “Enviada”" },
  { fg: "inverse-fg", bg: "inverse", min: AA_TEXT, usage: "Faixa de conexão" },
  { fg: "text", bg: "selection", min: AA_TEXT, usage: "Texto selecionado" },
  { fg: "notice-error-fg", bg: "notice-error-bg", min: AA_TEXT, usage: "Aviso de erro" },
  { fg: "notice-success-fg", bg: "notice-success-bg", min: AA_TEXT, usage: "Aviso de sucesso" },
  { fg: "notice-info-fg", bg: "notice-info-bg", min: AA_TEXT, usage: "Aviso informativo" },
  { fg: "notice-warning-fg", bg: "notice-warning-bg", min: AA_TEXT, usage: "Aviso de atenção" },
  ...STATUS_KEYS.map((key): ContrastPair => ({
    fg: `status.${key}.fg`,
    bg: `status.${key}.bg`,
    min: AA_TEXT,
    usage: `Status “${STATUS[key].label}” (texto)`,
  })),
  ...STATUS_KEYS.map((key): ContrastPair => ({
    fg: `status.${key}.icon`,
    bg: `status.${key}.bg`,
    min: AA_UI,
    usage: `Status “${STATUS[key].label}” (ícone)`,
  })),
  ...onSurfaces("focus", AA_UI, "Anel de foco"),
  ...onSurfaces("border-control", AA_UI, "Contorno de campo e caixa de seleção", [
    "bg",
    "surface",
    "surface-muted",
  ]),
  ...onSurfaces("accent", AA_UI, "Caixa marcada, controle ativo", [
    "bg",
    "surface",
    "surface-muted",
  ]),
  ...onSurfaces("danger-text", AA_UI, "Caixa “não conforme”", ["surface"]),
  ...onSurfaces("brand", AA_UI, "Logo e marca grande", ["bg", "surface"]),
  { fg: "brand-fg", bg: "brand", min: AA_UI, usage: "Título grande (24px+) sobre laranja" },
];

/** Movimento (prompt, <motion>): curvas exatas e durações dentro das faixas. */
export const MOTION = {
  easing: {
    "ease-out": "cubic-bezier(0.23, 1, 0.32, 1)",
    "ease-in-out": "cubic-bezier(0.77, 0, 0.175, 1)",
    "ease-drawer": "cubic-bezier(0.32, 0.72, 0, 1)",
  },
  /** ms. `range` é a faixa do prompt; o teste confere que o valor cai dentro dela. */
  duration: {
    press: { ms: 160, range: [100, 160], usage: "Botão e item pressionado (scale 0.97)" },
    popover: { ms: 180, range: [125, 200], usage: "Tooltip e popover" },
    dropdown: { ms: 200, range: [150, 250], usage: "Menu e select" },
    modal: { ms: 240, range: [200, 300], usage: "Dialog (centralizado)" },
    drawer: { ms: 280, range: [200, 300], usage: "Gaveta de foto (a velocidade do gesto manda)" },
    check: { ms: 180, range: [100, 200], usage: "Check desenhado do checklist" },
    morph: { ms: 200, range: [150, 250], usage: "Botão Enviar → Enviada (blur ≤ 2px)" },
    layout: { ms: 220, range: [150, 300], usage: "Tarefa sai de Pendentes e entra em Aguardando" },
  },
} as const;

/** Raios do manual: raio-s, raio-m, raio-l e pílula. */
export const RADII = {
  s: { px: 6, brand: "raio-s", usage: "Selos pequenos, miniatura de foto, marcador de crítico" },
  m: { px: 12, brand: "raio-m", usage: "Botões, campos, cartões, avisos" },
  l: { px: 26, brand: "raio-l", usage: "Dialog e gaveta (superfícies que flutuam), ícone do app" },
} as const;

/** Espaços: múltiplos de 8 (manual), mais 4 e 12 onde a interface precisa. */
export const SPACING = [4, 8, 12, 16, 24, 32, 40, 48, 64] as const;

/** Sombras: só no que flutua (menu, popover, dialog). Nada em repouso tem sombra. */
export const SHADOWS = {
  float: {
    light: "0 8px 24px -8px rgb(42 24 16 / 0.22), 0 2px 6px -2px rgb(42 24 16 / 0.12)",
    dark: "0 8px 24px -8px rgb(0 0 0 / 0.6), 0 2px 6px -2px rgb(0 0 0 / 0.4)",
    usage: "Menu, popover",
  },
  dialog: {
    light: "0 24px 64px -16px rgb(42 24 16 / 0.32), 0 4px 12px -4px rgb(42 24 16 / 0.16)",
    dark: "0 24px 64px -16px rgb(0 0 0 / 0.7), 0 4px 12px -4px rgb(0 0 0 / 0.5)",
    usage: "Dialog e gaveta",
  },
} as const;

/** Fundo do dialog (scrim). Opacidade sobre cacau. */
export const SCRIM = { light: "rgb(42 24 16 / 0.45)", dark: "rgb(0 0 0 / 0.6)" } as const;

/**
 * Estilos de texto. `family`: display = Bitter (títulos curtos, números, preços), text = Figtree
 * (tudo que se lê). Viram utilitários `type-<nome>`.
 */
export const TYPE = {
  display: {
    family: "display",
    size: 44,
    line: 48,
    weight: 800,
    tracking: "-0.01em",
    tabular: false,
    brand: "display (44px)",
    usage: "Frase do painel das páginas públicas. Nunca no app",
  },
  kpi: {
    family: "display",
    size: 40,
    line: 44,
    weight: 900,
    tracking: "-0.02em",
    tabular: true,
    brand: "preco (adaptado)",
    usage: "Número grande de indicador",
  },
  counter: {
    family: "display",
    size: 28,
    line: 32,
    weight: 800,
    tracking: "-0.01em",
    tabular: true,
    brand: "titulo-2",
    usage: "Contadores do Hoje (Pendentes, Atrasadas)",
  },
  "title-1": {
    family: "display",
    size: 28,
    line: 34,
    weight: 800,
    tracking: "-0.01em",
    tabular: false,
    brand: "titulo-2",
    usage: "Título da página (até ~6 palavras)",
  },
  "title-2": {
    family: "display",
    size: 20,
    line: 26,
    weight: 800,
    tracking: "0",
    tabular: false,
    brand: "titulo-3",
    usage: "Nome de seção",
  },
  lead: {
    family: "text",
    size: 18,
    line: 26,
    weight: 600,
    tracking: "0",
    tabular: false,
    brand: "destaque (18px)",
    usage: "Título de tarefa, texto do item do checklist",
  },
  body: {
    family: "text",
    size: 16,
    line: 24,
    weight: 400,
    tracking: "0",
    tabular: false,
    brand: "corpo",
    usage: "Texto corrido (mínimo 16px)",
  },
  "body-strong": {
    family: "text",
    size: 16,
    line: 24,
    weight: 600,
    tracking: "0",
    tabular: false,
    brand: "destaque",
    usage: "Rótulo de campo, botão, ênfase",
  },
  meta: {
    family: "text",
    size: 14,
    line: 20,
    weight: 500,
    tracking: "0",
    tabular: false,
    brand: "legenda (14px)",
    usage: "Horário, setor, selo de status. Nunca parágrafo",
  },
} as const satisfies Record<
  string,
  {
    family: "display" | "text";
    size: number;
    line: number;
    weight: number;
    tracking: string;
    tabular: boolean;
    brand: string;
    usage: string;
  }
>;

/**
 * Pilhas de fonte. --font-bitter e --font-figtree vêm do next/font/local (src/app/fonts.ts) e já
 * trazem a métrica de fallback; os nomes do manual (Rockwell/Georgia, Arial) ficam no fim.
 */
export const FONT_STACKS = {
  display: "var(--font-bitter), Rockwell, Georgia, serif",
  text: "var(--font-figtree), Arial, sans-serif",
} as const;

/** Alvo de toque mínimo (px) e alturas de controle. */
export const TOUCH = { min: 44, control: 48, bar: 56 } as const;
