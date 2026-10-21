<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## Regras do projeto (segurança)

- Página de área logada (`src/app/(app)/**`): metadados só por `generateMetadata()` que devolve `areaMetadata(área)` (passa pelo `requireArea` antes). `export const metadata` ali é erro de lint (D70).
- Redirecionamento para valor vindo de fora (query, formulário) sempre por `safeNextPath` (D60). Tabela indexada por valor da URL sempre por `lookupMessage` (D61).
- A sessão do Supabase fica em cookie HttpOnly (D63): nada no navegador usa a sessão; leitura e gravação de quem está logado passam pelo servidor.
- A API do Auth é pública (URL e chave publicável vão ao navegador): regra de segurança só na tela do app não é controle; ela precisa estar no Auth ou no banco (D64).
- Ip do cliente só por `trustedClientIp` (D68). Segredos: só `src/lib/supabase/admin.ts` lê `env.server.ts` (D71).
- Arquivo do storage só é lido por `signedReadUrl` (`src/lib/storage/signed-url.server.ts`): confere como o usuário e assina por no máximo 5 min (D77). Nunca dê SELECT em `storage.objects` a `authenticated`.
