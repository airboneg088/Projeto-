/** Páginas públicas (login e senha): coluna única centralizada, legível em 390px e 1440px. */
export default function PublicLayout({ children }: LayoutProps<"/">) {
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center px-4 py-10">
      <div className="w-full max-w-sm">
        <p className="mb-8 text-center text-xl font-semibold">Éde Gestão</p>
        <div className="rounded-lg bg-surface-1 p-6 sm:p-8">{children}</div>
      </div>
    </main>
  );
}
