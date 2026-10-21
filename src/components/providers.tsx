"use client";

import { CSPProvider } from "@base-ui/react/csp-provider";
import { ThemeProvider, useTheme } from "next-themes";
import type { ReactNode } from "react";
import { Toaster } from "sonner";

function ThemedToaster() {
  const { resolvedTheme } = useTheme();
  return (
    <Toaster
      theme={resolvedTheme === "dark" ? "dark" : "light"}
      position="top-center"
      closeButton
      toastOptions={{ duration: 5000 }}
    />
  );
}

/**
 * Provedores do lado do cliente: tema (claro por padrão, classe "dark" aplicada antes da
 * primeira pintura), nonce da CSP para os componentes do base-ui e o Toaster do Sonner.
 */
export function Providers({ nonce, children }: { nonce?: string; children: ReactNode }) {
  return (
    <ThemeProvider
      attribute="class"
      defaultTheme="light"
      enableSystem
      disableTransitionOnChange
      nonce={nonce}
    >
      <CSPProvider nonce={nonce}>
        {children}
        <ThemedToaster />
      </CSPProvider>
    </ThemeProvider>
  );
}
