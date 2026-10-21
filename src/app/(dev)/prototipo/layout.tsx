import { assertPrototypesEnabled } from "@/lib/dev/prototypes";

/**
 * Protótipos e catálogo de componentes: só com ENABLE_PROTOTYPES=1 (D116). Sem a variável,
 * todo /prototipo/* responde 404 (conferido no layout e em cada página).
 */
export default function PrototipoLayout({ children }: LayoutProps<"/prototipo">) {
  assertPrototypesEnabled();
  return children;
}
