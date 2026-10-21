import type { Metadata } from "next";

import { AreaPlaceholder } from "@/components/area-placeholder";
import { IconApproved } from "@/components/icons";
import { areaMetadata, requireArea } from "@/lib/auth/context";

export function generateMetadata(): Promise<Metadata> {
  return areaMetadata("gerente");
}

export default async function GerentePage() {
  // Repete a checagem do layout: layout e página renderizam em paralelo.
  const ctx = await requireArea("gerente");
  return (
    <AreaPlaceholder
      title="Gerência"
      subtitle={ctx.networkWide ? "Todas as lojas" : ctx.stores.map((s) => s.name).join(", ")}
      icon={IconApproved}
      phase="Fase 4"
      description="Fila de aprovação, tarefas avulsas, rotinas, agendamentos e equipe da loja."
    />
  );
}
