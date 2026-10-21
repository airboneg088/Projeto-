import type { Metadata } from "next";

import { AreaPlaceholder } from "@/components/area-placeholder";
import { requireArea } from "@/lib/auth/context";

export const metadata: Metadata = { title: "Gerência" };

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
