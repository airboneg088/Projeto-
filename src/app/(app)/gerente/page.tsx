import type { Metadata } from "next";

import { AreaPlaceholder } from "@/components/area-placeholder";
import { areaMetadata, requireArea } from "@/lib/auth/context";

export function generateMetadata(): Promise<Metadata> {
  return areaMetadata("gerente");
}

export default async function GerentePage() {
  // Repete a checagem do layout: layout e página renderizam em paralelo.
  await requireArea("gerente");
  return (
    <AreaPlaceholder
      title="Gerência"
      phase="Fase 4"
      description="Fila de aprovação, tarefas avulsas, rotinas, agendamentos e equipe da loja."
    />
  );
}
