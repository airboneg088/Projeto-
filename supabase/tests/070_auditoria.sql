-- =============================================================================
-- 070 · Auditoria
-- Mudança de vínculo, cancelamento de tarefa, edição de rotina e mudança de
-- situação de pessoa geram registro com o autor e a ação certos; leitura do
-- admin é auditada; regras do log_event; ninguém insere direto no audit_log.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(35);

select tests.create_base_fixture();
select tests.create_task('t_cancelar', 'store_p', 'sector_p1', 'staff_p1');

insert into public.task_templates (id, organization_id, store_id, title, weight)
values (tests.fx('tpl_p'), tests.fx('org_a'), tests.fx('store_p'), 'Rotina da loja P', 2);
insert into public.template_items (id, template_id, position, text)
values (tests.fx('tpl_p_i1'), tests.fx('tpl_p'), 1, 'Item original');

-- Alterações feitas pelo sistema (sem JWT) ficam sem autor
select is(
  (select actor_id from public.audit_log where table_name = 'task_templates' and record_id = tests.fx('tpl_p')::text and action = 'insert'),
  null::uuid,
  'gravação do sistema (sem usuário logado) fica com actor_id nulo'
);

-- Vínculo: proprietária encerra; admin abre outro (transferência) -------------
select tests.authenticate_as('owner_a');
select is(tests.affected_rows($$ update public.memberships set ends_at = now() where id = tests.fx('m_staff_p2') $$), 1,
  'proprietária encerra o vínculo do colaborador P2');

select tests.authenticate_as('admin_a');
select lives_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
     values (tests.fx('staff_p2'), tests.fx('org_a'), tests.fx('store_c'), tests.fx('sector_c1'), 'staff', now()) $$,
  'admin abre o novo vínculo na loja C (transferência)'
);
select throws_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, role)
     values (tests.fx('staff_c1'), tests.fx('org_a'), null, 'owner') $$,
  '42501', null, 'admin não cria vínculo de proprietária'
);

select tests.reset_role();
select results_eq(
  $$ select actor_id, action, organization_id, diff -> 'ends_at' -> 'old', diff ? 'ends_at', diff ? 'updated_at'
     from public.audit_log where table_name = 'memberships' and record_id = tests.fx('m_staff_p2')::text and action = 'update' $$,
  $$ values (tests.fx('owner_a'), 'update'::text, tests.fx('org_a'), 'null'::jsonb, true, false) $$,
  'encerramento do vínculo auditado: autor, ação, organização e só as colunas alteradas'
);
select results_eq(
  $$ select actor_id, action, diff -> 'store_id' ->> 'new', diff -> 'role' ->> 'new'
     from public.audit_log
     where table_name = 'memberships' and action = 'insert'
       and diff -> 'profile_id' ->> 'new' = tests.fx('staff_p2')::text
       and diff -> 'store_id' ->> 'new' = tests.fx('store_c')::text $$,
  $$ values (tests.fx('admin_a'), 'insert'::text, tests.fx('store_c')::text, 'staff'::text) $$,
  'novo vínculo auditado como insert pelo admin'
);

-- Cancelamento de tarefa ------------------------------------------------------
select tests.authenticate_as('manager_p');
select public.cancel_task(tests.fx('t_cancelar'), 'Fornecedor não entregou');
select tests.reset_role();
select results_eq(
  $$ select actor_id, action, table_name, diff -> 'status' ->> 'old', diff -> 'status' ->> 'new', diff -> 'cancel_reason' ->> 'new'
     from public.audit_log where record_id = tests.fx('t_cancelar')::text $$,
  $$ values (tests.fx('manager_p'), 'task_cancelled'::text, 'tasks'::text, 'pending'::text, 'cancelled'::text, 'Fornecedor não entregou'::text) $$,
  'cancelamento auditado (task_cancelled) com autor, status e motivo'
);
select is(
  (select count(*) from public.audit_log where table_name = 'tasks' and action <> 'task_cancelled'),
  0::bigint,
  'outras mudanças em tasks não poluem a auditoria'
);

-- Edição de rotina ------------------------------------------------------------
-- (rotina já usada numa tarefa: a edição sobe a versão; antes do 1º uso ela está em montagem)
select ok(private.instantiate_task(tests.fx('tpl_p'), tests.fx('store_p'), tests.fx('sector_p1'), null,
                                   now() + interval '60 days', now() + interval '61 days') is not null,
  'tarefa gerada da rotina (a rotina sai da montagem)');
select tests.authenticate_as('manager_p');
select is(tests.affected_rows($$ update public.task_templates set title = 'Rotina revisada' where id = tests.fx('tpl_p') $$), 1,
  'gerente edita a rotina da sua loja');
select is(tests.affected_rows($$ update public.template_items set text = 'Item revisado' where id = tests.fx('tpl_p_i1') $$), 1,
  'gerente edita item da rotina');
select tests.reset_role();
select results_eq(
  $$ select actor_id, action, array(select jsonb_object_keys(diff) order by 1), diff -> 'title' ->> 'new'
     from public.audit_log
     where table_name = 'task_templates' and record_id = tests.fx('tpl_p')::text and action = 'update' and diff ? 'title' $$,
  $$ values (tests.fx('manager_p'), 'update'::text, array['title', 'version']::text[], 'Rotina revisada'::text) $$,
  'edição da rotina auditada só com as colunas alteradas (título e versão)'
);
select results_eq(
  $$ select actor_id, diff -> 'text' ->> 'old', diff -> 'text' ->> 'new', organization_id
     from public.audit_log where table_name = 'template_items' and record_id = tests.fx('tpl_p_i1')::text and action = 'update' $$,
  $$ values (tests.fx('manager_p'), 'Item original'::text, 'Item revisado'::text, tests.fx('org_a')) $$,
  'edição de item da rotina auditada com valor antigo e novo'
);

-- Situação da pessoa ----------------------------------------------------------
select tests.authenticate_as('admin_a');
select lives_ok($$ select public.set_profile_status(tests.fx('staff_p1'), 'inactive') $$, 'admin desativa uma pessoa');
select throws_ok($$ select public.set_profile_status(tests.fx('admin_a'), 'inactive') $$, 'P0001', 'forbidden',
  'admin não desativa a si mesmo');
select throws_ok($$ select public.set_profile_status(tests.fx('staff_b1'), 'inactive') $$, 'P0001', 'forbidden',
  'admin não mexe em pessoa de outra organização');
select tests.authenticate_as('manager_p');
select throws_ok($$ select public.set_profile_status(tests.fx('staff_p2'), 'inactive') $$, 'P0001', 'forbidden',
  'gerente não desativa pessoas');
select tests.reset_role();
select results_eq(
  $$ select actor_id, action, diff -> 'status' ->> 'old', diff -> 'status' ->> 'new', organization_id
     from public.audit_log where table_name = 'profiles' and record_id = tests.fx('staff_p1')::text $$,
  $$ values (tests.fx('admin_a'), 'profile_status_changed'::text, 'active'::text, 'inactive'::text, tests.fx('org_a')) $$,
  'mudança de situação auditada (profile_status_changed)'
);

-- Leitura do admin é auditada --------------------------------------------------
select tests.authenticate_as('admin_a');
select is(
  (select count(*) from public.admin_read_tasks(tests.fx('store_p'), (now() at time zone 'America/Sao_Paulo')::date - 7,
                                                (now() at time zone 'America/Sao_Paulo')::date + 7)),
  1::bigint,
  'admin_read_tasks devolve as tarefas da loja no período'
);
select is(tests.count_rows($$ select count(*) from public.tasks $$), 0::bigint, 'admin não lê tarefas direto');
select throws_ok($$ select * from public.admin_read_tasks(tests.fx('store_b'), '2026-01-01', '2026-12-31') $$, 'P0001', 'forbidden',
  'admin não lê loja de outra organização');
select tests.authenticate_as('manager_p');
select throws_ok($$ select * from public.admin_read_tasks(tests.fx('store_p'), '2026-01-01', '2026-12-31') $$, 'P0001', 'forbidden',
  'admin_read_tasks é só para admin');
select tests.reset_role();
select results_eq(
  $$ select actor_id, table_name, record_id, diff ->> 'store_id' from public.audit_log where action = 'admin_read' $$,
  format($$ values (%L::uuid, 'tasks'::text, %L::text, %L::text) $$, tests.fx('admin_a'), tests.fx('store_p'), tests.fx('store_p')),
  'cada leitura do admin grava admin_read no audit_log'
);

-- log_event --------------------------------------------------------------------
select tests.authenticate_as('admin_a');
select throws_ok($$ select public.log_event('admin_login', '{"ip": "127.0.0.1"}') $$, 'P0001', 'forbidden',
  'admin NÃO registra o próprio login pela API (só o servidor, com a chave secreta)');
select throws_ok($$ select public.log_admin_login(auth.uid(), '127.0.0.1', null) $$, '42501', null,
  'admin NÃO chama log_admin_login pela API');
select throws_ok($$ select public.log_event('export') $$, 'P0001', 'forbidden', 'admin não registra exportação');
select tests.authenticate_service_role();
select is(public.log_admin_login(tests.fx('admin_a'), '127.0.0.1', null), true,
  'o servidor (chave secreta) registra o login do admin');
select tests.authenticate_as('manager_p');
select throws_ok($$ select public.log_event('admin_login') $$, 'P0001', 'forbidden', 'gerente não registra login de admin');
select lives_ok($$ select public.log_event('export', '{"formato": "xlsx", "linhas": 120}') $$, 'gerente registra exportação');
select tests.authenticate_as('owner_a');
select lives_ok($$ select public.log_event('export', '{"formato": "csv"}') $$, 'proprietária registra exportação');
select throws_ok($$ select public.log_event('qualquer_coisa') $$, 'P0001', 'forbidden', 'evento fora da lista é recusado');
select tests.authenticate_as('staff_c1');
select throws_ok($$ select public.log_event('export') $$, 'P0001', 'forbidden', 'colaborador não registra exportação');

select tests.authenticate_as('owner_a');
select results_eq(
  $$ select action, actor_id, diff from public.audit_log where action in ('admin_login_context', 'export') order by id $$,
  format(
    $$ values ('admin_login_context'::text, %L::uuid, '{"ip": "127.0.0.1"}'::jsonb),
              ('export'::text, %L::uuid, '{"formato": "xlsx", "linhas": 120}'::jsonb),
              ('export'::text, %L::uuid, '{"formato": "csv"}'::jsonb) $$,
    tests.fx('admin_a'), tests.fx('manager_p'), tests.fx('owner_a')
  ),
  'proprietária lê os eventos auditados da organização (autor = usuário logado)'
);

-- Ninguém insere direto no audit_log ------------------------------------------
select throws_ok(
  $$ insert into public.audit_log (actor_id, action) values (auth.uid(), 'forjado') $$,
  '42501', null, 'authenticated não insere direto no audit_log'
);
select tests.authenticate_service_role();
select throws_ok(
  $$ insert into public.audit_log (action) values ('forjado') $$,
  '42501', null, 'service_role não insere direto no audit_log'
);

select * from finish();
rollback;
