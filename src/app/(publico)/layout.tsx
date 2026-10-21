import { HousePattern } from "@/components/brand/house-pattern";
import { LogoHorizontal, LogoPrincipal } from "@/components/brand/logo";

/**
 * Páginas públicas (login e senha), modo Read: a marca aparece inteira aqui.
 * - Celular: faixa laranja com o logo horizontal branco e o formulário logo abaixo.
 * - Computador: painel laranja à esquerda (logo principal, padrão de casas na faixa do meio,
 *   frase em Bitter de 40px+ — branco sobre laranja só em texto grande) e o formulário à direita.
 */
export default function PublicLayout({ children }: LayoutProps<"/">) {
  return (
    <div className="min-h-dvh lg:grid lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
      <aside className="bg-brand text-brand-fg lg:sticky lg:top-0 lg:flex lg:h-dvh lg:flex-col">
        <div className="px-4 pt-[max(env(safe-area-inset-top),1.25rem)] pb-5 lg:hidden">
          <LogoHorizontal tone="branco" width={168} priority />
        </div>
        <div className="hidden px-14 pt-14 lg:block">
          <LogoPrincipal tone="branco" width={200} />
        </div>
        <HousePattern className="hidden min-h-0 flex-1 lg:my-12 lg:block" />
        <div className="hidden px-14 pb-14 lg:block">
          <p className="max-w-md type-display">As tarefas das três lojas, num lugar só.</p>
          <p className="mt-5 text-xl font-bold">Primavera · Castro Alves · Parque América</p>
        </div>
      </aside>

      <main className="flex flex-col items-center px-4 py-8 lg:justify-center lg:px-16 lg:py-16">
        <div className="w-full max-w-sm">
          <div className="rounded-m bg-surface p-6 sm:p-8">{children}</div>
          <p className="mt-6 text-center text-text-muted">
            Não consegue entrar? Fale com a gerência da sua loja.
          </p>
        </div>
      </main>
    </div>
  );
}
