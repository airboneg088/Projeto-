/**
 * Gera o CSS dos tokens (src/app/tokens.css) e as tabelas do DESIGN.md a partir de tokens.ts.
 * Rodado por `pnpm tokens`; tokens-sync.test.ts confere que os arquivos estão em dia.
 */
import { contrastRatio, formatRatio, lightness } from "./contrast";
import {
  COLORS,
  CONTRAST_PAIRS,
  FONT_STACKS,
  type ColorRole,
  MOTION,
  RADII,
  SCRIM,
  SHADOWS,
  SPACING,
  STATUS,
  STATUS_KEYS,
  type StatusPart,
  TOUCH,
  TYPE,
  type ThemeName,
  resolveToken,
} from "./tokens";

const COLOR_ROLES = Object.keys(COLORS) as ColorRole[];
const STATUS_PARTS: readonly StatusPart[] = ["bg", "fg", "icon", "border"];

const rem = (px: number) => `${px / 16}rem`;

function themeVariables(theme: ThemeName): string[] {
  const lines: string[] = [];
  for (const role of COLOR_ROLES) lines.push(`  --${role}: ${COLORS[role][theme]};`);
  for (const key of STATUS_KEYS) {
    for (const part of STATUS_PARTS)
      lines.push(`  --status-${key}-${part}: ${STATUS[key][theme][part]};`);
  }
  for (const [name, shadow] of Object.entries(SHADOWS))
    lines.push(`  --elevation-${name}: ${shadow[theme]};`);
  lines.push(`  --scrim: ${SCRIM[theme]};`);
  return lines;
}

export function renderTokensCss(): string {
  const out: string[] = [];
  out.push(
    "/*",
    " * GERADO por `pnpm tokens` a partir de src/lib/design/tokens.ts. Não edite à mão:",
    " * mude tokens.ts e rode `pnpm tokens` (o teste tokens-sync.test.ts falha se divergir).",
    " *",
    " * Tema claro no :root (padrão) e em .light; tema escuro em .dark (classe do next-themes).",
    " * As classes também valem em qualquer elemento: o catálogo mostra os dois temas lado a lado.",
    " */",
    "",
    ":root,",
    ".light {",
    "  color-scheme: light;",
    ...themeVariables("light"),
    "}",
    "",
    ".dark {",
    "  color-scheme: dark;",
    ...themeVariables("dark"),
    "}",
    "",
    "/* Movimento: iguais nos dois temas. */",
    ":root {",
  );
  for (const [name, value] of Object.entries(MOTION.easing)) out.push(`  --${name}: ${value};`);
  for (const [name, d] of Object.entries(MOTION.duration))
    out.push(`  --duration-${name}: ${d.ms}ms;`);
  out.push(
    `  --touch-min: ${TOUCH.min}px;`,
    `  --control-height: ${TOUCH.control}px;`,
    `  --bar-height: ${TOUCH.bar}px;`,
  );
  out.push("}", "");

  out.push(
    "/*",
    " * Vocabulário do Tailwind restrito aos tokens: sem a paleta padrão (cores fora da marca),",
    " * sem sombras de repouso, sem ease-in, sem raios fora do manual e sem texto de 12px.",
    " */",
    "@theme {",
    "  --color-*: initial;",
    "  --shadow-*: initial;",
    "  --inset-shadow-*: initial;",
    "  --drop-shadow-*: initial;",
    "  --text-shadow-*: initial;",
    "  --radius-*: initial;",
    "  --ease-*: initial;",
    "  --text-xs: initial;",
    "  --color-transparent: transparent;",
    "  --color-current: currentColor;",
  );
  for (const [name, radius] of Object.entries(RADII))
    out.push(`  --radius-${name}: ${radius.px}px;`);
  for (const [name, value] of Object.entries(MOTION.easing)) out.push(`  --${name}: ${value};`);
  out.push("}", "");

  out.push(
    "/* Utilitários que mudam com o tema (bg-surface, text-text-muted, border-border…). */",
    "@theme inline {",
  );
  out.push(`  --font-display: ${FONT_STACKS.display};`);
  out.push(`  --font-text: ${FONT_STACKS.text};`);
  for (const role of COLOR_ROLES) out.push(`  --color-${role}: var(--${role});`);
  for (const key of STATUS_KEYS) {
    for (const part of STATUS_PARTS)
      out.push(`  --color-status-${key}-${part}: var(--status-${key}-${part});`);
  }
  for (const name of Object.keys(SHADOWS))
    out.push(`  --shadow-${name}: var(--elevation-${name});`);
  out.push("}", "");

  out.push("/* Estilos de texto (DESIGN.md › Tipografia): type-<nome>. */");
  for (const [name, style] of Object.entries(TYPE)) {
    out.push(`@utility type-${name} {`);
    out.push(`  font-family: ${FONT_STACKS[style.family]};`);
    out.push(`  font-size: ${rem(style.size)};`);
    out.push(`  line-height: ${rem(style.line)};`);
    out.push(`  font-weight: ${style.weight};`);
    if (style.tracking !== "0") out.push(`  letter-spacing: ${style.tracking};`);
    if (style.tabular) out.push("  font-variant-numeric: tabular-nums;");
    out.push("}", "");
  }
  return `${out.join("\n").trimEnd()}\n`;
}

const code = (value: string) => `\`${value}\``;

function table(header: string[], rows: string[][]): string {
  const lines = [`| ${header.join(" | ")} |`, `| ${header.map(() => "---").join(" | ")} |`];
  for (const row of rows) lines.push(`| ${row.join(" | ")} |`);
  return lines.join("\n");
}

export const DESIGN_MARK_START =
  "<!-- tokens:inicio (gerado por `pnpm tokens` a partir de src/lib/design/tokens.ts; não edite este bloco) -->";
export const DESIGN_MARK_END = "<!-- tokens:fim -->";

/** Bloco de tabelas do DESIGN.md (entre os marcadores). */
export function renderDesignTables(): string {
  const parts: string[] = [];

  parts.push(
    "### Cores da interface",
    "",
    "Cada papel vira `--<papel>` (CSS) e `bg-<papel>` / `text-<papel>` / `border-<papel>` (Tailwind).",
    "",
    table(
      ["Papel", "Claro", "Escuro", "Uso"],
      COLOR_ROLES.map((role) => [
        code(role),
        code(COLORS[role].light),
        code(COLORS[role].dark),
        COLORS[role].usage,
      ]),
    ),
    "",
    "### Status da tarefa",
    "",
    "Sempre cor + ícone + texto. L* = clareza do fundo (0 a 100): atrasada e correção solicitada se",
    "separam das demais pela clareza, não só pelo matiz; pendente e cancelada, pelo contorno.",
    "",
    table(
      [
        "Status",
        "Banco",
        "Forma",
        "Claro (fundo · texto · ícone)",
        "Escuro (fundo · texto · ícone)",
        "L* claro / escuro",
      ],
      STATUS_KEYS.map((key) => {
        const s = STATUS[key];
        return [
          s.label,
          code(s.db),
          code(s.shape),
          `${code(s.light.bg)} · ${code(s.light.fg)} · ${code(s.light.icon)}`,
          `${code(s.dark.bg)} · ${code(s.dark.fg)} · ${code(s.dark.icon)}`,
          `${lightness(s.light.bg).toFixed(0)} / ${lightness(s.dark.bg).toFixed(0)}`,
        ];
      }),
    ),
    "",
    "### Contraste conferido (WCAG AA)",
    "",
    "Calculado de `tokens.ts` pelo `contrast.test.ts` (4,5:1 texto; 3:1 ícone, contorno de controle, foco e marca).",
    "",
    table(
      ["Uso", "Texto/elemento sobre fundo", "Mínimo", "Claro", "Escuro"],
      CONTRAST_PAIRS.map((pair) => [
        pair.usage,
        `${code(pair.fg)} sobre ${code(pair.bg)}`,
        `${pair.min}:1`,
        `${formatRatio(contrastRatio(resolveToken(pair.fg, "light"), resolveToken(pair.bg, "light")))}:1`,
        `${formatRatio(contrastRatio(resolveToken(pair.fg, "dark"), resolveToken(pair.bg, "dark")))}:1`,
      ]),
    ),
    "",
    "### Tipografia",
    "",
    table(
      ["Utilitário", "Fonte", "Tamanho / linha", "Peso", "Números", "Estilo da marca", "Uso"],
      Object.entries(TYPE).map(([name, style]) => [
        code(`type-${name}`),
        style.family === "display" ? "Bitter" : "Figtree",
        `${style.size} / ${style.line}px`,
        String(style.weight),
        style.tabular ? "tabulares" : "—",
        style.brand,
        style.usage,
      ]),
    ),
    "",
    "### Movimento",
    "",
    table(
      ["Token", "Valor", "Faixa do prompt", "Uso"],
      [
        ...Object.entries(MOTION.easing).map(([name, value]) => [
          code(`--${name}`),
          code(value),
          "exata",
          "Curva",
        ]),
        ...Object.entries(MOTION.duration).map(([name, d]) => [
          code(`--duration-${name}`),
          `${d.ms}ms`,
          `${d.range[0]}–${d.range[1]}ms`,
          d.usage,
        ]),
      ],
    ),
    "",
    "### Raios, espaços, sombras e alvos",
    "",
    table(
      ["Token", "Valor", "Uso"],
      [
        ...Object.entries(RADII).map(([name, r]) => [
          code(`rounded-${name}`),
          `${r.px}px (${r.brand})`,
          r.usage,
        ]),
        [code("rounded-full"), "999px (raio-pilula)", "Selo de status, contador"],
        [
          code("espaços"),
          SPACING.map((s) => `${s}`).join(" · ") + " px",
          "Tailwind `1`=4px: use 1, 2, 3, 4, 6, 8, 10, 12, 16",
        ],
        ...Object.entries(SHADOWS).map(([name, s]) => [code(`shadow-${name}`), "—", s.usage]),
        [code("--touch-min"), `${TOUCH.min}px`, "Alvo de toque mínimo"],
        [code("--control-height"), `${TOUCH.control}px`, "Altura de botão e campo"],
        [code("--bar-height"), `${TOUCH.bar}px`, "Botão da barra inferior de ação"],
      ],
    ),
  );

  return `${DESIGN_MARK_START}\n\n${parts.join("\n")}\n\n${DESIGN_MARK_END}`;
}

/** Troca o bloco gerado dentro do DESIGN.md (entre os marcadores). */
export function replaceDesignTables(markdown: string): string {
  const start = markdown.indexOf(DESIGN_MARK_START);
  const end = markdown.indexOf(DESIGN_MARK_END);
  if (start < 0 || end < start) throw new Error("DESIGN.md sem os marcadores do bloco de tokens.");
  return `${markdown.slice(0, start)}${renderDesignTables()}${markdown.slice(end + DESIGN_MARK_END.length)}`;
}
