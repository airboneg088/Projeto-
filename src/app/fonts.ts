import localFont from "next/font/local";

/**
 * Fontes do manual da marca, servidas pelo próprio app (next/font/local → /_next/static/media,
 * mesma origem: a CSP `font-src 'self'` basta e nada vai ao Google Fonts).
 *
 * As variáveis --font-bitter e --font-figtree alimentam os tokens --font-display e --font-text
 * (src/app/tokens.css). Nomes diferentes evitam variável que referencia a si mesma.
 */

/** Bitter 800/900: títulos curtos, números e preços. Fallback do manual: Rockwell, Georgia. */
export const bitter = localFont({
  src: [
    { path: "./fonts/bitter-latin-800-normal.woff2", weight: "800", style: "normal" },
    { path: "./fonts/bitter-latin-900-normal.woff2", weight: "900", style: "normal" },
  ],
  variable: "--font-bitter",
  display: "swap",
  fallback: ["Rockwell", "Georgia", "serif"],
  adjustFontFallback: "Times New Roman",
});

/** Figtree 400–800: tudo que se lê. Fallback do manual: Arial. */
export const figtree = localFont({
  src: [
    { path: "./fonts/figtree-latin-400-normal.woff2", weight: "400", style: "normal" },
    { path: "./fonts/figtree-latin-500-normal.woff2", weight: "500", style: "normal" },
    { path: "./fonts/figtree-latin-600-normal.woff2", weight: "600", style: "normal" },
    { path: "./fonts/figtree-latin-700-normal.woff2", weight: "700", style: "normal" },
    { path: "./fonts/figtree-latin-800-normal.woff2", weight: "800", style: "normal" },
  ],
  variable: "--font-figtree",
  display: "swap",
  fallback: ["Arial", "sans-serif"],
  adjustFontFallback: "Arial",
});
