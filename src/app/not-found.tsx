import Link from "next/link";

import { LogoHorizontal } from "@/components/brand/logo";
import { buttonVariants } from "@/components/ui/button";

export default function NotFound() {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-3 px-4 py-10">
      <LogoHorizontal className="mb-6" />
      <h1 className="type-title-1 text-text">Página não encontrada</h1>
      <p className="text-text-muted">O endereço pode estar errado ou a página mudou de lugar.</p>
      <Link href="/" className={buttonVariants({ block: true, className: "mt-3" })}>
        Ir para o início
      </Link>
    </main>
  );
}
