import { AppShell } from "@/components/app-shell";
import { requireArea } from "@/lib/auth/context";

export default async function PainelLayout({ children }: LayoutProps<"/painel">) {
  const ctx = await requireArea("painel");
  return (
    <AppShell ctx={ctx} current="painel">
      {children}
    </AppShell>
  );
}
