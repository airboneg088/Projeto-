import type { NextConfig } from "next";

/**
 * Cabeçalhos de segurança aplicados a todas as rotas. A Content-Security-Policy tem nonce por
 * pedido e por isso é montada no proxy (src/proxy.ts), não aqui.
 */
const securityHeaders = [
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Frame-Options", value: "DENY" },
  {
    key: "Permissions-Policy",
    value: "camera=(self), geolocation=(self), microphone=(), payment=()",
  },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  // cacheComponents/partialPrefetching ficam desligados: a CSP com nonce exige renderização
  // dinâmica de todas as páginas, e o prerender parcial (PPR) é incompatível com nonce
  // (ver node_modules/next/dist/docs/01-app/02-guides/content-security-policy.md).
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
