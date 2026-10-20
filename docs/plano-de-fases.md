# Plano de fases — Éde Gestão

Cada fase termina com: `pnpm lint`, `pnpm typecheck`, `pnpm test` (e testes de RLS/E2E quando existirem) rodados e com **saída real** mostrada; lista do que ficou pendente; **parada para aprovação** antes da próxima.

Critérios do MVP (C1–C10, do prompt) aparecem ao lado da fase que os entrega.

## Stack confirmada (versões estáveis em 20/10/2026, via `npm view`)

| Pacote | Versão | Observação |
|---|---|---|
| `next` | 16.4.x | App Router; sessão em `proxy.ts` (antigo `middleware.ts`, renomeado no Next 16) |
| `react` | 19.3.x | |
| `typescript` | 5.x strict | `strict`, `noUncheckedIndexedAccess` |
| `tailwindcss` | 4.3.x | tokens em CSS custom properties via `@theme` |
| `@supabase/ssr` / `@supabase/supabase-js` | 0.12.x / 2.118.x | sessão em cookies |
| `supabase` (CLI) | 2.121.x | migrations versionadas |
| `@base-ui/react` | 1.9.x | nome atual do base-ui estável |
| `sonner` · `motion` · `@number-flow/react` | 2.0 · 14.4 · 0.6 | |
| `recharts` · `react-virtuoso` · `zustand` | 3.10 · 4.18 · 5.0 | |
| `clsx` · `class-variance-authority` · `next-themes` · `cmdk` | 2.1 · 0.7 · 0.4 · 1.1 | |
| `zod` | 4.6.x | entrada validada no cliente e no servidor |
| `resend` | 6.x | |
| `idb` · `serwist` / `@serwist/next` | 8.0 · 9.5 | ver risco R2 |
| `browser-image-compression` · `exceljs` · `date-fns` · `date-fns-tz` | 2.0 · 4.4 · 4.4 · 3.2 | `date-fns-tz` 3.2 aceita `date-fns` 4 |
| `vitest` · `@playwright/test` | 5.0 · 1.64 | E2E em 390px e 1440px |

Gerenciador de pacotes: **pnpm**.

---

## Fase 0 — Descoberta ✅ (esta entrega)

**Entregáveis:** `PRODUCT.md`, este plano, `docs/modelo-de-dados.md` (diagrama ER, máquina de estados, RLS, indicadores), `docs/decisoes.md`.

**Aceite:** você aprova o modelo de dados e responde às perguntas bloqueantes.

---

## Fase 1 — Fundação · entrega C1

**Entregáveis**
- Projeto Next.js + TS strict, Tailwind com tokens **provisórios** (neutros; a identidade entra na Fase 2), base-ui, Sonner, estrutura de pastas, ESLint + Prettier, Vitest, Playwright.
- Migrations pequenas e reversíveis: extensões → enums → tabelas → constraints/índices → máquina de estados → funções RPC → RLS → storage → `audit_log` append-only → views de indicadores.
- `supabase/seed.sql`: 3 lojas, setores, 1 owner, 1 gerente por loja, 3 colaboradores por loja, 8 rotinas-padrão (abertura, salão de vendas, precificação, reposição, estoque, caixa, limpeza, fechamento) adaptadas a utilidades domésticas. Pessoas e endereços marcados `[EXEMPLO]`.
- Auth com cookies (`@supabase/ssr`), `proxy.ts` de sessão, layout por papel (`/hoje`, `/gerente`, `/painel`, `/admin`), login e recuperação de senha funcionais (sem acabamento visual).
- Headers de segurança (CSP, HSTS) e `.env.example` sem valores reais.

**Critérios de aceite (verificáveis)**
1. Migrations + seed aplicam do zero sem erro (`supabase db reset` ou script local equivalente).
2. Suíte de RLS passa os 7 testes de isolamento de `docs/modelo-de-dados.md` §6, incluindo storage.
3. Teste SQL: transição inválida e reprovação sem motivo levantam exceção.
4. Teste SQL: `UPDATE`/`DELETE` em `audit_log`, `evidences` e `reviews` falham.
5. Teste SQL: views de indicadores devolvem os valores esperados escritos no teste.
6. E2E: colaborador logado não acessa `/gerente` nem `/painel`.
7. `grep` confirma que `SUPABASE_SERVICE_ROLE_KEY` não aparece em nenhum arquivo importado por código de cliente.
8. Lint, typecheck e testes: zero erros.

**Preciso de você:** respostas da Fase 0. Não precisa de conta Supabase ainda (roda local).

---

## Fase 2 — Design system e protótipo das telas-chave

**Entregáveis**
- 2–3 direções de tokens (se não houver identidade oficial) → sua escolha → `DESIGN.md` (tokens, tipografia, espaçamento, raios, motion).
- `/prototype`: **3 variantes genuinamente diferentes**, com eixos nomeados, de (a) "Hoje" do colaborador e (b) fila de aprovação do gerente. Você escolhe; a escolhida é promovida e o resto apagado.
- Componentes com `cva`: Button, StatusBadge (cor + ícone + texto), TaskCard, ChecklistItem, PhotoCapture, EmptyState, Skeleton.

**Critérios de aceite**
1. Contraste AA verificado para texto e para as 7 cores de status, nos temas claro e escuro.
2. Alvos de toque ≥ 44px medidos no protótipo em 390px.
3. Componentes têm os estados carregando / vazio / erro / offline.
4. `/review-animations` com veredito **Approve** sobre o motion introduzido.

**Preciso de você:** escolher direção de tokens e variante do protótipo.

---

## Fase 3 — Fluxo do colaborador + evidência + offline · entrega C2, C4, C6

**Entregáveis**
- "Hoje" (contadores + lista por janela), execução (instruções, imagem de referência, checklist, câmera, observação, enviar), histórico próprio, notificações.
- Captura: `capture="environment"` + `getUserMedia` quando suportado; rejeição de arquivo com EXIF/`lastModified` anterior ao início da tentativa; "sem EXIF" vira suspeita (não bloqueia).
- Compressão no cliente (~1600px, ~300 KB, JPEG), marca d'água (loja · data/hora · colaborador), sha256 e phash, GPS opcional.
- Fila offline em IndexedDB (`idb`) + `POST /api/sync` idempotente por `client_mutation_id`; indicador "N envios aguardando conexão"; aviso de conflito (servidor vence).
- PWA instalável: manifest, ícones, splash, service worker (Serwist).

**Critérios de aceite**
1. E2E (390px): tarefa com foto obrigatória não envia sem foto; mensagem diz o que fazer.
2. E2E: mesma foto enviada duas vezes é bloqueada; foto parecida gera alerta para o gerente.
3. E2E com `context.setOffline(true)`: marcar checklist, fotografar, enviar; voltar online; **exatamente 1** tentativa e N evidências no banco. Reenvio forçado da fila não duplica.
4. E2E: gerente cancela enquanto o colaborador está offline → ao sincronizar, o colaborador vê o aviso e nada é gravado.
5. Lighthouse/Chrome: app instalável (manifest + SW válidos).
6. Gerente vê as duas datas quando `captured_at_device` e `received_at_server` divergem > 10 min.

**Preciso de você:** decisão D18 (marca d'água/hash no servidor com `sharp`), se ainda aberta.

---

## Fase 4 — Gerente: aprovação, tarefas, rotinas e agendamentos · entrega C3, C5

**Entregáveis**
- Fila de aprovação (foto em tela cheia com swipe to dismiss, comparação com referência, aprovar com 1 toque, reprovar com dialog e motivo obrigatório, marcação dos itens reprovados).
- Reexecução, tarefas avulsas, CRUD de rotinas com versão/snapshot, agendamentos, equipe.
- Job `pg_cron` de geração idempotente no fuso de cada loja; roll-over para `overdue`; planos de ação (mesmo item reprovado 3× em 30 dias).

**Critérios de aceite**
1. Teste SQL: rodar a geração 2× para a mesma data → mesma contagem de tarefas.
2. Teste SQL: geração às 23:30 UTC-3 cria tarefas do dia local correto (virada de dia no fuso da loja).
3. Teste SQL: editar uma rotina não altera tarefas já geradas.
4. E2E: reprovar sem motivo é impossível (UI e banco); histórico mostra todas as tentativas.
5. Teste SQL: 3ª reprovação do mesmo item em 30 dias cria exatamente 1 plano de ação.

---

## Fase 5 — Painel da proprietária, relatórios e exportação · entrega C7

**Entregáveis:** painel das 3 lojas com filtros (período, loja, setor, funcionário, status), indicadores, drill-down até tarefa e foto, recharts (sem animação de entrada), NumberFlow nos KPIs, relatórios diário/semanal/mensal, exportação CSV e Excel (registrada no `audit_log`).

**Critérios de aceite**
1. Teste com dados de exemplo: cada KPI exibido = valor esperado escrito no teste.
2. Nota ponderada sempre aparece com o volume atribuído; nenhuma tela ordena pessoas por quantidade concluída.
3. Exportação de 10 mil linhas termina sem estourar o limite da função na Vercel.
4. `submitted` não aparece como concluída em nenhum número.

---

## Fase 6 — Notificações e escalonamento · entrega C8

**Entregáveis:** central in-app + Sonner, e-mail via Resend, regras (aviso antes do vencimento, atraso, correção solicitada, lembrete de recorrente, aguardando aprovação há X h, escalonamento de tarefa crítica → gerente → proprietária), resumo diário às 20:00 da loja, configuração por loja, interface `channel` pronta para push/WhatsApp (sem implementar).

**Critérios de aceite**
1. Teste SQL com relógio fixado: cada regra dispara no horário local correto e uma única vez (`dedupe_key`).
2. Escalonamento: tarefa crítica não feita na janela → gerente; X h depois → proprietária.
3. E-mail de teste chega pelo domínio verificado.

**Preciso de você:** domínio verificado na Resend.

---

## Fase 7 — Endurecimento e revisão de qualidade · entrega C10

**Entregáveis:** `/impeccable audit` e `harden` em todas as telas; `/review-animations`; `/find-animation-opportunities`; `/impeccable polish`; Playwright E2E dos fluxos críticos em 390px e 1440px; rate limit no login; páginas de política de privacidade e termos; canal do titular (LGPD); job de retenção de fotos.

**Critérios de aceite**
1. `/impeccable audit` sem problemas críticos.
2. `/review-animations` com veredito **Approve**.
3. E2E dos fluxos críticos verdes nos dois viewports.
4. Job de retenção remove o arquivo do storage e mantém o registro com `purged_at`; ação registrada no `audit_log`.

---

## Fase 8 — Implantação · entrega C9

**Entregáveis:** `docs/deploy.md` passo a passo para pessoa não programadora (criar projeto Supabase, rodar migrations, variáveis na Vercel, domínio, Resend, `pg_cron`); `docs/backup.md` (backup diário/PITR + roteiro de restauração); checklist do piloto na Loja Primavera.

**Critérios de aceite**
1. Restauração testada uma vez, com evidência (data, projeto, resultado).
2. Deploy de produção acessível pelo domínio, PWA instalado em um celular real.

**Preciso de você:** contas Supabase e Vercel nos planos definidos (ver D16).
