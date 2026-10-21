import type { Metadata } from "next";

import { RecuperarForm } from "./recuperar-form";

export const metadata: Metadata = { title: "Recuperar senha" };

export default function RecuperarSenhaPage() {
  return (
    <>
      <h1 className="type-title-1 text-text">Recuperar senha</h1>
      <p className="mt-1.5 mb-6 text-text-muted">
        Informe o e-mail da sua conta. Vamos enviar um link para você criar uma nova senha.
      </p>
      <RecuperarForm />
    </>
  );
}
