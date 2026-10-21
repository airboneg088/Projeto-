import "server-only";

import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

import { type StorageBucket, type SignedUrlDeps, createSignedReadUrl } from "./signed-url";

const READ_CHECK = {
  evidences: "can_read_evidence",
  references: "can_read_reference",
} as const satisfies Record<StorageBucket, string>;

/**
 * URL assinada (até 5 min) para o usuário logado ler um arquivo do storage, ou `null` se ele não
 * pode (D77). A conferência roda como o usuário (RLS e vínculo vigente); a assinatura, com a chave
 * secreta, só depois dela. Use em Server Components, Server Actions e Route Handlers.
 */
export async function signedReadUrl(
  bucket: StorageBucket,
  path: string,
  expiresIn?: number,
): Promise<string | null> {
  const supabase = await createClient();
  const deps: SignedUrlDeps = {
    async canRead(b, p) {
      const { data, error } = await supabase.rpc(READ_CHECK[b], { p_path: p });
      if (error) {
        console.error("[storage] falha ao conferir leitura", error.code ?? error.message);
        return false;
      }
      return data === true;
    },
    async sign(b, p, ttl) {
      const { data, error } = await createAdminClient().storage.from(b).createSignedUrl(p, ttl);
      if (error || !data) {
        console.error("[storage] falha ao assinar a URL", error?.message ?? "sem dados");
        return null;
      }
      return data.signedUrl;
    },
  };
  return createSignedReadUrl(deps, bucket, path, expiresIn);
}
