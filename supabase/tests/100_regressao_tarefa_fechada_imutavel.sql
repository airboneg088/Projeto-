-- =============================================================================
-- 100 · Regressão R1-FI-05 e R1-REGRAS-01: o gerente não reescreve tarefa
-- aprovada ou cancelada nem move prazo vencido, então não infla indicadores
-- depois do fato; as edições permitidas ficam no audit_log.
--   - approved/cancelled: nenhuma coluna muda (task_closed);
--   - prazo/janela: só em pending/in_progress/rejected, antes de vencer e nunca
--     para o passado (deadline_locked);
--   - edição de título, instruções, imagem, prioridade, responsável, janela ou
--     prazo é auditada (update em tasks).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(15);

select tests.create_base_fixture();

-- Tarefa com prazo vencido há 10 min (janela começou há 2 h); o envio chega atrasado
insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at)
values (tests.fx('late'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Abertura',
        tests.fx('staff_p1'), now() - interval '2 hours', now() - interval '10 minutes');
insert into public.task_items (id, task_id, position, text) values (tests.fx('late:i1'), tests.fx('late'), 1, 'Item');

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('late'), gen_random_uuid());
select public.answer_item(tests.attempt_of('late', 1), tests.fx('late:i1'), true);
select public.submit_attempt(tests.attempt_of('late', 1));
select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('late', 1), 'approved');

select is(
  (select pct_aprovadas_na_janela from public.kpi_summary(
     ((now() at time zone 'America/Sao_Paulo')::date - 1), ((now() at time zone 'America/Sao_Paulo')::date + 1),
     array[tests.fx('store_p')])),
  0.0::numeric, 'antes: aprovada fora da janela (0.0%)'
);

-- Tarefa aprovada ---------------------------------------------------------------
select is(
  tests.exec_result($$ update public.tasks set due_at = now() + interval '1 hour' where id = tests.fx('late') $$),
  'P0001:task_closed', 'gerente NÃO altera o prazo de tarefa aprovada');
select is(
  (select pct_aprovadas_na_janela from public.kpi_summary(
     ((now() at time zone 'America/Sao_Paulo')::date - 1), ((now() at time zone 'America/Sao_Paulo')::date + 1),
     array[tests.fx('store_p')])),
  0.0::numeric, 'depois: % na janela não é inflado retroativamente'
);
select is(
  tests.exec_result($$ update public.tasks set title = 'Outra coisa', assignee_id = tests.fx('staff_p2')
                    where id = tests.fx('late') $$),
  'P0001:task_closed', 'gerente NÃO reescreve título/responsável de tarefa aprovada');

-- Tarefa cancelada --------------------------------------------------------------
select tests.reset_role();
select tests.create_task('canc', 'store_p', 'sector_p1', 'staff_p1');
select tests.authenticate_as('manager_p');
select public.cancel_task(tests.fx('canc'), 'Loja fechada');
select is(
  tests.exec_result($$ update public.tasks set title = 'Nunca existiu', due_at = now() + interval '9 days'
                    where id = tests.fx('canc') $$),
  'P0001:task_closed', 'gerente NÃO reescreve tarefa cancelada');

-- Prazo vencido / enviada: o prazo não se move ----------------------------------------
select tests.reset_role();
insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at)
values (tests.fx('atrasada'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Caixa',
        tests.fx('staff_p1'), now() - interval '3 hours', now() - interval '1 hour');
select tests.walk(tests.fx('atrasada'), 'overdue');
select tests.create_task('enviada', 'store_p', 'sector_p1', 'staff_p1');
select tests.walk(tests.fx('enviada'), 'in_progress', 'submitted');
select tests.create_task('pendente', 'store_p', 'sector_p1', 'staff_p1');

select tests.authenticate_as('manager_p');
select is(
  tests.exec_result($$ update public.tasks set due_at = now() + interval '2 hours' where id = tests.fx('atrasada') $$),
  'P0001:deadline_locked', 'gerente NÃO empurra o prazo de tarefa atrasada (esconderia o atraso)');
select is(
  tests.exec_result($$ update public.tasks set due_at = now() + interval '2 days' where id = tests.fx('enviada') $$),
  'P0001:deadline_locked', 'gerente NÃO move o prazo de tarefa aguardando aprovação');
select is(
  tests.exec_result($$ update public.tasks set due_at = now() - interval '1 minute' where id = tests.fx('pendente') $$),
  'P0001:deadline_locked', 'gerente NÃO põe prazo no passado');
select is(
  tests.exec_result($$ update public.tasks set assignee_id = tests.fx('staff_p2') where id = tests.fx('atrasada') $$),
  'ok', 'tarefa atrasada ainda pode ser reatribuída (fica auditado)');

-- Edição permitida: tarefa pendente, antes do prazo -----------------------------------
select is(
  tests.exec_result($$ update public.tasks set due_at = due_at + interval '1 hour', title = 'Pendente ajustada'
                    where id = tests.fx('pendente') $$),
  'ok', 'gerente ajusta prazo e título de tarefa pendente antes de vencer');

select tests.reset_role();
select results_eq(
  $$ select title, due_at < now() from public.tasks where id = tests.fx('late') $$,
  $$ values ('Abertura'::text, true) $$,
  'tarefa aprovada intacta (título e prazo)'
);
select results_eq(
  $$ select actor_id, action, diff ? 'due_at', diff ? 'title', diff ? 'status'
     from public.audit_log where table_name = 'tasks' and record_id = tests.fx('pendente')::text $$,
  $$ values (tests.fx('manager_p'), 'update'::text, true, true, false) $$,
  'edição de prazo e título fica no audit_log (só as colunas alteradas)'
);
select results_eq(
  $$ select actor_id, diff -> 'assignee_id' ->> 'new'
     from public.audit_log where table_name = 'tasks' and record_id = tests.fx('atrasada')::text $$,
  format($$ values (%L::uuid, %L::text) $$, tests.fx('manager_p'), tests.fx('staff_p2')),
  'reatribuição fica no audit_log'
);
select is(
  (select count(*) from public.audit_log where table_name = 'tasks' and record_id = tests.fx('late')::text),
  0::bigint,
  'nenhuma edição da tarefa aprovada foi gravada (todas recusadas)'
);
select is(
  (select count(*) from public.audit_log
   where table_name = 'tasks' and record_id = tests.fx('canc')::text and action = 'task_cancelled'),
  1::bigint,
  'o cancelamento continua auditado'
);

select * from finish();
rollback;
