/**
 * Leitura de arquivos do storage só por URL assinada curta, criada no servidor (D77; PDF: "leitura
 * apenas por signed URL de curta duração (≤ 5 min) gerada no servidor").
 *
 * Ninguém lê `storage.objects` direto com o próprio token: com SELECT, o storage-api assina a URL
 * com o prazo que o CLIENTE escolhe, e o link continua valendo depois de o vínculo acabar. Por isso
 * o servidor (1) confere a regra como o usuário logado (`can_read_evidence` / `can_read_reference`,
 * mesma regra das tabelas) e (2) só então assina, com a chave secreta, por no máximo 5 minutos.
 */

/** Prazo máximo de uma URL de leitura, em segundos (5 min). */
export const MAX_SIGNED_URL_SECONDS = 300;

/** Buckets privados do app. */
export type StorageBucket = "evidences" | "references";

/** Prazo pedido, validado: inteiro de 1 a 300 segundos. Fora disso é erro de programação. */
export function signedUrlTtl(seconds: number = MAX_SIGNED_URL_SECONDS): number {
  if (!Number.isInteger(seconds) || seconds < 1 || seconds > MAX_SIGNED_URL_SECONDS) {
    throw new RangeError(
      `Prazo da URL assinada deve ser um inteiro de 1 a ${MAX_SIGNED_URL_SECONDS} segundos (recebido: ${seconds}).`,
    );
  }
  return seconds;
}

/** O que o servidor precisa para criar a URL: conferir como o usuário e assinar com a chave secreta. */
export type SignedUrlDeps = {
  /** Conferência como o usuário logado (RPC `can_read_evidence` / `can_read_reference`). */
  canRead(bucket: StorageBucket, path: string): Promise<boolean>;
  /** Assinatura com a chave secreta; `null` se o arquivo não existir ou der erro. */
  sign(bucket: StorageBucket, path: string, expiresIn: number): Promise<string | null>;
};

/**
 * URL assinada de leitura, ou `null` se o usuário não pode ver o arquivo (ou ele não existe). Só
 * assina depois da conferência; o prazo nunca passa de 5 min.
 */
export async function createSignedReadUrl(
  deps: SignedUrlDeps,
  bucket: StorageBucket,
  path: string,
  expiresIn: number = MAX_SIGNED_URL_SECONDS,
): Promise<string | null> {
  const ttl = signedUrlTtl(expiresIn);
  if (!(await deps.canRead(bucket, path))) return null;
  return deps.sign(bucket, path, ttl);
}
