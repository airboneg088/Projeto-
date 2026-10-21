/**
 * Content-Security-Policy com nonce por pedido (aplicada em src/proxy.ts).
 *
 * - script-src: só scripts com o nonce do pedido; 'strict-dynamic' deixa esses scripts
 *   carregarem os chunks do Next. Em desenvolvimento o React precisa de 'unsafe-eval'.
 * - style-src: 'unsafe-inline' é necessário. O Sonner injeta um <style> em tempo de execução
 *   (sem suporte a nonce) e React/Next/base-ui geram atributos style="" (ex.: variáveis CSS
 *   do Toaster). Com nonce no style-src, o navegador ignoraria o 'unsafe-inline'.
 * - upgrade-insecure-requests só em produção servida por HTTPS (em http://localhost quebraria
 *   o `pnpm start` usado nos testes E2E).
 */

export type CspOptions = {
  nonce: string;
  supabaseUrl: string;
  isDev: boolean;
  upgradeInsecureRequests: boolean;
};

function originOf(url: string): string {
  try {
    return new URL(url).origin;
  } catch {
    return "";
  }
}

export function buildCsp({
  nonce,
  supabaseUrl,
  isDev,
  upgradeInsecureRequests,
}: CspOptions): string {
  const supabase = originOf(supabaseUrl);
  const directives: Array<[string, string[]]> = [
    ["default-src", ["'self'"]],
    [
      "script-src",
      ["'self'", `'nonce-${nonce}'`, "'strict-dynamic'", ...(isDev ? ["'unsafe-eval'"] : [])],
    ],
    ["style-src", ["'self'", "'unsafe-inline'"]],
    ["img-src", ["'self'", "data:", "blob:", supabase]],
    ["connect-src", ["'self'", supabase]],
    ["font-src", ["'self'"]],
    ["frame-ancestors", ["'none'"]],
    ["form-action", ["'self'"]],
    ["base-uri", ["'self'"]],
    ["object-src", ["'none'"]],
  ];
  const policy = directives.map(([name, values]) => [name, ...values.filter(Boolean)].join(" "));
  if (upgradeInsecureRequests) policy.push("upgrade-insecure-requests");
  return policy.join("; ");
}

/** Nonce aleatório de 128 bits em base64, novo a cada pedido. */
export function createNonce(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
