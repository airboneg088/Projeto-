import type { Metadata } from "next";

import { AreaPlaceholder } from "@/components/area-placeholder";
import { IconStore } from "@/components/icons";
import { areaMetadata, requireArea } from "@/lib/auth/context";

export function generateMetadata(): Promise<Metadata> {
  return areaMetadata("painel");
}

export default async function PainelPage() {
  // Repete a checagem do layout: layout e página renderizam em paralelo.
  await requireArea("painel");
  return (
    <AreaPlaceholder
      title="Painel"
      subtitle="Primavera, Castro Alves e Parque América"
      icon={IconStore}
      phase="Fase 5"
      description="Indicadores das 3 lojas, com filtros e detalhe até a tarefa e a foto."
    />
  );
}
