import { AppShell } from "@/components/app-shell";
import { requireArea } from "@/lib/auth/context";

export default async function GerenteLayout({ children }: LayoutProps<"/gerente">) {
  const ctx = await requireArea("gerente");
  return (
    <AppShell ctx={ctx} current="gerente">
      {children}
    </AppShell>
  );
}
