# Registro de decisões

Decisões que não estavam no prompt. Reversíveis: decididas e registradas aqui. Irreversíveis ou que afetam dados, segurança ou custo: **aguardando você**.

| # | Data | Status |
|---|---|---|
| D01–D15, D19–D20 | 20/10/2026 | Decidido (reversível) |
| D16, D18 | 20/10/2026 | **Aguardando você** |
| D17 | 20/10/2026 | Decidido; risco registrado |

---

### D01 · Sessão em `proxy.ts`, não `middleware.ts`
O Next.js 16 renomeou `middleware.ts` para `proxy.ts` (o nome antigo está depreciado) e o roda em Node.js por padrão. A "middleware de sessão" do prompt será `proxy.ts`.

### D02 · base-ui = `@base-ui/react`
O pacote estável atual é `@base-ui/react` (1.9.x). O nome antigo `@base-ui-components/react` parou em release candidate.

### D03 · Mantidos `date-fns` 4 + `date-fns-tz` 3.2
Conforme o prompt. `date-fns-tz` 3.2 declara compatibilidade com `date-fns` 4. Não troco pelo `@date-fns/tz` sem perguntar.

### D04 · Gerenciador de pacotes: pnpm
Instalação mais rápida e lockfile determinístico; suportado nativamente pela Vercel.

### D05 · ➕ Tabela `task_items` (snapshot dos itens)
O snapshot do modelo precisa incluir os itens do checklist, e `attempt_item_answers` precisa de chave estrangeira estável. `task_items.template_item_id` guarda a linhagem para "falhas recorrentes" entre tarefas diferentes.

### D06 · ➕ Tabela `store_settings` + `organizations.photo_retention_days`
As notificações são "configuráveis por loja" (prazos de aviso, horas até escalonar, horário do resumo). A retenção de fotos é política de privacidade da rede, então fica na organização (padrão 180 dias).

### D07 · ➕ Tabela `review_item_flags`
"Top itens mais reprovados" e "plano de ação quando o mesmo item é reprovado 3× em 30 dias" exigem saber **quais itens** foram reprovados, não só a tentativa. Ao reprovar, o gerente marca os itens com problema (opcional quando o problema é geral).

### D08 · ➕ Tabela `data_requests`
Canal do titular (LGPD) para pedir correção ou exportação dos próprios dados, com status e resolução registrados.

### D09 · Janela = `window_start_at` → `due_at`
O fim da janela é o prazo. Evita dois campos redundantes. Tarefa avulsa pode ter só `due_at` (janela aberta desde a criação).

### D10 · Atribuição à equipe do setor
`assignee_id = null` significa "qualquer colaborador com vínculo vigente no setor". Quem inicia vira o `performed_by` da tentativa.

### D11 · Vínculo de rede para owner e admin
`memberships.store_id = null` só é permitido para `owner` e `admin` (CHECK). Gerente e colaborador sempre têm loja.

### D12 · Sincronização offline por Route Handler
A fila do IndexedDB é reenviada fora da árvore React (inclusive pelo service worker), então usa `POST /api/sync` em lote, idempotente por `client_mutation_id`. Server Actions continuam para mutações online (gerente, proprietária, admin).

### D13 · Definições dos indicadores
Detalhadas em `docs/modelo-de-dados.md` §7. Duas escolhas minhas:
- **Nota ponderada:** resultado = 1 se aprovada, 0 se não (canceladas fora). Simples e auditável; pode evoluir para nota parcial por item.
- **% aprovadas na 1ª tentativa:** exclui tarefas sem `requires_approval` (auto-aprovadas inflariam o número).

### D14 · Caminho no storage com `{organization_id}`
O prompt traz `org/{store_id}/…`; interpretei `org` como o id da organização, no mesmo padrão dos demais segmentos.

### D15 · Admin lê dados operacionais só por funções auditadas
Um `SELECT` direto não dispara trigger, então não pode ser auditado. Admin não recebe policy de leitura direta nas tabelas operacionais; lê por funções `admin_read_*` que gravam no `audit_log`.

### D16 · Planos pagos de Supabase e Vercel — **aguardando você** (custo)
Estimativa de fotos: 3 lojas × ~20 tarefas/dia × ~1,5 foto × ~300 KB ≈ **27 MB/dia → ~5 GB em 180 dias**.
- **Supabase Free** não serve para produção: 1 GB de storage, projeto pausa após 1 semana sem uso e não há backup diário (critério C9). **Pro: US$ 25/mês** (100 GB de storage, backups diários por 7 dias). PITR é add-on pago à parte; backup diário já atende o C9.
- **Vercel Hobby** é só para uso pessoal e não comercial; uma ferramenta interna de empresa é uso comercial. **Pro: US$ 20/mês por membro** (1 membro basta).
- **Resend Free** deve bastar para o volume previsto; reavaliar na Fase 6.

Desenvolvimento das Fases 1–7 roda local, sem custo. A conta paga só é necessária na Fase 8.

### D17 · Testes de RLS sem Docker neste ambiente
O container de desenvolvimento não tem o daemon do Docker rodando, então `supabase start` / `supabase test db` não funcionam aqui. Plano: tentar subir o `dockerd`; se não for possível, rodar as migrations e os testes em Postgres 16 local com um shim mínimo de `auth` e `storage` (mesmas funções `auth.uid()` / `auth.jwt()` e tabela `storage.objects` do Supabase). Os mesmos arquivos SQL rodam com `supabase test db` na sua máquina ou no CI. **Risco:** diferenças sutis do shim; mitigado rodando a suíte no CI com a stack oficial do Supabase.

### D18 · Pipeline da evidência — **aguardando você** (biblioteca fora da lista)
Para o sha256 e o phash serem confiáveis, o ideal é calculá-los **no servidor** a partir dos bytes recebidos, e aplicar a marca d'água com o **horário do servidor** depois do hash (senão a marca d'água muda os bytes e nenhuma foto repetida seria detectada). Isso pede `sharp` no Route Handler de upload. O `sharp` já é dependência opcional do próprio Next.js para otimização de imagem e é suportado na Vercel.
- **Recomendado:** adicionar `sharp`.
- **Alternativa sem lib nova:** marca d'água e phash no cliente (canvas) e sha256 no cliente sobre a imagem antes da marca d'água. Funciona, mas os hashes passam a ser informados pelo aparelho, não comprovados pelo servidor.
Decisão necessária até o início da Fase 3.

### D19 · Gerente não altera vínculos
Transferências e mudanças de papel ficam com proprietária e admin (registradas no `audit_log`). O gerente vê a equipe da própria loja.

### D20 · Prioridades: `low`, `normal`, `high`, `urgent`
Exibidas como Baixa, Normal, Alta e Urgente. Independente de `is_critical` (que é por item e alimenta o escalonamento).
