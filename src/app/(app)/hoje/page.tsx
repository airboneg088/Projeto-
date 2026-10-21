import type { Metadata } from "next";

import { AreaPlaceholder } from "@/components/area-placeholder";
import { requireArea } from "@/lib/auth/context";

export const metadata: Metadata = { title: "Hoje" };

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
