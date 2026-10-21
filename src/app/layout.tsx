import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";

import { Providers } from "@/components/providers";
import { COLORS } from "@/lib/design/tokens";

import { bitter, figtree } from "./fonts";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Éde Gestão",
    template: "%s · Éde Gestão",
  },
  description: "Controle das tarefas operacionais das lojas Éde Utilidades.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  // Deixa a página ir até as bordas do aparelho; a barra de ação inferior usa
  // env(safe-area-inset-bottom) para não ficar sob a barra de gestos.
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: COLORS.bg.light },
    { media: "(prefers-color-scheme: dark)", color: COLORS.bg.dark },
  ],
};

export default async function RootLayout({ children }: LayoutProps<"/">) {
  // Nonce da CSP gerado no proxy (src/proxy.ts). Ler os headers também deixa todas as páginas
  // dinâmicas, requisito para o nonce valer em cada resposta.
  const nonce = (await headers()).get("x-nonce") ?? undefined;

  return (
    <html
      lang="pt-BR"
      className={`${bitter.variable} ${figtree.variable} h-full`}
      suppressHydrationWarning
    >
      <body className="min-h-full">
        <Providers nonce={nonce}>{children}</Providers>
      </body>
    </html>
  );
}
