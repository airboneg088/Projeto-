"use client";

import { useTheme } from "next-themes";
import { useSyncExternalStore } from "react";

import { IconMoon, IconSun } from "@/components/icons";
import { Button } from "@/components/ui/button";

const subscribe = () => () => {};

/**
 * Alterna entre tema claro (padrão) e escuro. Botão de ícone de 44px com nome acessível fixo
 * ("Tema escuro") e aria-pressed; antes de hidratar não declara estado.
 */
export function ThemeToggle({ className }: { className?: string }) {
  const { resolvedTheme, setTheme } = useTheme();
  const hydrated = useSyncExternalStore(
    subscribe,
    () => true,
    () => false,
  );
  const isDark = hydrated && resolvedTheme === "dark";

  return (
    <Button
      variant="ghost"
      size="icon"
      className={className}
      onClick={() => setTheme(isDark ? "light" : "dark")}
      aria-pressed={hydrated ? isDark : undefined}
      aria-label="Tema escuro"
      title={isDark ? "Voltar ao tema claro" : "Usar tema escuro"}
    >
      {isDark ? <IconSun size={22} /> : <IconMoon size={22} />}
    </Button>
  );
}
