# Desenvolvimento local

> Como rodar o Éde Gestão na sua máquina (ou no ambiente de nuvem do Claude Code) com um Supabase local.

## 1. O que é a "stack local" e por quê

O caminho oficial para desenvolver com Supabase é `supabase start`, que sobe tudo em contêineres Docker. **No ambiente de nuvem deste projeto as imagens Docker não podem ser baixadas** (a política de rede bloqueia o registro de imagens), então `supabase start` é impossível aqui (decisão D17).

Para não depender disso, o repositório traz um **"mini Supabase"** sem Docker, em `scripts/local-stack/`:

| Peça           | O que é                                                                                                | Papel no Supabase real        |
| -------------- | ------------------------------------------------------------------------------------------------------ | ----------------------------- |
| Postgres 16    | Cluster local em `.local/pg`, com `pg_cron`                                                            | Banco                         |
| `bootstrap.sql`| Papéis `anon`, `authenticated`, `service_role`, `authenticator` etc., schema `extensions` e os grants do hospedado | Imagem `supabase/postgres` |
| GoTrue         | Binário oficial `supabase/auth` v2.180.0; cria o schema `auth` com as próprias migrations              | Auth (login, recuperação)     |
| PostgREST      | Binário oficial v13.0.7                                                                                | API REST (`/rest/v1`)         |
| Gateway        | `gateway.mjs` (Node, sem dependências) na porta 54321                                                  | Kong                          |
| SMTP sink      | `smtp-sink.mjs`: grava todo e-mail em `.local/mail/`, nunca envia                                      | Inbucket/Mailpit              |
| Shim de storage| `storage-shim.sql`: tabelas `storage.buckets` e `storage.objects` iguais às do storage-api             | Storage (só a parte SQL)      |

Os mesmos arquivos do projeto (`supabase/config.toml`, `supabase/migrations/`, `supabase/seed.sql`, `supabase/tests/`) funcionam nas duas stacks: na local e na oficial com Docker (seção 7).

## 2. Pré-requisitos

- Node.js 22+ e pnpm 10.28 (`corepack enable` ou `npm i -g pnpm@10.28.0`).
- Postgres 16 com as extensões `pg_cron` e `pgtap`, e o `pg_prove` (Ubuntu: `postgresql-16`, `postgresql-16-cron`, `postgresql-16-pgtap`, `libtap-parser-sourcehandler-pgtap-perl`). Binários em `/usr/lib/postgresql/16/bin` (outro caminho: defina `PG_BIN`).
- `curl`, `tar`/`xz`, `flock` e `runuser` (util-linux).
- Acesso a `github.com` na primeira subida: o `stack:up` baixa PostgREST e GoTrue para `.local/bin` e confere o checksum SHA-256.

Se o comando rodar como `root`, o Postgres roda como o usuário `postgres` do sistema (o Postgres não aceita rodar como root).

## 3. Comandos

| Comando                                  | O que faz                                                                                                                                   |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `pnpm stack:up`                          | Sobe o que estiver parado e espera ficar saudável. Na primeira vez: baixa binários, cria o cluster, o template e aplica migrations + seed. Gera o `.env.local`. |
| `pnpm stack:up --restart auth`           | Reinicia serviços (`auth`, `rest`, `gateway`, `smtp`; separados por vírgula). Use depois de mudar `[auth]` no `supabase/config.toml`.        |
| `pnpm stack:status`                      | Mostra cada serviço e se está saudável (sai com erro se algum estiver fora do ar).                                                          |
| `pnpm stack:smoke`                       | Teste de fumaça: cria usuário, faz login, chama a API, pede recuperação de senha, abre o link do e-mail e apaga o usuário.                  |
| `pnpm stack:down`                        | Para tudo. Os dados ficam em `.local/`.                                                                                                     |
| `pnpm db:reset`                          | Recria o banco `postgres` do zero (template → migrations → seed) e reinicia GoTrue e PostgREST. Equivale a `supabase db reset`.              |
| `DB_NAME=meu_teste pnpm db:reset`        | Mesmo processo num banco separado. Bom para experimentos e testes em paralelo; não mexe no banco principal.                                 |
| `pnpm db:test`                           | Roda os testes pgTAP de `supabase/tests/**/*.sql` com `pg_prove`. Aceita `DB_NAME=...` e arquivos específicos como argumento.             |
| `pnpm db:types`                          | Gera `src/lib/supabase/database.types.ts` a partir do banco local (`scripts/db/gen-types.mjs`: lê o catálogo com `psql`, mesmo formato do `supabase gen types`, sem Docker). Aceita `DB_NAME=...`. Rode depois de mudar migrations. |
| `pnpm db:types --check`                  | Não grava: sai com erro se `database.types.ts` estiver desatualizado em relação ao banco.                                                  |
| `pnpm db:rollback-check`                 | Num banco descartável (`rollback_check`), aplica cada migration e o rollback dela (`supabase/rollbacks/`) e confere que o catálogo volta igual. |
| `pnpm test:e2e`                          | Playwright (mobile 390 e desktop 1440) contra o build de produção: rode `pnpm build` antes. Recria o banco `postgres` com o seed no início. |
| `pnpm verify`                            | `lint` + `typecheck` + `test` + `check:secrets` + `db:test`.                                                                               |

Fluxo típico:

```bash
pnpm install
pnpm stack:up        # sobe a stack e gera .env.local
pnpm dev             # app em http://localhost:3000
pnpm db:reset        # depois de criar ou mudar uma migration
pnpm db:test         # testes de RLS e regras do banco
```

`db:reset` leva poucos segundos e pode rodar duas vezes seguidas. Resets de bancos diferentes podem rodar em paralelo (há travas com `flock`).

## 4. Portas e endereços

| Serviço                    | Endereço                                                   |
| -------------------------- | ---------------------------------------------------------- |
| API (gateway)              | `http://127.0.0.1:54321` (`/auth/v1`, `/rest/v1`, `/storage/v1`) |
| Postgres                   | `postgresql://postgres:postgres@127.0.0.1:54322/postgres`  |
| SMTP (e-mails capturados)  | `127.0.0.1:54325` → arquivos em `.local/mail/`             |
| PostgREST (direto)         | `127.0.0.1:54330` (saúde em `:54332/ready`)                |
| GoTrue (direto)            | `127.0.0.1:54331` (saúde em `/health`)                     |

O gateway imita o Kong do Supabase: exige o header `apikey` (chave publishable ou secreta), envia `Authorization: Bearer <apikey>` quando o pedido não tem token e libera CORS para `http://localhost:3000`. Os links de e-mail (`/auth/v1/verify`) não exigem chave, como no hospedado.

### `.env.local`

Gerado pelo `stack:up` (não versionado; o modelo é o `.env.example`):

| Variável                               | Valor local                                                  |
| -------------------------------------- | ------------------------------------------------------------ |
| `NEXT_PUBLIC_SUPABASE_URL`             | `http://127.0.0.1:54321`                                     |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | JWT `anon` padrão da CLI do Supabase                         |
| `SUPABASE_SECRET_KEY`                  | JWT `service_role` padrão da CLI — **somente no servidor**   |
| `NEXT_PUBLIC_SITE_URL`                 | `http://localhost:3000`                                      |
| `DATABASE_URL`                         | `postgresql://postgres:postgres@127.0.0.1:54322/postgres`    |

As chaves são as mesmas que `supabase start` imprime (segredo JWT público de desenvolvimento `super-secret-jwt-token-with-at-least-32-characters-long`). Servem só para uso local; produção usa as chaves do projeto na Vercel.

## 5. Usuários de exemplo (somente local)

Criados pelo `supabase/seed.sql`. **A senha abaixo é apenas para desenvolvimento local; nunca use em produção.**

Senha de todos: `Exemplo#2026`

| Papel         | E-mails                                                                                              |
| ------------- | ---------------------------------------------------------------------------------------------------- |
| Proprietária  | `proprietaria@exemplo.local`                                                                         |
| Admin         | `admin@exemplo.local`                                                                                |
| Gerentes      | `gerente.primavera@exemplo.local`, `gerente.castroalves@exemplo.local`, `gerente.parqueamerica@exemplo.local` |
| Colaboradores | `colaborador1.primavera@exemplo.local` a `colaborador3.primavera@exemplo.local`, idem para `castroalves` e `parqueamerica` |

O cadastro público está desligado (`enable_signup = false`): contas são criadas pela administração.

## 6. Banco, migrations e testes

- **Template.** O banco `ede_template` guarda o estado "Supabase recém-criado": bootstrap, schema `auth` criado pelas migrations do próprio GoTrue, funções `auth.uid()`, `auth.role()`, `auth.email()`, `auth.jwt()`, shim do storage e `pg_cron`. Todo `db:reset` clona esse template e aplica as migrations. Se `bootstrap.sql`, `post-auth.sql` ou `storage-shim.sql` mudarem, o `stack:up` reconstrói o template sozinho (ou force: `bash scripts/local-stack/build-template.sh --force`).
- **Migrations.** `supabase/migrations/AAAAMMDDHHMMSS_<descricao>.sql`, aplicadas em ordem, cada uma numa transação (`ON_ERROR_STOP`). O histórico fica em `supabase_migrations.schema_migrations`, como na CLI. Nunca edite uma migration já aplicada; crie outra.
- **Grants como no hospedado.** Tudo que o papel `postgres` cria em `public` recebe `ALL` para `anon`, `authenticated` e `service_role` (`ALTER DEFAULT PRIVILEGES`). A migration `..._privilegios.sql` fecha isso: `anon` fica sem nada em `public` (inclusive nas tabelas futuras), `authenticated` só tem o comando onde há policy (e só nas colunas permitidas) e ninguém da API trunca. Mesmo assim, toda tabela nova precisa de `enable row level security`, policies e privilégios por coluna; desde essa migration, função nova do `postgres` nasce **sem EXECUTE para PUBLIC** (padrão global): em `public` fica para `authenticated` e `service_role`; em `private`, só com `grant execute` explícito. As migrations anteriores revogam função a função (o teste `001_estrutura.sql` confere).
- **Testes pgTAP.** Um arquivo por assunto em `supabase/tests/*.sql`, autocontido:
  ```sql
  begin;
  \ir helpers/meu_helper.psql
  select plan(3);
  -- ... asserts (set local role authenticated; set local request.jwt.claims = '...';)
  select * from finish();
  rollback;
  ```
  Helpers ficam em `supabase/tests/helpers/*.psql` (não rodam como teste). O `db:test` cria a extensão `pgtap` no schema `extensions` se faltar e libera as funções dela para PUBLIC (o helper `auth.psql` faz o mesmo dentro da transação, para a CLI do Supabase); o `search_path` padrão (`"$user", public, extensions`) resolve as funções. Função criada dentro de um teste e chamada com outro papel precisa de `grant execute ... to public` (rola de volta no fim). Conta criada em teste que será vinculada pela API declara a organização: `tests.create_user('nome', '[TESTE] Nome', 'org_a')`.
- **Testes de concorrência.** Cenários que precisam de várias sessões e dados commitados (ex.: foto e envio da mesma tentativa ao mesmo tempo, o mesmo registro de foto chegando duas vezes, reatribuição durante o início) ficam em `scripts/db/concorrencia/*.sql` e rodam pelo `pnpm test` (`scripts/db/__tests__/concorrencia.test.mjs`), num banco descartável criado do template e apagado no fim. Sem a stack local, o teste é pulado.
- **E-mails.** Cada mensagem vira `.local/mail/<id>.eml` (bruto) e `<id>.json` (assunto, destinatários, HTML decodificado e `links`). Testes E2E de recuperação de senha leem o `.json`.
- **Templates de e-mail.** Declare em `supabase/config.toml` (`[auth.email.template.recovery]` com `subject` e `content_path = "./supabase/templates/recovery.html"`). A stack local lê o mesmo arquivo; depois de mudar, rode `pnpm stack:up --restart auth`.

## 7. Usando o Supabase oficial (máquina com Docker)

Numa máquina com Docker, prefira a stack oficial. Os arquivos do projeto são os mesmos:

```bash
npx supabase@2.121.0 start          # sobe tudo (API em :54321, banco em :54322)
npx supabase@2.121.0 db reset       # migrations + seed
npx supabase@2.121.0 test db        # testes pgTAP de supabase/tests
npx supabase@2.121.0 status -o env  # valores para o .env.local
```

Preencha o `.env.local` a partir do `.env.example` com a URL da API e as chaves impressas pelo `status` (as chaves JWT `anon` e `service_role` padrão são as mesmas da stack local). Os e-mails ficam no servidor de e-mail de teste da CLI (`http://127.0.0.1:54324`) em vez de `.local/mail`. Não rode as duas stacks ao mesmo tempo: as portas 54321 e 54322 coincidem (`pnpm stack:down` antes).

## 8. Diferenças conhecidas em relação ao hospedado

| Ponto                    | Stack local                                                                                         | Supabase hospedado / `supabase start`               | O que fazer                                                                                         |
| ------------------------ | --------------------------------------------------------------------------------------------------- | --------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Versão do Postgres       | **16**                                                                                              | **17** (`major_version = 17` no config.toml)        | Escrever SQL compatível com PG16 e PG17 (nada exclusivo do 17).                                      |
| Storage                  | storage-api **não roda**; `/storage/v1` responde 501. Só existem as tabelas e funções (shim)        | Upload, download e signed URLs reais               | Policies de `storage.objects` são testadas em SQL (pgTAP). Upload real e signed URL: testar com a stack oficial. |
| Papel `postgres`         | Superusuário                                                                                        | Não é superusuário                                  | Não depender de privilégios de superusuário nas migrations (ex.: criar objetos dentro de `auth` ou `storage`). |
| `pg_cron`                | Já instalado em todo banco clonado do template; jobs só executam no banco `postgres`                | Instalado pela migration                            | Usar `create extension if not exists pg_cron with schema pg_catalog;`. Em testes, chamar a função do job direto. |
| Schemas expostos na API  | Só `public`                                                                                         | `public` e `graphql_public`                         | Nada (não usamos GraphQL).                                                                          |
| Serviços ausentes        | Realtime, Studio, Edge Functions, pg_graphql, pg_net, Vault                                         | Disponíveis                                         | Fora do escopo do MVP.                                                                              |
| Limites de taxa do Auth  | Altos (1000) para os testes automatizados                                                           | Valores do projeto                                  | Testar o rate limit do login na camada do app (Fase 7).                                              |
| E-mail                   | Capturado em `.local/mail/`                                                                         | Resend (produção) / servidor de teste da CLI        | —                                                                                                   |

## 9. Problemas comuns

- **"Postgres local não está rodando"** → `pnpm stack:up`.
- **Serviço fora do ar** → `pnpm stack:status` e o log em `.local/logs/<serviço>.log` (`postgres`, `rest`, `auth`, `gateway`, `smtp`, `auth-migrate`).
- **Porta ocupada** → outro processo usa 54321/54322/54325/54330–54332 (ex.: `supabase start` rodando). Pare-o ou rode `pnpm stack:down`.
- **Começar do zero** (apaga todos os dados locais): `pnpm stack:down && rm -rf .local && pnpm stack:up`.
