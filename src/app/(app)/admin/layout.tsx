import { AppShell } from "@/components/app-shell";
import { requireArea } from "@/lib/auth/context";

export default async function AdminLayout({ children }: LayoutProps<"/admin">) {
  const ctx = await requireArea("admin");
  return (
    <AppShell ctx={ctx} current="admin">
      {children}
    </AppShell>
  );
}
