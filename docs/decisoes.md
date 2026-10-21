# Registro de decisões

Decisões que não estavam no prompt. Reversíveis: decididas e registradas aqui. Irreversíveis ou que afetam dados, segurança ou custo: **aguardando você**.

| # | Data | Status |
|---|---|---|
| D01–D15, D19–D20 | 20/10/2026 | Decidido (reversível) |
| D16, D18 | 20/10/2026 | **Aguardando você** |
| D17 | 20/10/2026 | Decidido; risco registrado |
| D21–D32 | 21/10/2026 | Decidido (reversível) — correções da revisão de segurança da Fase 1 |
| D33–D51 | 21/10/2026 | Decidido (reversível) — correções da 2ª rodada de revisão da Fase 1; D51 registra um risco aceito |
| D52–D59 | 21/10/2026 | Decidido (reversível) — correções da 3ª rodada de revisão da Fase 1; riscos aceitos e adiados no fim deste arquivo |
| D60–D71 | 21/10/2026 | Decidido (reversível) — correções da 3ª rodada de revisão da Fase 1 (app: login, sessão, Auth, cabeçalhos, segredos) |
| D72–D91 | 21/10/2026 | Decidido (reversível) — correções da revisão final da Fase 1 (offline, indicadores, snapshot, auditoria, storage, LGPD, Auth); riscos novos no fim deste arquivo |

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
A fila do IndexedDB é reenviada fora da árvore React (inclusive pelo service worker), então usa `POST /api/sync` em lote, idempotente por `client_mutation_id` (início, resposta de item, foto e envio; a resposta leva também o horário do aparelho, D56). Server Actions continuam para mutações online (gerente, proprietária, admin).

### D13 · Definições dos indicadores
Detalhadas em `docs/modelo-de-dados.md` §7 (a atribuição por pessoa foi ajustada na D46). Duas escolhas minhas:
- **Nota ponderada:** resultado = 1 se aprovada, 0 se não (canceladas fora). Simples e auditável; pode evoluir para nota parcial por item. Tarefa ainda no prazo também conta como 0 no período: a comparação é justa em períodos fechados; o painel do dia (Fase 5) decide como mostrar o que está em aberto (risco R3-REGRAS-07).
- **% aprovadas na 1ª tentativa:** exclui tarefas sem `requires_approval` (auto-aprovadas inflariam o número).

### D14 · Caminho no storage com `{organization_id}`
O prompt traz `org/{store_id}/…`; interpretei `org` como o id da organização, no mesmo padrão dos demais segmentos.

### D15 · Admin lê dados operacionais só por funções auditadas
Um `SELECT` direto não dispara trigger, então não pode ser auditado. Admin não recebe policy de leitura direta nas tabelas operacionais; lê por funções `admin_read_*` que gravam no `audit_log`. Hoje existe só `admin_read_tasks` (tarefas); as demais leituras de suporte entram com a tela de administração (D90).

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
O admin lê o `audit_log` de cadastros e eventos; os registros de `task_templates`, `template_items`, `schedules`, `tasks`, `task_items`, `task_attempts` e `evidences` (cujo diff traz o conteúdo) ficam só para a proprietária (D15).

### D25 · Erro igual para "não existe" e "não é seu"
As RPCs conferem o acesso antes de qualquer trava e respondem `forbidden` tanto para id inexistente quanto para id de outra loja/organização. `not_found` deixou de existir nas RPCs públicas. A foto "parecida" (phash) só é procurada na mesma loja, para o gerente que revisa conseguir abri-la.

### D26 · Evidência só com arquivo no storage
`register_evidence` exige o objeto no bucket `evidences`, no caminho exato da tentativa, enviado pela própria pessoa ou pelo servidor (`file_missing`), e grava o tamanho informado pelo storage. O sha256 e o phash continuam vindo do aparelho até a decisão D18.

### D27 · Tarefa fechada não muda; prazo vencido não se move
Tarefa `approved` ou `cancelled` não tem mais nenhuma coluna alterada (`task_closed`), nem os itens dela (D41). O prazo só muda com a tarefa `pending`, `in_progress` ou `rejected`, antes de vencer e nunca para o passado; o **início da janela** só muda com a tarefa `pending` e **sem tentativas**, antes do prazo e nunca para o passado (nulo = aberta desde a criação também conta como passado); tarefa criada pela API não nasce com prazo vencido (`deadline_locked` nos três casos). Reatribuir tarefa (inclusive atrasada) continua permitido e ela não fica presa a quem saiu: a tentativa aberta de quem deixou de ser o responsável é encerrada sem envio e o novo responsável inicia outra (D52); depois do prazo, o responsável no prazo fica gravado (D46). A criação de tarefa pela API e as edições de título, instruções, imagem, prioridade, responsável, janela e prazo vão para o `audit_log`.

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
- `log_event` (navegador) aceita só `export` (gerente/proprietária), com chaves conhecidas, valores simples (texto até 500 caracteres, número ou booleano) e até 2 KB (e, desde a D76, no máximo 10 por minuto e 200 por dia por pessoa). O login de admin é gravado pelo próprio Auth (hook Custom Access Token, D79); `log_admin_login`, que **só a chave secreta executa**, grava o contexto (ip válido e user_agent de até 300 caracteres, `admin_login_context`), no máximo um registro por admin por minuto (D35).
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
`log_event('admin_login')` saiu do navegador. `log_admin_login(p_actor_id, p_ip, p_user_agent)` só é executável pela chave secreta, confere o vínculo de admin vigente e limita a um registro por minuto. O ip vem só de fonte confiável (D68; antes era o 1º valor de `x-forwarded-for`, que o cliente escolhe). `export` continua no `log_event` e vai para os Route Handlers na Fase 5. Desde a D79 o login em si (`admin_login`) é gravado pelo Auth, e `log_admin_login` grava só o contexto (`admin_login_context`).

### D36 · Autoria não informada pelo cliente
`data_requests.resolved_by`/`resolved_at` saíram do privilégio de coluna: o gatilho grava quem concluiu (usuário logado; sistema = nulo) e quando, ao virar `done`/`rejected`. Pedidos do titular passaram a ser auditados. `created_by` segue a mesma regra (D32).

### D37 · Quem saiu não altera o nome
`profiles_update_self` exige perfil ativo e vínculo vigente: quem foi desativado ou teve o vínculo encerrado não muda mais o nome que aparece no histórico. Correção depois disso: pedido do titular (`data_requests`, tipo `correction`), que continua aberto a quem saiu (D78).

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
Os gatilhos de guarda (imutabilidade, máquina de estados, DELETE/TRUNCATE) são `ENABLE ALWAYS`: valem também com `session_replication_role = replica` (o modo das importações). Para a restauração de dados continuar possível, nesse modo o INSERT de linha histórica (tarefa aprovada, resposta de tentativa enviada, item) passa como está; UPDATE/DELETE seguem bloqueados. Quem é dono das tabelas ainda pode desligar um gatilho com `ALTER TABLE`, o que é DDL explícito. Os gatilhos de **auditoria e de integridade** (validações, versão da rotina, última proprietária, passagem da tarefa) continuam no modo padrão e **não** disparam em modo réplica: risco R3-FUNCOES-04, abaixo.

### D45 · Função nova sem EXECUTE para PUBLIC
`alter default privileges for role postgres revoke execute on functions from public` (global; o padrão por schema só acrescenta). Função nova em `public` fica para `authenticated` e `service_role` (padrão do schema); em `private`, só com grant explícito. Efeito colateral: o pgTAP, criado depois das migrations, tem as funções liberadas para PUBLIC pelo `scripts/db/test.sh` e pelo helper dos testes (dentro da transação).

### D46 · A pessoa da tarefa nos indicadores
Uma regra só para a nota por pessoa e para o filtro de pessoa do `kpi_summary` (`private.task_person`): quem executou a **última tentativa** (a aprovada, se houver; tentativa encerrada sem envio não conta, D52); sem tentativa, o **responsável no prazo** (ou o atual); nulo = "Sem responsável". Cada tarefa conta para uma pessoa só (os totais por pessoa somam o da loja). Item crítico reprovado conta para quem executou a tentativa reprovada (pode aparecer com volume 0). Reatribuir depois do prazo grava o responsável no prazo (`tasks.assignee_at_due`, coluna do sistema) na primeira troca, então a falha não muda de pessoa. Tarefa vencida e não aprovada: ver D74 (vale quem estava com ela no prazo, mesmo que a tentativa tenha sido encerrada depois).

### D47 · Item "não conforme"
"Envio exige todos os itens respondidos": item marcado = feito; **desmarcado com observação = não conforme** (respondido); desmarcado sem observação = não respondido (`items_incomplete`). O colaborador registra com honestidade o que não está certo ("Alarme com defeito, técnico chamado"). Tentativa com item não conforme **nunca é auto-aprovada**: vai para o gerente decidir, mesmo em tarefa sem exigência de aprovação ("concluída é concluída"). Foto exigida no item continua exigida.

### D48 · Snapshot fiel
Tarefa nova que cita uma rotina usa a **versão atual** dela (as anteriores não são guardadas, então não há como conferir outra) e as mesmas exigências (foto, observação, aprovação) e peso (`invalid_template_version`, `invalid_snapshot`); item que cita item de rotina usa o mesmo crítico, foto e peso. Título, instruções, imagem e prioridade continuam editáveis (e auditados). Na Fase 4, criar tarefa a partir de rotina deve ir por uma RPC que chama `private.instantiate_task`.

### D49 · Foto anterior ao início da tentativa
`register_evidence` recusa foto **com EXIF** cujo horário de captura é anterior ao início da tentativa (o do aparelho, quando a tentativa veio da fila offline, D72), com 10 min de tolerância para o relógio do aparelho (o mesmo limite de `clock_skew`): `photo_before_start`. Sem EXIF, o horário informado não é confiável: a foto entra com a suspeita `no_exif` e o gerente avalia (o PDF pede para não bloquear sem confirmar). Foto sem horário de captura também fica com `no_exif`. Risco: celular com relógio mais de 10 min atrasado tem a foto recusada; a mensagem pede para conferir a data e a hora (R3-04).

### D50 · Sem tarefa "retroativa" pela API
Tarefa criada por usuário logado precisa de prazo no futuro (`deadline_locked`) e fica no `audit_log` (`insert`). A geração pelo sistema (job, seed) continua livre e não é auditada linha a linha: segue os agendamentos, que são auditados.

### D51 · Contagem estimada do PostgREST — **risco aceito**
`Prefer: count=planned/estimated` devolve a estimativa do planejador, que usa estatísticas da tabela inteira (todas as lojas). Não foi reproduzido como vazamento (localmente a tabela nunca foi analisada) e, com uma organização só, o volume das outras lojas não é sensível. O app não usa essas contagens. Se virar requisito, dá para recusar esses cabeçalhos com `db-pre-request` do PostgREST (função que lê `request.headers`).

---

## Correções da 3ª rodada de revisão da Fase 1 (21/10/2026)

### D52 · Passagem da tarefa: tentativa aberta de quem saiu é encerrada sem envio
**Contexto:** a D27 dizia que reatribuir não deixava a tarefa presa a quem saiu, mas a tentativa aberta de quem iniciou continuava valendo: o novo responsável recebia `invalid_transition` ("Outra pessoa já está executando") e quem saiu ainda respondia e enviava. Depois do prazo, só a proprietária podia destravar, cancelando (e a tarefa sumia dos indicadores).
**Decisão:** a tentativa aberta de quem não pode mais executar a tarefa é **encerrada sem envio** (`task_attempts.abandoned_at` com o horário do servidor e `abandoned_reason`: `reassigned` quando a tarefa é de outra pessoa ou de outro setor, `access_lost` quando a pessoa perdeu o vínculo de colaborador na loja ou o perfil está inativo). Acontece na hora da reatribuição (gatilho em `tasks`), na hora da troca de setor, do fim imediato do vínculo ou da desativação (D82) e, para vínculo com fim agendado, quando outra pessoa que pode executar a tarefa a inicia (`start_attempt`). Fica no `audit_log` (`attempt_abandoned`, só a proprietária lê) e no histórico; a tentativa encerrada congela (sem respostas, fotos ou envio). A tarefa segue `in_progress` (ou `overdue`) até o novo responsável iniciar a tentativa seguinte. `answer_item`, `register_evidence` e `submit_attempt` conferem `can_execute_task` de novo depois das travas: quem saiu recebe `forbidden`. Nos indicadores, tentativa encerrada sem envio não é "execução" de ninguém (antes do prazo, a pessoa da tarefa segue a reatribuição; D46; depois do prazo, a falha fica com quem tinha a tarefa no prazo, D74; e a "1ª tentativa" é o 1º envio, D73). Enquanto quem iniciou ainda pode executar a tarefa, ninguém a toma dele.
**Por quê:** nada é apagado (o histórico mostra quem começou e por que parou), a passagem é auditada e não exige uma tela nova; sem mudar a máquina de estados (não há volta `in_progress → pending`).

### D53 · "Atrasada" = venceu sem envio
**Contexto:** `kpi_summary` contava como atrasada toda tarefa não aprovada com prazo vencido, então uma tarefa enviada a tempo saía de "Aguardando aprovação" e virava "Atrasada" só porque o gerente ainda não revisou. PRODUCT.md §7 define Atrasada como "Venceu sem envio".
**Decisão:** vale o PRODUCT.md. Atrasada = não aprovada, prazo vencido e **não** aguardando a revisão de um envio feito até o prazo. Enviada até o prazo e ainda sem revisão continua "Aguardando aprovação" (e em "Pendentes"); enviada depois do prazo, nunca enviada ou reprovada sem novo envio até o prazo contam como atrasadas. `submitted` continua sem contar como concluída.
**Por quê:** a demora da revisão é do gerente (medida em "Tempo envio → revisão"), não atraso de quem executou; e o painel passa a bater com o status exibido da tarefa.

### D54 · Foto exigida pela tarefa = foto geral, além das dos itens
**Contexto:** `submit_attempt` aceitava qualquer foto da tentativa para `tasks.requires_photo`, então a foto de um item cumpria também a "foto da tarefa" (ex.: Limpeza: a foto do piso valia como "foto do salão limpo").
**Decisão:** com `requires_photo` na tarefa, o envio exige ao menos uma foto **geral** (`evidences.task_item_id` nulo), além das fotos exigidas por item — como já diziam o `COMMENT` da rotina e o modelo de dados.
**Por quê:** é o que o cadastro da rotina promete ("além das fotos exigidas por item"); a alternativa (qualquer foto vale) tornaria a opção da tarefa redundante sempre que algum item exige foto.

### D55 · Setor nos indicadores leva a loja
**Contexto:** `weighted_scores('sector')` devolvia só o nome do setor; com "Caixa", "Estoque", "Limpeza" e "Salão de vendas" nas três lojas, a proprietária recebia linhas iguais.
**Decisão:** a função ganhou a coluna `store_id` (loja do grupo; nula por pessoa, que pode ter passado por mais de uma loja) e, por setor, o nome vem como "Loja · Setor".
**Por quê:** o nome já serve para exibir sem outra consulta, e o `store_id` permite agrupar e filtrar por loja na tela (Fase 5).

### D56 · Resposta de item idempotente e "a mais nova vence" pelo relógio do aparelho
**Contexto:** `attempt_item_answers` não tinha `client_mutation_id` e `answer_item` gravava o que chegasse por último: um reenvio offline atrasado (fila reordenada) desfazia uma marcação mais nova.
**Decisão:** `answer_item(p_attempt_id, p_task_item_id, p_checked, p_note, p_client_mutation_id, p_answered_at_device)` devolve `boolean`. O mesmo `client_mutation_id` não muda nada (devolve `true`); resposta com horário do aparelho anterior ao da resposta gravada é ignorada (devolve `false`; o app mostra a resposta do servidor). O horário do aparelho é gravado em `answered_at_device`, limitado ao horário do servidor (relógio adiantado não "congela" o item). Sem horário do aparelho (uso online), vale a ordem de chegada. O cliente offline (Fase 3) **deve** enviar os dois.
**Por quê:** a ordem real das respostas só o aparelho conhece; guardar só o último `client_mutation_id` por item basta para o reenvio idêntico, e o horário resolve o reenvio de uma resposta antiga sem guardar o histórico de cada toque. Risco aceito abaixo (R3-01).

### D57 · Versão da rotina só sobe depois do primeiro uso
**Contexto:** a regra "itens gravados na mesma transação da criação não contam" não funciona pela API: rotina, itens e imagem de referência (cujo caminho leva o id da rotina) chegam em pedidos separados, e uma rotina nova com 3 itens nascia na versão 4.
**Decisão:** editar o conteúdo ou os itens só sobe a `version` se alguma tarefa já usou a rotina; antes disso ela está "em montagem" e fica na versão 1. Depois do primeiro uso, cada edição sobe de 1 em 1, como antes.
**Por quê:** a versão existe para identificar o snapshot das tarefas; sem tarefa, não há o que distinguir. Alternativa descartada: RPC de criação atômica (rotina + itens), que não resolve a imagem enviada depois. Outra possível: só subir se uma tarefa usa a versão *atual* (uma edição em vários pedidos subiria uma vez só); fica para a Fase 4 se a numeração incomodar.

### D58 · Agendamento: janela no mesmo dia e regra dentro do domínio
**Contexto:** `window_end = '24:00'` é um `time` válido e jogava o prazo da tarefa do dia D para D+1 (contando no dia seguinte dos indicadores); a regra aceitava `weekdays` 0 e 9, `monthdays` 40 e datas como "amanhã".
**Decisão:** `CHECK` `schedules_window_same_day` (`window_end <= 23:59:59`, além de `window_start < window_end`) e `schedules_rule_values` (`private.is_valid_schedule_rule`, imutável): `weekdays` inteiros 1..7 (ISO), `monthdays` inteiros 1..31, `dates` AAAA-MM-DD que existem, em qualquer chave presente. Erro 23514 com o nome da constraint.
**Por quê:** a geração (Fase 4) não precisa tratar valores impossíveis e o erro aparece na hora de salvar, onde o gerente pode corrigir. Janela que atravessa a meia-noite não é suportada; se a operação pedir, entra como duração em vez de hora final (risco R3-07).

### D59 · Teste de fumaça desativa o usuário, não apaga
**Contexto:** `pnpm stack:smoke` terminava apagando o usuário criado, o que falha com `profiles.id ... ON DELETE RESTRICT` (pessoas nunca são apagadas).
**Decisão:** o teste faz exclusão lógica no Auth (`should_soft_delete`, e-mail embaralhado), deixa o perfil `inactive` e confere que o login passa a ser recusado. Nenhum usuário de teste fica utilizável; a linha fica, como de qualquer pessoa que saiu.
**Por quê:** é o mesmo caminho que a administração usará para quem sai; não exige afrouxar a FK nem acesso direto ao banco.

---

## Correções da 3ª rodada de revisão da Fase 1 — app (21/10/2026)

### D60 · `next` normalizado como o navegador resolve
**Contexto:** `safeNextPath` devolvia o texto recebido. `/.//evil.com` (e `/x/..//evil.com`, `/%2E//evil.com`) passava nas checagens; o navegador resolve os segmentos `.`/`..` para `//evil.com` e saía do site depois do login (R2-APP-01). Caracteres fora do Latin-1 iam crus para o cabeçalho e davam 500, inclusive gastando o link do e-mail (R2-APP-10).
**Decisão:** o valor é resolvido com `new URL(valor, "https://app.invalid")` e só vale se ficar na mesma origem e o caminho não começar com `//`; a mesma checagem roda em cada camada decodificada (pega `/.%2F/evil.com`). A função devolve **o caminho normalizado** (`pathname + search + hash`, sempre ASCII), nunca o texto bruto. Vale para o `next` do login (página e Server Action); o `/auth/confirm` deixou de usar `next` (D62).
**Por quê:** comparar com o mesmo algoritmo do navegador (WHATWG URL) fecha a classe de truques de ponto e codificação de uma vez, em vez de listar padrões.

### D61 · Mensagens da URL só por chave própria
**Contexto:** `/login?erro=__proto__` (ou `constructor`, `toString`) lia o protótipo de `Object` e a página caía com 500 (R2-APP-15).
**Decisão:** `lookupMessage` usa `Object.hasOwn` e só devolve texto. Toda tabela indexada por valor da URL passa por ela.
**Por quê:** é a correção na causa (busca em objeto literal), sem trocar as tabelas por `Map`.

### D62 · `/auth/confirm` só aceita a recuperação de senha pelo fluxo PKCE
**Contexto:** a rota aceitava `token_hash` de qualquer tipo (`magiclink`, `email`, `signup`, `invite`) por GET: um link de login da conta de outra pessoa trocava a sessão de quem o abrisse, sem aviso (R2-APP-06). Conferido aqui: o Auth também aceita o token de um *magic link* como `type=recovery` (gera sessão com `amr` "otp").
**Decisão:** só `?code=` (PKCE). A troca exige o `code_verifier` gravado no navegador que pediu o link, então um link mandado por outra pessoa não cria sessão. Depois da troca, a sessão precisa ter `amr` "recovery" (o app não aceita mais "otp" como recuperação); senão é encerrada. O destino é sempre `/redefinir-senha`, que mostra o e-mail da conta. Quando a Fase 6/7 precisar de link que funcione em outro navegador (modelo com `{{ .TokenHash }}`), ele entra em dois passos: GET mostra "Continuar" e um POST (Server Action, origem conferida) valida o token, avisando se outra pessoa está logada. Enquanto isso, o e-mail e a tela dizem que o link vale no mesmo aparelho e navegador (D80; riscos R3-05).
**Por quê:** é o único link de e-mail que o app envia hoje; PKCE amarra o link ao navegador sem tela nova.

### D63 · Cookie da sessão: HttpOnly, Secure em produção, Lax, 7 dias
**Contexto:** os cookies saíam com o padrão do `@supabase/ssr`: legíveis pelo JavaScript, sem `Secure` e por 400 dias (R2-APP-04).
**Decisão:** `sessionCookieOptions` (src/lib/supabase/cookies.ts) é aplicada a toda gravação no `setAll` do servidor e do proxy: `httpOnly`, `secure` com `NODE_ENV=production`, `sameSite: "lax"`, `path: "/"`, `maxAge` de **7 dias** renovado a cada gravação (na prática, "sai depois de 7 dias sem usar neste aparelho"). O `@supabase/ssr` 0.12 ignora o `maxAge` de `cookieOptions`, por isso a política é imposta no `setAll`. Conferido: nenhum código do navegador lê a sessão (o `client.ts` não é importado); o comentário dele avisa que, com HttpOnly, ele é anônimo.
**Por quê:** um script injetado não leva o token. Para a Fase 3, a fila offline já vai pelo servidor (`POST /api/sync`, D12) e upload de foto deve usar URL assinada criada no servidor; Realtime no navegador, se vier, pede uma decisão nova (não afrouxar o HttpOnly). Offline por mais de 7 dias exige entrar de novo antes de sincronizar (a fila continua no IndexedDB; risco R3-06).

### D64 · Troca de senha pela API do Auth: reautenticação depois de 24 h e aviso por e-mail
**Contexto:** qualquer token de acesso trocava a senha direto no Auth (`PUT /user`), sem link e sem a senha atual (R2-APP-03). A regra "só pela recuperação" existia só na tela do app; **a API do Auth é pública** (URL e chave publicável vão para o navegador), então checagem no app não é controle.
**Decisão:** `[auth.email] secure_password_change = true` e aviso por e-mail quando a senha muda (`[auth.email.notification.password_changed]`, modelo em pt-BR em `supabase/templates/senha-alterada.html`). A stack local espelha as duas (auth-env.mjs). O GoTrue v2.180 não tem opção de exigir a senha atual.
**Por quê:** é o que o Auth oferece. Conferido: sessão com mais de 24 h recebe `reauthentication_needed`; o link de recuperação cria sessão nova e continua funcionando (E2E). Resta a janela de 24 h depois do login (risco R3-APP-02), coberta pelo e-mail de aviso e pelo cookie HttpOnly.

### D65 · Política de senha: 8+ caracteres, letra e número, até 72 bytes
**Contexto:** o Auth só exigia 8 caracteres e a mensagem prometia "letras e números"; o zod contava caracteres, mas o limite do Auth/bcrypt é em bytes: 40 "ç" passava e caía em "tente de novo" (R2-APP-14).
**Decisão:** `password_requirements = "letters_digits"` (stack local: `GOTRUE_PASSWORD_REQUIRED_CHARACTERS`, mesmo mapeamento da CLI). `redefinirSchema` usa as mesmas regras: letra de A a Z (o Auth não conta letra acentuada), número e no máximo 72 bytes UTF-8, cada uma com sua mensagem. `weak_password` e `validation_failed` do Auth têm texto próprio. O login não muda (senha antiga continua entrando).
**Por quê:** a tela e o Auth recusam as mesmas senhas, com a explicação certa. Regra mais forte (maiúscula/símbolo) fica para quando houver política da empresa.

### D66 · Token de acesso de 10 min; "Sair" encerra só este aparelho
**Contexto:** depois de "Sair" ou da troca de senha (que encerra todas as sessões), o token de acesso continuava valendo na API (PostgREST/RLS) até expirar: `jwt_expiry` era 3.600 s (R2-APP-12).
**Decisão:** `jwt_expiry = 600` (10 min; a stack local lê do config.toml). "Sair" continua `scope: "local"` (sair do tablet da loja não derruba o celular da pessoa); a troca de senha continua `scope: "global"`. O refresh token é revogado na hora nos dois casos. Conferir a sessão em `auth.sessions` em toda policy (ou num `db-pre-request` do PostgREST) foi descartado agora: mexe em todos os helpers de acesso e não cobre o storage-api; fica registrado como risco (R3-APP-03).
**Por quê:** reduz a janela de 60 para 10 min sem custo para o uso offline da Fase 3: o token só é usado ao sincronizar, e o servidor o renova pelo refresh token (que não expira por tempo).

### D67 · Login e recuperação: mesma resposta, mesmo tempo; *magic link* desligado
**Contexto:** a tela de login respondia "acesso não está ativo" para conta bloqueada no Auth antes de conferir a senha (R2-APP-09) e respondia mais rápido para e-mail inexistente (R2-APP-08). Direto no Auth, com a chave publicável, `/otp` e `/magiclink` respondiam diferente para e-mail cadastrado e mandavam um e-mail de login válido a qualquer conta (R2-APP-02).
**Decisão:**
- `user_banned` recebe a mesma mensagem de senha errada; quem tem a senha certa e está sem acesso vê "sem acesso" depois de entrar (requireArea).
- Login recusado leva no mínimo **800 ms**; "Esqueci minha senha" leva sempre no mínimo **1.500 ms** (o Auth demora mais quando envia o e-mail). Validação de formulário não espera (não consulta o Auth).
- Login por link de e-mail desligado no GoTrue (`GOTRUE_EXTERNAL_EMAIL_MAGIC_LINK_ENABLED=false`, na stack local pelo auth-env.mjs; não há chave para isso no `config.toml` da CLI). `/magiclink` passa a responder igual para qualquer e-mail e nenhum dos dois manda mais e-mail de login.
**Por quê:** é o que dá para uniformizar no app e na configuração do Auth. O que sobra é do próprio Auth e só fecha com captcha (risco R3-APP-01).

### D68 · Ip do cliente só de fonte confiável
**Contexto:** o registro `admin_login` gravava o 1º valor de `x-forwarded-for`, que o cliente escolhe atrás de qualquer proxy que acrescenta (R2-APP-16).
**Decisão:** modelo de confiança explícito (`trustedClientIp`): na Vercel (`VERCEL=1`), `x-real-ip` (ou o 1º de `x-vercel-forwarded-for`), que a borda da Vercel grava e sobrescreve; o valor precisa ser um ip válido. Fora da Vercel (local, `next start` sem proxy), **nenhum** cabeçalho é confiável e o ip não é gravado. Hospedagem em outro lugar precisa declarar o cabeçalho do seu proxy aqui. O `user_agent` continua informativo (o cliente escolhe).
**Por quê:** um ip falso no log de segurança é pior que nenhum; a regra fica num lugar só e testada.

### D69 · CSP em todas as respostas HTML, inclusive 404
**Contexto:** o `matcher` do proxy pulava qualquer caminho de um segmento terminado em `.js`, `.txt`, `.ico`…, existindo ou não; o 404 em HTML desses caminhos saía sem CSP (R2-APP-11).
**Decisão:** o proxy só deixa de fora `_next/static/`, `/_next/image` e `/icon.svg` (arquivos que existem; a exclusão é ancorada, D89). Arquivo novo em `public/` (robots.txt, manifest, service worker da Fase 3) entra nessa lista. Conferido: 404 de `/_next/static/...` é `text/plain`.
**Por quê:** a CSP com nonce é montada no proxy; mandar todo HTML por ele é mais simples que manter uma segunda CSP estática no next.config (que valeria também para o service worker e poderia bloqueá-lo).

### D70 · Metadados de área só depois do guard
**Contexto:** `export const metadata` das páginas de área era resolvido mesmo com o pedido negado: o colaborador recebia o título "Gerência" no HTML e no RSC do redirecionamento (R2-APP-13). Com `generateMetadata` lendo dados (Fases 4–5), vazaria dado.
**Decisão:** páginas de área usam `generateMetadata()` que chama `areaMetadata(área)`, que passa por `requireArea` antes de devolver o título. Uma regra do ESLint (`no-restricted-syntax` em `src/app/(app)/**`) recusa `export const metadata` ali.
**Por quê:** a regra fica no código e no lint, não só na revisão; `requireArea` é memorizado por pedido (sem consulta extra).

### D71 · `check:secrets` mais estrito e com autoteste
**Contexto:** o script não pegava `SUPABASE_SERVICE_ROLE_KEY` (nome do critério 7; a busca diferenciava maiúsculas), nem bloco `env` no next.config, nem um Server Component que passa `getServerEnv()` como prop para um Client Component (vai no HTML/RSC); com build e sem o valor da chave, só avisava (R2-APP-05).
**Decisão:** nomes de segredo sem diferenciar maiúsculas em `src/` e `next.config.*`; `next.config` sem bloco `env`; `env.server.ts` só importado por `admin.ts`, e `admin.ts` só por `*.server.ts` com `import "server-only"`; valor da chave procurado em todo o `.next` (sem `cache`), e nomes das variáveis secretas em `.next/static`; em CI (`CI=true`), build sem o valor da chave para comparar é erro. Autoteste em `scripts/__tests__/check-secrets.test.mjs` (os dois vazamentos do revisor e as outras regras). O HTML e o RSC servidos de verdade (sem login e com cada papel) são varridos no E2E (`e2e/segredos.spec.ts`).
**Por quê:** o critério 7 fala do build; a parte estática pega o erro antes do build e o E2E pega o que só aparece renderizado.

---

## Correções da revisão final da Fase 1 (21/10/2026)

### D72 · Início offline pelo relógio do aparelho
**Contexto:** `start_attempt` não recebia o horário do aparelho, então `started_at` era a hora em que a fila offline chegou ao servidor. Foto com EXIF tirada offline mais de 10 min antes da sincronização caía em `photo_before_start` (D49) e o envio, em `photo_required`: o trabalho feito sem internet se perdia (R3-REGRAS-01).
**Decisão:** `start_attempt(p_task_id, p_client_mutation_id, p_started_at_device default null)` grava `task_attempts.started_at_device`, limitado pelo servidor: nunca antes do início da janela (ou da criação da tarefa), nem antes do fim da tentativa anterior (envio, revisão ou encerramento), nem depois de agora (`CHECK started_at_device <= started_at`). `register_evidence` compara o EXIF com `coalesce(started_at_device, started_at)` − 10 min. `started_at` continua sendo a hora do servidor para todo o resto. `clock_skew` continua medindo captura × recebimento no servidor (o PDF pede mostrar as duas datas quando divergem > 10 min); numa sincronização offline ele é esperado, e a tela da Fase 3/4 mostra as duas datas. O cliente offline (Fase 3) **deve** enviar o horário do início, como já faz com as respostas (D56).
**Por quê:** só o aparelho sabe quando a pessoa abriu a tarefa; os limites impedem usar o horário do aparelho para aceitar foto de antes da janela.

### D73 · "1ª tentativa" = 1º envio
**Contexto:** a tentativa encerrada sem envio (D52) continua numerada; a tarefa aprovada no único envio de quem a recebeu contava como "não aprovada na 1ª tentativa" (R3-REGRAS-02).
**Decisão:** em `kpi_summary`, aprovada na 1ª tentativa = a tentativa aprovada é a primeira **enviada** da tarefa (nenhuma tentativa enviada com número menor). `attempt_number` continua sendo a numeração do histórico.
**Por quê:** PRODUCT.md §7 define tentativa como "cada execução enviada"; a passagem da tarefa não pode baixar a qualidade da loja nem de quem socorreu.

### D74 · Falha da tarefa vencida fica com quem a tinha no prazo
**Contexto:** com a D52, reatribuir depois do prazo encerrava a tentativa de quem executava no prazo, e `private.task_person` ignorava tentativa encerrada: a atrasada ia para "Sem responsável" (equipe) ou para quem a recebeu já vencida e a iniciou (R3-REGRAS-08, reabrindo o R2-REGRAS-04).
**Decisão:** `private.task_person`: aprovada = quem executou a tentativa aprovada; vencida e não aprovada = quem estava com a tarefa **no prazo** (tentativa iniciada até o prazo e não encerrada antes dele, mesmo que encerrada depois numa passagem; sem ela, o responsável no prazo, `assignee_at_due`, ou o atual); ainda no prazo = como antes (última tentativa não encerrada, senão o responsável). A assinatura não mudou (lê status e prazo da própria tarefa).
**Por quê:** cumpre a D46 ("a falha não muda de pessoa") sem nova coluna; a D52 vale para a passagem a tempo.

### D75 · Itens do snapshot: linhagem fixa e mudanças auditadas
**Contexto:** com a tarefa gerada ainda pendente, o gerente apagava o item crítico que veio da rotina, reescrevia o texto dele ou incluía itens, sem nenhum registro (R3-REGRAS-03); a D48 só fixava crítico, foto e peso.
**Decisão:** item com linhagem (`template_item_id`) não sai da tarefa e tem também o **texto** da rotina (`invalid_snapshot`, 23514); incluir, alterar e remover item pela API (usuário logado) vai para o `audit_log` (`task_items`, modo `by_user`; a geração pelo sistema não é registrada linha a linha). Item sem linhagem continua livre (incluir e tirar), e reordenar continua permitido. O admin não lê esses registros (D24).
**Por quê:** o snapshot é da rotina; outro checklist = editar a rotina (auditada, sobe a versão) ou tarefa avulsa. O resto fica rastreável.

### D76 · Quantidade limitada nas portas do audit_log
**Contexto:** a D38 limitou o tamanho, não a quantidade: um POST em lote em `data_requests` gravava N pedidos e N linhas permanentes no `audit_log`; `log_event('export')` não tinha limite (R3-FUNCOES-01).
**Decisão:** índice único parcial `data_requests_one_open_per_kind (profile_id, kind) where status in ('open','in_progress')`: um pedido em andamento por tipo (o lote inteiro falha com 23505; a tela da Fase 7 traduz para "Você já tem um pedido em andamento"). `log_event`: no máximo 10 exportações por minuto e 200 por dia por pessoa (trava por pessoa); acima disso, `rate_limited` (P0001) e a exportação não acontece (o Route Handler da Fase 5 registra antes de exportar).
**Por quê:** o titular nunca precisa de dois pedidos iguais abertos (o texto tem 4.000 caracteres); recusar é melhor que deixar exportação sem registro.

### D77 · Storage sem leitura direta: URL assinada só no servidor
**Contexto:** as policies de SELECT em `storage.objects` deixavam o próprio usuário assinar URLs (`createSignedUrl(path, expiresIn)`) com o prazo que quisesse, válidas depois de o vínculo acabar (R3-ISOLAMENTO-01). O PDF pede leitura só por signed URL de até 5 min gerada no servidor.
**Decisão:** sem policy de SELECT (nem UPDATE/DELETE) em `storage.objects` para `authenticated`; só INSERT (upload sem upsert só precisa dele). O servidor confere `public.can_read_evidence(path)` / `public.can_read_reference(path)` com o cliente do usuário (mesma regra de antes) e assina com a chave secreta por no máximo 300 s (`src/lib/storage/signed-url.server.ts`; prazo validado em `signed-url.ts`, com teste). Vale para fotos de evidência e imagens de referência.
**Por quê:** o prazo e a conferência ficam no servidor; o upload continua direto do aparelho. Se o storage-api real exigir SELECT no upload, a CI da Fase 3 (`supabase start`) acusa e a policy volta limitada à tentativa aberta do próprio executor (que já tem o arquivo).

### D78 · Canal do titular aberto a quem saiu
**Contexto:** `data_requests_insert_own` exigia `current_org_id()`, nula sem vínculo vigente ou com perfil inativo: justamente quem saiu (D37) não pedia correção nem exportação (R3-ISOLAMENTO-02).
**Decisão:** a policy usa `private.home_org_id()`: a organização de qualquer vínculo que a pessoa teve (vigente, futuro ou encerrado), com qualquer situação do perfil (uma pessoa, uma organização, D21; mais de uma = nula). Continua em nome próprio, só `open`, e um por tipo (D76). Não devolve acesso a mais nada. A tela "Meus dados" para quem saiu entra com o canal do titular da Fase 7 (o app hoje desconecta quem não tem vínculo).
**Por quê:** LGPD art. 18 vale depois do desligamento; o banco já deixa, a tela vem depois.

### D79 · Login de admin registrado pelo Auth
**Contexto:** o `admin_login` só era gravado quando o login passava pela Server Action do app; um login direto na API pública do Auth (com a chave publicável) não deixava rastro (R3-APP-05). A D64 já dizia que regra só no app não é controle.
**Decisão:** hook Custom Access Token do Auth (`[auth.hook.custom_access_token]`, `pg-functions://postgres/private/custom_access_token_hook`; na stack local pelo auth-env.mjs): todo token emitido que não seja renovação, para quem tem vínculo de admin vigente com perfil ativo, grava `admin_login` com o método (`password`, `recovery`...), no máximo um por admin por minuto. A função não muda as claims, nunca levanta erro (falha vira aviso no log) e só `supabase_auth_admin` a executa. `log_admin_login` (servidor) passa a gravar só o contexto: `admin_login_context` com ip confiável (D68) e user_agent.
**Por quê:** o registro sai da camada que todo login atravessa. No hospedado, o hook é ligado pelo `supabase config push` (ou no painel: Authentication → Hooks).

### D80 · E-mail de recuperação em pt-BR e erro de "outro navegador"
**Contexto:** o e-mail de recuperação era o padrão do Auth, em inglês e com um código de 6 dígitos que o app não aceita; o link aberto em outro navegador dizia "O link expirou ou já foi usado" (R3-CRITERIOS-01). O `config.toml` levava `max_frequency = "1s"` para o hospedado (R3-APP-06).
**Decisão:** modelo `supabase/templates/recuperacao.html` (`[auth.email.template.recovery]`, assunto "Crie uma nova senha do Éde Gestão"), só com o link e dizendo que ele vale por 1 h, uma vez, no mesmo aparelho e navegador do pedido. Em `/auth/confirm`, falta ou divergência do `code_verifier` (`pkce_code_verifier_not_found`, `bad_code_verifier`, `flow_state_not_found`) vai para `/login?erro=outro-navegador`, com o texto certo; o resto continua "expirou ou já foi usado". `max_frequency = "60s"` no `config.toml` (local: 1 s, pelo auth-env.mjs, para o E2E).
**Por quê:** é a parte do D62 que dá para entregar sem o fluxo de dois passos, que fica para a Fase 7 (risco R3-05).

### D81 · Encerramento e revisão pelo relógio real
**Contexto:** `abandoned_at` usava `now()` (início da transação): uma reatribuição numa transação que começou antes de a tentativa ser iniciada (PATCH em lote que esperou trava, Server Action com vários comandos) falhava inteira no CHECK `task_attempts_abandoned_after_start` (R3-FUNCOES-03).
**Decisão:** `abandoned_at = clock_timestamp()` em `release_stale_attempt` e no gatilho de guarda; `review_attempt` grava `reviewed_at = clock_timestamp()` (a revisão nunca fica antes do envio). Cenário de concorrência em `scripts/db/concorrencia/passagem-em-transacao-antiga.sql`.
**Por quê:** o CHECK continua valendo e a passagem não depende da ordem das transações.

### D82 · Passagem também na mudança de setor, vínculo ou perfil
**Contexto:** quem mudava de setor (tarefa de equipe), tinha o vínculo encerrado agora ou o perfil desativado continuava com a tentativa aberta, contando nos indicadores, e ainda enviava fotos ao bucket (a policy de upload não conferia `can_execute_task`) (R3-ISOLAMENTO-03).
**Decisão:** gatilhos `AFTER UPDATE OF sector_id, starts_at, ends_at OR DELETE` em `memberships` e `AFTER UPDATE OF status` (para inativo) em `profiles` chamam `private.release_stale_attempt` para cada tentativa aberta da pessoa (trava tarefa → tentativa). Fim agendado (ends_at no futuro) não muda nada agora (R3-02). `private.can_insert_evidence_object` exige `can_execute_task`, a mesma regra das RPCs.
**Por quê:** são eventos imediatos; o gatilho dispara na hora certa, sem esperar outra pessoa iniciar.

### D83 · Reenvio do envio para quem não executa mais
**Contexto:** reenviar `submit_attempt` devolvia o status atual da tarefa a quem já não podia lê-la (R3-ISOLAMENTO-04).
**Decisão:** reenvio de tentativa já enviada: quem ainda executa a tarefa recebe o status atual (fila offline idempotente); quem não executa mais recebe só o resultado da própria tentativa (`approved`/`rejected` da revisão dela, ou `submitted`).
**Por quê:** a pessoa continua sabendo o que aconteceu com o que ela enviou, e nada além.

### D84 · Slug da organização fixo pela API
**Contexto:** trocar o próprio slug pelo de outra organização respondia 23505 e revelava que ela existe (R3-ISOLAMENTO-05).
**Decisão:** `authenticated` não tem mais UPDATE em `organizations.slug`; o admin altera nome e retenção de fotos. O slug é definido por quem cria a organização (chave secreta).
**Por quê:** o slug não aparece para o usuário; não precisa mudar pela API.

### D85 · Notificação de tarefa leva a loja da tarefa
**Contexto:** `notifications.store_id` (que a RLS usa para cortar quem saiu da loja) não era amarrado à loja da tarefa (R3-ISOLAMENTO-06).
**Decisão:** `CHECK (task_id is null or store_id is not null)` e FK composta `(task_id, store_id) → tasks (id, store_id)`. Notificação sem tarefa (resumo, rede) continua com loja opcional. O gerador da Fase 6 grava a loja da tarefa.
**Por quê:** integridade no banco, antes de o gerador existir.

### D86 · Responsável = colaborador ativo da loja
**Contexto:** tarefa e agendamento aceitavam como responsável qualquer pessoa com vínculo na loja (gerente, proprietária) ou perfil inativo; ninguém conseguia iniciar e a tarefa vencia (R3-REGRAS-05).
**Decisão:** `private.can_be_assignee`: vínculo de colaborador não encerrado na loja e perfil ativo (`invalid_assignee`, 23514), em tarefas e agendamentos; `private.instantiate_task` manda para a equipe do setor quando o responsável fixo não atende mais (D42).
**Por quê:** só o colaborador executa (`start_attempt`); com responsável preenchido, a equipe do setor não pode iniciar.

### D87 · Fuso da loja só IANA
**Contexto:** `stores.timezone` aceitava `UTC-3`, `GMT-3`, `-03` e `Etc/GMT-3`, que o Postgres entende com o sinal invertido (UTC+3): todo "dia local da loja" andava 6 h (R3-REGRAS-04).
**Decisão:** `private.is_valid_timezone` aceita só nomes `Região/Cidade` que existem em `pg_timezone_names`, fora `Etc/`, `posix/`, `right/` e abreviações. Mudanças de fuso continuam no `audit_log` (`stores`).
**Por quê:** as lojas usam fusos do Brasil (America/Sao_Paulo, Manaus...); não há motivo para aceitar especificação POSIX.

### D88 · Reenvio antigo de resposta depois do envio
**Contexto:** o reenvio atrasado de uma resposta que já valeu e foi corrigida devolvia `false` com a tentativa aberta, mas virava `attempt_closed` depois do envio (R3-REGRAS-06).
**Decisão:** `answer_item` aplica "mais antigo que a resposta gravada → `false`" antes da conferência de estado. Resposta nova numa tentativa enviada continua `attempt_closed`.
**Por quê:** um reenvio que não muda nada não deve virar erro na fila offline.

### D89 · Exclusões do proxy ancoradas
**Contexto:** o `matcher` excluía `_next/image` sem âncora: `/_next/imagex`, `/_next/image-foo/bar` etc. pulavam o proxy e o 404 em HTML saía sem CSP (R3-APP-07).
**Decisão:** `"/((?!_next/static/|_next/image$|icon\\.svg$).*)"`; o E2E de cabeçalhos cobre esses caminhos.
**Por quê:** só arquivos que existem ficam fora do proxy (D69).

### D90 · Leitura do admin: hoje só tarefas
**Contexto:** a matriz do §6 marcava "L†" (leitura auditada) para o admin em 11 tabelas operacionais, mas só existe `admin_read_tasks` (R3-CRITERIOS-02).
**Decisão:** a matriz passa a dizer o que existe: tarefas por `admin_read_tasks`; nas demais tabelas operacionais, o admin não lê. As leituras de suporte (detalhe da tarefa, fotos com URL assinada, rotinas, agendamentos, planos), todas auditadas, entram com a tela de administração da Fase 7.
**Por quê:** menos acesso é a direção segura; o documento não pode prometer o que não existe.

### D91 · zod também no cliente
**Contexto:** os formulários de login, recuperação e nova senha mandavam toda entrada à Server Action; zod só rodava no servidor (R3-CRITERIOS-04), e o PDF pede "zod em todo input (cliente e servidor)".
**Decisão:** os três formulários validam no `onSubmit` com os mesmos esquemas (`validateFormFields`, `useClientValidation`) e não enviam quando a entrada é inválida; o servidor valida de novo sempre. zod roda sem o modo JIT (`z.config({ jitless: true })`), porque o JIT testa `new Function` e a CSP não tem `unsafe-eval`.
**Por quê:** erro na hora, sem ida ao servidor, com o mesmo texto; vale também para os formulários offline da Fase 3.

## Riscos aceitos e adiados

| Id | Risco | Por que foi aceito ou adiado | Fase que trata |
|---|---|---|---|
| R3-01 (D56) | Duas pessoas/aparelhos com relógios divergentes na mesma tentativa: a resposta do aparelho com relógio atrasado pode ser ignorada como "mais antiga". | A tentativa é de uma pessoa só (normalmente um aparelho); o horário do aparelho é limitado ao do servidor e `answer_item` devolve `false`, então o app consegue mostrar a resposta que ficou. | Fase 3 (fila offline: aviso de conflito "o servidor vence") |
| R3-02 (D52, D82) | Só para vínculo com **fim agendado** (`ends_at` no futuro): quando a data chega, a tentativa aberta da pessoa continua aberta (e contando para ela) até outra pessoa iniciar a tarefa. Troca de setor, fim imediato, remoção do vínculo e desativação já encerram na hora (D82). | Um gatilho não dispara quando o horário de `ends_at` passa; precisa de job. | Fase 4 (job de atrasadas também encerra tentativas de quem saiu) |
| R3-03 (D52) | Depois da passagem, a tarefa fica `in_progress` sem tentativa aberta até o novo responsável iniciar. | Mudar a máquina de estados (`in_progress → pending`) mexeria em transições já testadas; o estado é coerente (a tarefa está em execução, só trocou de mãos). | Fase 2/4 (telas mostram "aguardando o novo responsável" a partir de `abandoned_at`) |
| R3-APP-01 (D67; R2-APP-02, R2-APP-08, R2-APP-09) | Direto no Auth, com a chave publicável (pública), ainda dá para saber se um e-mail tem conta: `/otp` responde `otp_disabled` para e-mail desconhecido e `email_provider_disabled` para cadastrado; o login por senha (`/token`) demora mais para conta existente (só ela passa pelo bcrypt) e responde `user_banned` antes de conferir a senha. | É comportamento do GoTrue v2.180, sem opção para mudar. As respostas do **app** são iguais (texto e tempo) e o *magic link* está desligado (não sai e-mail de login). O controle para chamadas diretas é o captcha do Auth (`[auth.captcha]`, Turnstile ou hCaptcha), que exige provedor externo, script de terceiro (CSP) e segredo: entra junto com o rate limit. No hospedado, conferir se o *magic link* pode ser desligado (não há chave no `config.toml` da CLI); sem isso, o captcha cobre. | Fase 7 (captcha no Auth + `captchaToken` no login e na recuperação) |
| R3-APP-02 (D64; R2-APP-03) | Nas primeiras 24 h depois do login, um token de acesso roubado ainda troca a senha direto no Auth (`PUT /user`), sem a senha atual. | O GoTrue só oferece "reautenticar depois de 24 h" (`secure_password_change`); não há opção de exigir a senha atual. Mitigado: cookie HttpOnly (o token não sai por script injetado), aviso por e-mail a cada troca e token de 10 min. | Fase 7 (revisão de segurança: MFA ou reautenticação com código para troca de senha) |
| R3-APP-03 (D66; R2-APP-12) | Depois de "Sair" ou da troca de senha, o token de acesso já emitido continua lendo a API (PostgREST, storage) por até 10 min. O refresh token é revogado na hora e o app (proxy) já recusa a sessão. | Conferir `auth.sessions` em toda policy mexe em todos os helpers de acesso e não cobre o storage-api; o `db-pre-request` do PostgREST cobre só a REST. | Fase 7 (`db-pre-request` conferindo `session_id` em `auth.sessions`, e avaliar o mesmo nos helpers usados pelo storage) |
| R2-APP-07 | Sem limite de tentativas no login e na recuperação na camada do app (60 tentativas em ~1 s localmente). **Em produção** o login e a recuperação rodam em Server Actions: o Auth vê o ip do servidor (Vercel) para todo mundo, então os limites por ip do Auth (`sign_in_sign_ups` 30 por 5 min) viram um balde só da empresa: 30 senhas erradas de qualquer pessoa bloqueiam o login de todos. `email_sent` (2 por hora no hospedado sem SMTP próprio) também é do projeto inteiro. | Já é entregável da Fase 7 ("rate limit no login"). Desenho: limite no app por e-mail normalizado + ip do cliente de fonte confiável (D68), contado no Postgres por uma RPC `SECURITY DEFINER` (tabela de tentativas com espera crescente, limpeza por `pg_cron`), sem dependência nova; os limites do Auth no hospedado ficam altos o bastante para não serem o gargalo compartilhado; SMTP próprio (Resend) com `email_sent` realista; captcha (R3-APP-01). | Fase 7 (limite no app) e Fase 6 (SMTP próprio) |
| R2-ISO-08 (D51) | `Prefer: count=planned/estimated` do PostgREST devolve a estimativa do planejador, baseada na tabela inteira. | Não reproduzido como vazamento; com uma organização, o volume das outras lojas não é sensível; o app não usa essas contagens. | Fase 7 (`db-pre-request` recusando esses cabeçalhos, se virar requisito) |
| R2-FUNC-07 (D40) | O arquivo no bucket `evidences` pode ser apagado antes do prazo de retenção por quem tem a chave secreta. | Gatilho em `storage.objects` (tabela do serviço de storage) arrisca a compatibilidade com o storage-api hospedado; o registro da evidência continua imutável. | Fase 7 (job de retenção é o único uso da chave secreta para isso) |
| R2-FUNC-01 | Um admin pode dar vínculo de gerente a outra conta que ele controla e ler a operação sem `admin_read_*`. | Fechar exige fluxo de produto (aprovação ou aviso à proprietária quando um admin cria vínculo de gerente). | Fases 6–7 (notificação à proprietária e revisão da administração) |
| R1-ISO-10 (D17, D32, D77) | Policies de storage testadas só em SQL: listagem, cópia, movimentação, upsert e signed URL do storage-api real não são exercitados (sem Docker aqui, `/storage/v1` responde 501). Em especial, a D77 supõe que o upload sem upsert só precisa de INSERT (sem SELECT). | Não há como rodar o storage-api neste ambiente. | Fase 3 (suíte e teste HTTP de isolamento no CI com `supabase start`; se o upload pedir SELECT, policy limitada à tentativa aberta do próprio executor) |
| R3-04 (D49, D72) | Celular com relógio mais de 10 min atrasado tem a foto recusada (`photo_before_start`), online ou offline. | A tolerância de 10 min é o limite de `clock_skew`; sem ela, foto antiga passaria. A mensagem pede para conferir a data e a hora do celular. | Fase 3 (a tela compara o relógio do aparelho com o do servidor ao sincronizar e avisa antes da foto) |
| R3-05 (D62, D80; R3-APP-06) | O link de recuperação só funciona no navegador que o pediu (PKCE) e uma vez. Um terceiro que pede "Esqueci minha senha" para o e-mail de outra pessoa invalida o link que ela já tem (o Auth guarda um token por usuário), e o link novo que ela recebe não funciona no navegador dela: dá para atrapalhar a recuperação de alguém pedindo links seguidos. Também não funciona se o link for aberto em outro aparelho, no app instalado (iOS) ou se um antivírus de e-mail abrir o link antes. | O fluxo de dois passos com `{{ .TokenHash }}` (GET mostra "Continuar", Server Action valida) muda o desenho da D62 e precisa de tela e testes próprios. Mitigado: o e-mail e a tela dizem que o link vale no mesmo aparelho e navegador (D80) e o `max_frequency` do hospedado é 60 s. | Fase 7 (fluxo de dois passos + limite de pedidos por e-mail no rate limit) |
| R3-06 (D63) | Offline por mais de 7 dias, o cookie da sessão vence e a pessoa precisa entrar de novo antes de a fila sincronizar. | A sessão de 7 dias é a política de segurança (D63); a fila continua guardada no IndexedDB. | Fase 3 (aviso "entre para enviar N envios guardados" e teste E2E) |
| R3-07 (D58) | Janela de agendamento que atravessa a meia-noite não é suportada. | Nenhuma rotina das lojas atravessa a meia-noite hoje; o CHECK recusa e o gerente vê o erro ao salvar. | Fase 4 (duração em vez de hora final, se a operação pedir) |
| R3-08 (D78) | Quem saiu ou foi desativado já pode abrir pedido do titular pelo banco, mas o app ainda não tem a tela: o guarda do app desconecta quem não tem vínculo. | A tela "Meus dados" faz parte do canal do titular (LGPD), entregável da Fase 7. | Fase 7 (página "Meus dados" acessível sem vínculo vigente) |
| R3-FUNCOES-02 (D41) | A chave secreta (service_role) ainda **acrescenta** histórico a tarefa, tentativa ou revisão fechada: marcação em revisão gravada, foto depois do envio, tentativa nova em tarefa aprovada, revisão de tentativa encerrada sem envio, status levado a `approved` sem envio; e `cancel_task` deixa aberta a tentativa da tarefa cancelada. Nada disso vai para o `audit_log`. | Hoje a chave secreta só grava `log_admin_login` e assina URLs do storage; guardas de INSERT em quatro tabelas mexem nas fixtures e no caminho de restauração (D44) e pedem desenho junto com quem passará a usar a chave. | Fase 4 (job de retenção e Server Actions: guardas `BEFORE INSERT` em `task_attempts`, `evidences`, `reviews`, `review_item_flags`, pré-condições no `enforce_task_status` e encerramento da tentativa no cancelamento) |
| R3-FUNCOES-04 (D44) | Em `session_replication_role = replica`, os gatilhos de auditoria e de integridade (validações, última proprietária, versão da rotina, passagem da tarefa) não disparam: uma importação ou script nesse modo altera cadastro sem trilha. | Só o dono das tabelas entra nesse modo, e ele também pode desligar gatilhos com `ALTER TABLE` (DDL explícito). Tornar todos `ENABLE ALWAYS` com exceção de restauração exige rever cada gatilho. | Fase 8 (roteiro de restauração em `docs/backup.md`; avaliar `ENABLE ALWAYS` nos gatilhos de auditoria) |
| R3-REGRAS-07 (D13) | A nota ponderada, "% aprovadas na janela" e a adoção contam como 0 a tarefa que ainda está no prazo: no painel do dia, a loja com prazos mais tarde parece pior ao meio-dia. | É definição de indicador (D13); a escolha ("só o que já venceu" ou "até agora", e coluna "em aberto") depende do desenho do painel. Hoje a comparação é justa para períodos fechados. | Fase 5 (painel: período fechado por padrão ou nota só sobre tarefas decididas, com "em aberto" ao lado) |
| R3-09 (D90) | O admin (suporte) só lê tarefas (`admin_read_tasks`); itens, tentativas, respostas, fotos, revisões, rotinas, agendamentos e planos não têm leitura auditada para ele. | Menos acesso é a direção segura; a leitura de suporte depende das telas de administração. | Fase 7 (funções `admin_read_*` auditadas, com URL assinada no servidor para fotos) |
| R3-FUNCOES-01b (D76) | Fotos (`evidences`, permanentes) não têm cota por tentativa: o executor de uma tentativa aberta registra quantas quiser (cada uma exige arquivo no bucket e sha256 novo). | O tamanho já é limitado pelo bucket (5 MB) e cada foto precisa de upload real; a cota depende do desenho da tela de câmera. | Fase 3 (cota de fotos por item/tentativa na RPC) |
