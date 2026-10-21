import type { Metadata } from "next";

import { AreaPlaceholder } from "@/components/area-placeholder";
import { requireArea } from "@/lib/auth/context";

export const metadata: Metadata = { title: "Administração" };

export default async function AdminPage() {
  // Repete a checagem do layout: layout e página renderizam em paralelo.
  await requireArea("admin");
  return (
    <AreaPlaceholder
      title="Administração"
      phase="Fase 7"
      description="Lojas, setores, usuários, vínculos, retenção de fotos e privacidade (LGPD)."
    />
  );
}
