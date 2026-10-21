import type { Metadata } from "next";

import { AreaPlaceholder } from "@/components/area-placeholder";
import { areaMetadata, requireArea } from "@/lib/auth/context";

export function generateMetadata(): Promise<Metadata> {
  return areaMetadata("hoje");
}

export default async function HojePage() {
  // Repete a checagem do layout: layout e página renderizam em paralelo.
  await requireArea("hoje");
  return (
    <AreaPlaceholder
      title="Hoje"
      phase="Fase 3"
      description="Suas tarefas do dia, com checklist, foto e envio mesmo sem internet."
    />
  );
}
