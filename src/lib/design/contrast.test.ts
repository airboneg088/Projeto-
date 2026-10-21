import { describe, expect, it } from "vitest";

import { contrastRatio, formatRatio, lightness } from "./contrast";
import {
  AA_TEXT,
  AA_UI,
  BRAND,
  COLORS,
  CONTRAST_PAIRS,
  MOTION,
  STATUS,
  STATUS_KEYS,
  THEMES,
  resolveToken,
} from "./tokens";

describe("cálculo de contraste (WCAG 2.x)", () => {
  it("bate com os valores de referência", () => {
    expect(contrastRatio("#000000", "#FFFFFF")).toBeCloseTo(21, 5);
    expect(contrastRatio("#FFFFFF", "#FFFFFF")).toBeCloseTo(1, 5);
    // Valores publicados no manual da marca.
    expect(formatRatio(contrastRatio(BRAND.cacau, BRAND.creme))).toBe("15.65");
    expect(formatRatio(contrastRatio(BRAND.branco, BRAND["laranja-brasa"]))).toBe("5.00");
    expect(formatRatio(contrastRatio(BRAND["laranja-brasa"], BRAND.areia))).toBe("4.07");
  });

  it("recusa cor fora do formato #RRGGBB", () => {
    expect(() => contrastRatio("red", "#FFFFFF")).toThrow(/Cor inválida/);
  });
});

describe.each(THEMES)("tema %s: todos os pares declarados passam AA", (theme) => {
  it.each(
    CONTRAST_PAIRS.map((pair) => [`${pair.usage}: ${pair.fg} sobre ${pair.bg}`, pair] as const),
  )("%s", (_name, pair) => {
    const ratio = contrastRatio(resolveToken(pair.fg, theme), resolveToken(pair.bg, theme));
    expect(ratio, `${formatRatio(ratio)}:1 < ${pair.min}:1`).toBeGreaterThanOrEqual(pair.min);
  });
});

describe("cobertura dos pares", () => {
  const declared = new Set(CONTRAST_PAIRS.map((pair) => `${pair.fg}|${pair.bg}`));

  it.each(STATUS_KEYS)("status %s tem texto (4,5:1) e ícone (3:1) conferidos", (key) => {
    expect(declared.has(`status.${key}.fg|status.${key}.bg`)).toBe(true);
    expect(declared.has(`status.${key}.icon|status.${key}.bg`)).toBe(true);
    const text = CONTRAST_PAIRS.find((p) => p.fg === `status.${key}.fg`);
    expect(text?.min).toBe(AA_TEXT);
  });

  it("botões (primário, perigo, “Enviada”) e foco estão na lista", () => {
    for (const pair of [
      "accent-fg|accent",
      "accent-fg|accent-hover",
      "danger-fg|danger",
      "danger-fg|danger-hover",
      "success-fg|success",
      "focus|bg",
      "focus|surface",
      "border-control|surface",
    ]) {
      expect(declared.has(pair), pair).toBe(true);
    }
  });

  it("todo texto da interface é conferido em todas as superfícies", () => {
    for (const fg of ["text", "text-muted", "accent-text", "danger-text"]) {
      for (const bg of ["bg", "surface", "surface-muted", "surface-pressed"]) {
        const pair = CONTRAST_PAIRS.find((p) => p.fg === fg && p.bg === bg);
        expect(pair?.min, `${fg} sobre ${bg}`).toBe(AA_TEXT);
      }
    }
  });

  it("todo valor é #RRGGBB", () => {
    for (const [role, value] of Object.entries(COLORS)) {
      for (const theme of THEMES) expect(value[theme], role).toMatch(/^#[0-9A-F]{6}$/i);
    }
    for (const key of STATUS_KEYS) {
      for (const theme of THEMES) {
        for (const color of Object.values(STATUS[key][theme]))
          expect(color).toMatch(/^#[0-9A-F]{6}$/i);
      }
    }
  });
});

describe("status não dependem só do matiz", () => {
  it.each(THEMES)("tema %s: “atrasada” se destaca de todos pela clareza (ΔL* ≥ 30)", (theme) => {
    const late = lightness(STATUS.atrasada[theme].bg);
    for (const key of STATUS_KEYS.filter((k) => k !== "atrasada")) {
      expect(Math.abs(late - lightness(STATUS[key][theme].bg)), key).toBeGreaterThanOrEqual(30);
    }
  });

  it.each(THEMES)(
    "tema %s: “correção solicitada” se separa dos fundos claros (ΔL* ≥ 7)",
    (theme) => {
      const fix = lightness(STATUS["correcao-solicitada"][theme].bg);
      for (const key of [
        "pendente",
        "em-andamento",
        "aguardando-aprovacao",
        "aprovada",
        "cancelada",
      ] as const) {
        expect(Math.abs(fix - lightness(STATUS[key][theme].bg)), key).toBeGreaterThanOrEqual(7);
      }
    },
  );

  it("pendente e cancelada têm contorno visível (forma), e as formas são as documentadas", () => {
    expect(STATUS.pendente.shape).toBe("outline");
    expect(STATUS.cancelada.shape).toBe("dashed");
    for (const theme of THEMES) {
      expect(
        contrastRatio(STATUS.pendente[theme].border, STATUS.pendente[theme].bg),
      ).toBeGreaterThan(1.5);
      expect(
        contrastRatio(STATUS.cancelada[theme].border, STATUS.cancelada[theme].bg),
      ).toBeGreaterThan(1.5);
    }
  });

  it("cada status tem rótulo e valor do banco únicos", () => {
    const labels = STATUS_KEYS.map((k) => STATUS[k].label);
    const db = STATUS_KEYS.map((k) => STATUS[k].db);
    expect(new Set(labels).size).toBe(STATUS_KEYS.length);
    expect(new Set(db).size).toBe(STATUS_KEYS.length);
    expect(db.sort()).toEqual(
      [
        "approved",
        "cancelled",
        "in_progress",
        "overdue",
        "pending",
        "rejected",
        "submitted",
      ].sort(),
    );
  });
});

describe("movimento", () => {
  it("curvas exatas do prompt", () => {
    expect(MOTION.easing).toEqual({
      "ease-out": "cubic-bezier(0.23, 1, 0.32, 1)",
      "ease-in-out": "cubic-bezier(0.77, 0, 0.175, 1)",
      "ease-drawer": "cubic-bezier(0.32, 0.72, 0, 1)",
    });
  });

  it.each(Object.entries(MOTION.duration))("%s dentro da faixa e abaixo de 300ms", (_name, d) => {
    expect(d.ms).toBeGreaterThanOrEqual(d.range[0]);
    expect(d.ms).toBeLessThanOrEqual(d.range[1]);
    expect(d.ms).toBeLessThanOrEqual(300);
  });

  it("check desenhado ≤ 200ms; press entre 100 e 160ms", () => {
    expect(MOTION.duration.check.ms).toBeLessThanOrEqual(200);
    expect(MOTION.duration.press.ms).toBeGreaterThanOrEqual(100);
    expect(MOTION.duration.press.ms).toBeLessThanOrEqual(160);
  });
});

describe("limites dos números", () => {
  it("AA_UI e AA_TEXT são os da WCAG", () => {
    expect(AA_TEXT).toBe(4.5);
    expect(AA_UI).toBe(3);
  });
});
