import { AppShell } from "@/components/app-shell";
import { requireArea } from "@/lib/auth/context";

export default async function HojeLayout({ children }: LayoutProps<"/hoje">) {
  const ctx = await requireArea("hoje");
  return (
    <AppShell ctx={ctx} current="hoje">
      {children}
    </AppShell>
  );
}
