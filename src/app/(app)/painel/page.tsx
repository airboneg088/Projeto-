import type { Metadata } from "next";

import { AreaPlaceholder } from "@/components/area-placeholder";
import { requireArea } from "@/lib/auth/context";

export const metadata: Metadata = { title: "Painel" };

export default async function PainelPage() {
  // Repete a checagem do layout: layout e página renderizam em paralelo.
  await requireArea("painel");
  return (
    <AreaPlaceholder
      title="Painel"
      phase="Fase 5"
      description="Indicadores das 3 lojas, com filtros e detalhe até a tarefa e a foto."
    />
  );
}
