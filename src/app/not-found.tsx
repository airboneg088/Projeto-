import Link from "next/link";

export default function NotFound() {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-4 px-4 py-10">
      <h1 className="text-2xl font-semibold">Página não encontrada</h1>
      <p className="text-text-muted">O endereço pode estar errado ou a página mudou de lugar.</p>
      <Link href="/" className="btn btn-primary btn-block">
        Ir para o início
      </Link>
    </main>
  );
}
