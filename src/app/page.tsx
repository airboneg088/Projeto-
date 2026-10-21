import { redirectToHome } from "@/lib/auth/context";

/** "/" não tem conteúdo: leva ao login ou à página inicial do papel principal. */
export default async function Home() {
  await redirectToHome();
}
