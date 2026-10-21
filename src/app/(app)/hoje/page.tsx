import type { Metadata } from "next";

import { AreaPlaceholder } from "@/components/area-placeholder";
import { IconListChecks } from "@/components/icons";
import { areaMetadata, requireArea } from "@/lib/auth/context";
import { formatLongDate } from "@/lib/format";

export function generateMetadata(): Promise<Metadata> {
  return areaMetadata("hoje");
}

export default async function HojePage() {
  // Repete a checagem do layout: layout e página renderizam em paralelo.
  const ctx = await requireArea("hoje");
  const store = ctx.stores.map((s) => s.name).join(", ");
  return (
    <AreaPlaceholder
      title="Hoje"
      subtitle={[formatLongDate(new Date()), store].filter(Boolean).join(" · ")}
      icon={IconListChecks}
      phase="Fase 3"
      description="Suas tarefas do dia, com checklist, foto e envio mesmo sem internet."
    />
  );
}
