"use client";

import { Button } from "@/components/ui/button";

export default function ErrorPage({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-4 px-4 py-10">
      <h1 className="text-2xl font-semibold">Algo deu errado</h1>
      <p className="text-text-muted">
        Não conseguimos carregar esta tela. Confira a internet e tente de novo.
      </p>
      <Button block onClick={() => reset()}>
        Tentar de novo
      </Button>
    </main>
  );
}
