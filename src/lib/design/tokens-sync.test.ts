import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { renderTokensCss, replaceDesignTables } from "./render";

/**
 * tokens.ts é a fonte única. Este teste confere que src/app/tokens.css e o bloco de tabelas do
 * DESIGN.md foram gerados da versão atual. `pnpm tokens` (TOKENS_WRITE=1) regrava os dois.
 */
const CSS_PATH = fileURLToPath(new URL("../../app/tokens.css", import.meta.url));
const DESIGN_PATH = fileURLToPath(new URL("../../../DESIGN.md", import.meta.url));
const WRITE = process.env.TOKENS_WRITE === "1";

describe("arquivos gerados a partir de tokens.ts", () => {
  it("src/app/tokens.css está em dia", () => {
    const expected = renderTokensCss();
    if (WRITE) writeFileSync(CSS_PATH, expected);
    expect(readFileSync(CSS_PATH, "utf8"), "rode `pnpm tokens`").toBe(expected);
  });

  it("tabelas do DESIGN.md estão em dia", () => {
    const current = readFileSync(DESIGN_PATH, "utf8");
    const expected = replaceDesignTables(current);
    if (WRITE) writeFileSync(DESIGN_PATH, expected);
    expect(readFileSync(DESIGN_PATH, "utf8"), "rode `pnpm tokens`").toBe(expected);
  });
});
