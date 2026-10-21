# Registro de decisões

Decisões que não estavam no prompt. Reversíveis: decididas e registradas aqui. Irreversíveis ou que afetam dados, segurança ou custo: **aguardando você**.

| # | Data | Status |
|---|---|---|
| D01–D15, D19–D20 | 20/10/2026 | Decidido (reversível) |
| D16, D18 | 20/10/2026 | **Aguardando você** |
| D17 | 20/10/2026 | Decidido; risco registrado |
| D21–D32 | 21/10/2026 | Decidido (reversível) — correções da revisão de segurança da Fase 1 |
| D33–D51 | 21/10/2026 | Decidido (reversível) — correções da 2ª rodada de revisão da Fase 1; D51 registra um risco aceito |

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
Detalhadas em `docs/modelo-de-dados.md` §7 (a atribuição por pessoa foi ajustada na D46). Duas escolhas minhas:
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

---

## Correções da revisão da Fase 1 (21/10/2026)

### D21 · Uma pessoa, uma organização
Cada perfil só tem vínculos numa organização (gatilho em `memberships`, erro `profile_other_organization`). As funções de acesso também só contam papéis da organização atual e, se uma pessoa tiver vínculos vigentes em duas organizações, negam tudo (falha fechada). Conta nova criada pela administração com a chave secreta **grava** `app_metadata.organization_id`: o perfil fica visível só para o admin dessa organização e não pode ser vinculado por outra. Pela API, o 1º vínculo de uma pessoa **exige** a conta criada para aquela organização: conta sem organização declarada não é "capturada" por quem a vincular primeiro (só o sistema, sem usuário logado, vincula uma conta antiga sem esse dado). O seed e as fixtures dos testes gravam a organização em todas as contas. Quem precisar trabalhar em duas redes usa duas contas.

### D22 · owner e admin sempre de rede
`CHECK ((role in ('owner','admin')) = (store_id is null))` (reforça D11). Proprietária ou admin "de uma loja só" não existe; as funções de acesso também ignoram uma linha assim.

### D23 · Vínculo: troca de papel ou loja = encerrar e abrir outro
No UPDATE de `memberships` só mudam `sector_id`, `starts_at` e `ends_at` (privilégio de coluna). Admin só cria e altera vínculos de **gerente e colaborador**: vínculo de proprietária **e de admin** só a proprietária cria, encerra, estende ou reabre (um admin não derruba os outros nem readmite quem a proprietária tirou). Admin nunca mexe no próprio vínculo (D15: não se dá acesso operacional) e não dá papel operacional a quem tem papel de rede; a proprietária pode tudo. `set_profile_status` (admin) só vale para quem tem vínculo na organização e nunca para proprietária ou admin (o acesso deles muda pelo vínculo, que só a proprietária altera).

### D24 · Admin não lê conteúdo operacional pela auditoria
O admin lê o `audit_log` de cadastros e eventos; os registros de `task_templates`, `template_items`, `schedules`, `tasks` e `evidences` (cujo diff traz o conteúdo) ficam só para a proprietária (D15).

### D25 · Erro igual para "não existe" e "não é seu"
As RPCs conferem o acesso antes de qualquer trava e respondem `forbidden` tanto para id inexistente quanto para id de outra loja/organização. `not_found` deixou de existir nas RPCs públicas. A foto "parecida" (phash) só é procurada na mesma loja, para o gerente que revisa conseguir abri-la.

### D26 · Evidência só com arquivo no storage
`register_evidence` exige o objeto no bucket `evidences`, no caminho exato da tentativa, enviado pela própria pessoa ou pelo servidor (`file_missing`), e grava o tamanho informado pelo storage. O sha256 e o phash continuam vindo do aparelho até a decisão D18.

### D27 · Tarefa fechada não muda; prazo vencido não se move
Tarefa `approved` ou `cancelled` não tem mais nenhuma coluna alterada (`task_closed`), nem os itens dela (D41). O prazo só muda com a tarefa `pending`, `in_progress` ou `rejected`, antes de vencer e nunca para o passado; o **início da janela** só muda com a tarefa `pending` e **sem tentativas**, antes do prazo e nunca para o passado (nulo = aberta desde a criação também conta como passado); tarefa criada pela API não nasce com prazo vencido (`deadline_locked` nos três casos). Reatribuir tarefa atrasada continua permitido (não fica presa a quem saiu), mas o responsável no prazo fica gravado (D46). A criação de tarefa pela API e as edições de título, instruções, imagem, prioridade, responsável, janela e prazo vão para o `audit_log`.

### D28 · Cancelamento tardio só pela proprietária
O gerente cancela só tarefa `pending` ou `in_progress` antes do prazo e que **nunca teve tentativa enviada**. Tarefa vencida, enviada ou reprovada — inclusive a reprovada que o colaborador já reiniciou (volta a `in_progress`) — só a proprietária cancela (`owner_only`): o gerente avaliado não apaga uma falha dos indicadores. A coluna "canceladas" no painel fica para a Fase 5.

### D29 · Janela de execução é obrigatória no início, sem tolerância
`start_attempt` recusa antes de `window_start_at` (`window_not_open`). Sem tolerância por enquanto; se a operação pedir (ex.: começar a abertura 10 min antes), entra como configuração da loja. O indicador "atribuição → envio" nunca fica negativo (envio antes da janela conta zero).

### D30 · Texto em branco
Motivo de reprovação/cancelamento e observação obrigatória precisam ter **ao menos uma letra (alfabeto latino, com acentos) ou um número** (`private.is_blank` virou lista de permissão). Uma lista de espaços e invisíveis nunca fica completa (U+200E, U+00AD, U+2800, U+3164, U+E0020...) e `[[:alnum:]]` também não serve (U+3164 conta como letra). Só pontuação também não vale. O texto é gravado sem espaços e invisíveis nas pontas (`private.clean_text`).

### D31 · Item de rotina usado não é apagado
`task_items.template_item_id` virou `ON DELETE RESTRICT` e `template_items` ganhou `is_active`: item já usado em tarefa é desativado (sai das próximas tarefas), e o histórico de "falhas recorrentes" não some. Rotina e item nunca usados continuam podendo ser apagados.

### D32 · Auditoria e privilégios
- `version`, `created_at` e `created_by` das rotinas não são graváveis pela API; nem a chave secreta grava `version` direto. `created_by` é sempre o usuário logado.
- `log_event` (navegador) aceita só `export` (gerente/proprietária), com chaves conhecidas, valores simples (texto até 500 caracteres, número ou booleano) e até 2 KB. O login de admin é gravado por `log_admin_login`, que **só a chave secreta executa**: o servidor chama logo depois do login (Server Action e link de e-mail) com o id do usuário autenticado; o banco confere o vínculo de admin vigente, grava só ip válido e user_agent de até 300 caracteres e no máximo um registro por admin por minuto (D35). Garantia no próprio banco (hook do Auth) fica para a Fase 7, testada no Supabase oficial.
- `anon` não tem privilégio em nenhuma tabela de `public`; `authenticated` só tem o comando onde há policy; ninguém da API trunca tabelas (nem `service_role`), e TRUNCATE é bloqueado por gatilho nas tabelas auditadas.
- `created_by` é sempre o usuário logado; sem usuário (sistema, chave secreta) fica nulo — o valor informado é ignorado.
- Risco que continua (D17): as policies de storage são testadas só em SQL; listagem, cópia, movimentação, upsert e signed URL do storage-api real precisam de teste no CI com `supabase start` (planejado para a Fase 3).

---

## Correções da 2ª rodada de revisão da Fase 1 (21/10/2026)

### D33 · Validação depois do alcance (oráculo dos gatilhos)
Os gatilhos de validação (`BEFORE`, `SECURITY DEFINER`) rodam antes do `WITH CHECK` da RLS. Para não revelarem vínculos, a loja de uma rotina, a versão de uma rotina ou a linhagem de itens de outra loja/organização, quem grava pela API sem poder gravar no destino recebe **primeiro o mesmo erro da RLS** (42501, `new row violates row-level security policy for table "..."`), antes de qualquer consulta. A validação (`invalid_*`) só roda para quem pode gravar ali; sem usuário logado (sistema, chave secreta) ela roda sempre. Escolhi levantar o erro, e não "pular a validação e deixar a RLS recusar", porque uma função `SECURITY DEFINER` futura (que não passa pela RLS) continuaria protegida (falha fechada).

### D34 · Admin fora do conteúdo operacional por caminhos laterais
- **Planos de ação:** o admin não pode ser responsável por plano (`invalid_owner`) e a policy "o responsável lê o seu" não inclui o admin. Responsável = gerente ou colaborador da loja, ou a proprietária.
- **Imagens de referência:** o admin não lista, não lê e não envia imagens do bucket `references` (a imagem e o caminho, com o id da rotina, são conteúdo de rotina; D15). Ele também não cria nem edita rotinas. Se o suporte precisar ver uma imagem, entra uma função `admin_read_*` auditada que gera a signed URL.

### D35 · Login de admin só pelo servidor
`log_event('admin_login')` saiu do navegador. `log_admin_login(p_actor_id, p_ip, p_user_agent)` só é executável pela chave secreta, confere o vínculo de admin vigente e limita a um registro por minuto. O ip vem do 1º valor de `x-forwarded-for`: na Vercel o proxy grava o ip real do cliente; fora dela (local) o valor é informativo. `export` continua no `log_event` e vai para os Route Handlers na Fase 5.

### D36 · Autoria não informada pelo cliente
`data_requests.resolved_by`/`resolved_at` saíram do privilégio de coluna: o gatilho grava quem concluiu (usuário logado; sistema = nulo) e quando, ao virar `done`/`rejected`. Pedidos do titular passaram a ser auditados. `created_by` segue a mesma regra (D32).

### D37 · Quem saiu não altera o nome
`profiles_update_self` exige perfil ativo e vínculo vigente: quem foi desativado ou teve o vínculo encerrado não muda mais o nome que aparece no histórico. Correção depois disso: pedido do titular (`data_requests`, tipo `correction`).

### D38 · Limites de tamanho no que vai para a auditoria
Colunas de texto gravadas pela API têm limite (`CHECK`): título 200, instruções 4.000, item 500, motivo 1.000, observação 2.000 (item 1.000), nome de loja/setor/organização 100, endereço 300, plano 1.000, pedido do titular 4.000; `schedules.rule` só com `weekdays`/`monthdays`/`dates` e até 4 KB; `store_settings.channels` até 2 KB. No diff do `audit_log`, valor acima de 2 KB vai resumido (`truncated`, `bytes`, `sha256`, 1.024 caracteres iniciais).

### D39 · id gerado pelo banco
A API não informa `id` nos INSERT (privilégio de coluna): uma chave primária repetida revelaria ids de outra organização. O app usa o id devolvido (`returning`/`select()`). As RPCs offline continuam idempotentes por `client_mutation_id`.

### D40 · Retenção de fotos e purga
`purged_at` só é aceito depois do prazo de retenção da organização (`retention_not_reached`) e sempre com o horário do servidor; o mínimo de retenção subiu para **30 dias** (a foto dura ao menos até a revisão e o fechamento do mês). Bloquear o DELETE do arquivo no bucket `evidences` antes do prazo não foi feito: exigiria gatilho em `storage.objects`, tabela do serviço de storage do Supabase (risco de compatibilidade); fica com o job de retenção (Fase 4), que é o único que usa a chave secreta para isso.

### D41 · Histórico protegido também da chave secreta
- `tasks` não tem DELETE para ninguém (privilégio revogado da `service_role` e gatilho para todos).
- `task_items` só mudam (incluir, alterar, apagar) com a tarefa `pending` e sem tentativas (`task_closed`).
- `attempt_item_answers` e `review_item_flags` ganharam `task_id` e FKs compostas: o item respondido/marcado é sempre da mesma tarefa da tentativa/revisão.

### D42 · Geração não quebra com responsável que saiu
`private.instantiate_task` gera a tarefa para a equipe do setor (assignee nulo), com aviso no log, quando o responsável fixo do agendamento não tem mais vínculo na loja. Um agendamento "órfão" não derruba o job diário (Fase 4), que deve avisar o gerente para corrigir o agendamento.

### D43 · A organização sempre tem proprietária
Encerrar, agendar o fim, adiar ou apagar o último vínculo vigente de proprietária é recusado para qualquer papel (`last_owner`). Para a proprietária sair, outra proprietária vigente e sem fim precisa existir antes.

### D44 · Modo réplica não desliga a proteção
Os gatilhos de guarda (imutabilidade, máquina de estados, DELETE/TRUNCATE) são `ENABLE ALWAYS`: valem também com `session_replication_role = replica` (o modo das importações). Para a restauração de dados continuar possível, nesse modo o INSERT de linha histórica (tarefa aprovada, resposta de tentativa enviada, item) passa como está; UPDATE/DELETE seguem bloqueados. Quem é dono das tabelas ainda pode desligar um gatilho com `ALTER TABLE`, o que é DDL explícito.

### D45 · Função nova sem EXECUTE para PUBLIC
`alter default privileges for role postgres revoke execute on functions from public` (global; o padrão por schema só acrescenta). Função nova em `public` fica para `authenticated` e `service_role` (padrão do schema); em `private`, só com grant explícito. Efeito colateral: o pgTAP, criado depois das migrations, tem as funções liberadas para PUBLIC pelo `scripts/db/test.sh` e pelo helper dos testes (dentro da transação).

### D46 · A pessoa da tarefa nos indicadores
Uma regra só para a nota por pessoa e para o filtro de pessoa do `kpi_summary` (`private.task_person`): quem executou a **última tentativa** (a aprovada, se houver); sem tentativa, o **responsável no prazo** (ou o atual); nulo = "Sem responsável". Cada tarefa conta para uma pessoa só (os totais por pessoa somam o da loja). Item crítico reprovado conta para quem executou a tentativa reprovada (pode aparecer com volume 0). Reatribuir depois do prazo grava o responsável no prazo (`tasks.assignee_at_due`, coluna do sistema) na primeira troca, então a falha não muda de pessoa.

### D47 · Item "não conforme"
"Envio exige todos os itens respondidos": item marcado = feito; **desmarcado com observação = não conforme** (respondido); desmarcado sem observação = não respondido (`items_incomplete`). O colaborador registra com honestidade o que não está certo ("Alarme com defeito, técnico chamado"). Tentativa com item não conforme **nunca é auto-aprovada**: vai para o gerente decidir, mesmo em tarefa sem exigência de aprovação ("concluída é concluída"). Foto exigida no item continua exigida.

### D48 · Snapshot fiel
Tarefa nova que cita uma rotina usa a **versão atual** dela (as anteriores não são guardadas, então não há como conferir outra) e as mesmas exigências (foto, observação, aprovação) e peso (`invalid_template_version`, `invalid_snapshot`); item que cita item de rotina usa o mesmo crítico, foto e peso. Título, instruções, imagem e prioridade continuam editáveis (e auditados). Na Fase 4, criar tarefa a partir de rotina deve ir por uma RPC que chama `private.instantiate_task`.

### D49 · Foto anterior ao início da tentativa
`register_evidence` recusa foto **com EXIF** cujo horário de captura é anterior ao início da tentativa, com 10 min de tolerância para o relógio do aparelho (o mesmo limite de `clock_skew`): `photo_before_start`. Sem EXIF, o horário informado não é confiável: a foto entra com a suspeita `no_exif` e o gerente avalia (o PDF pede para não bloquear sem confirmar). Foto sem horário de captura também fica com `no_exif`. Risco: celular com relógio mais de 10 min atrasado tem a foto recusada; a mensagem pede para conferir a data e a hora.

### D50 · Sem tarefa "retroativa" pela API
Tarefa criada por usuário logado precisa de prazo no futuro (`deadline_locked`) e fica no `audit_log` (`insert`). A geração pelo sistema (job, seed) continua livre e não é auditada linha a linha: segue os agendamentos, que são auditados.

### D51 · Contagem estimada do PostgREST — **risco aceito**
`Prefer: count=planned/estimated` devolve a estimativa do planejador, que usa estatísticas da tabela inteira (todas as lojas). Não foi reproduzido como vazamento (localmente a tabela nunca foi analisada) e, com uma organização só, o volume das outras lojas não é sensível. O app não usa essas contagens. Se virar requisito, dá para recusar esses cabeçalhos com `db-pre-request` do PostgREST (função que lê `request.headers`).

