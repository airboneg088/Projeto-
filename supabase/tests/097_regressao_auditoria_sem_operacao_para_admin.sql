-- =============================================================================
-- 097 · Regressão R1-ISO-08: admin não lê conteúdo operacional pela audit_log.
-- O diff de rotinas, itens, agendamentos, tarefas e evidências carrega o
-- conteúdo (título, instruções, janelas, responsáveis); o admin só lê operação
-- por admin_read_* (D15). Admin continua lendo cadastros e eventos; a
-- proprietária lê tudo.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(8);

select tests.create_base_fixture();
select tests.create_store_activity('p');

-- Edição auditada de uma tarefa (gera registro de tasks)
select tests.create_task('t_edit', 'store_p', 'sector_p1', 'staff_p1');
select tests.authenticate_as('manager_p');
update public.tasks set title = 'Título editado' where id = tests.fx('t_edit');

select tests.authenticate_as('admin_a');
select is(tests.count_rows($$ select count(*) from public.task_templates $$), 0::bigint,
  'pré-condição: admin não lê rotinas direto');
select is(tests.count_rows($$ select count(*) from public.audit_log
                              where table_name in ('task_templates', 'template_items', 'schedules', 'tasks', 'evidences') $$),
  0::bigint, 'admin NÃO lê registros de tabelas operacionais na auditoria');
select is(tests.count_rows($$ select count(*) from public.audit_log where diff -> 'title' ->> 'new' = 'Rotina p' $$),
  0::bigint, 'admin NÃO descobre o título da rotina da loja P pela auditoria');
select ok(tests.count_rows($$ select count(*) from public.audit_log where table_name = 'memberships' $$) > 0,
  'admin continua lendo a auditoria de cadastros (vínculos)');
-- Login do admin registrado pelo servidor (chave secreta)
select tests.authenticate_service_role();
select is(public.log_admin_login(tests.fx('admin_a'), '127.0.0.1', 'Teste'), true, 'servidor registra o login do admin');
select tests.authenticate_as('admin_a');
select is(tests.count_rows($$ select count(*) from public.audit_log where action = 'admin_login' $$),
  1::bigint, 'admin lê eventos sem tabela (login)');

select tests.authenticate_as('owner_a');
select ok(tests.count_rows($$ select count(*) from public.audit_log where table_name = 'task_templates' $$) > 0,
  'proprietária lê a auditoria das rotinas');
select is(tests.count_rows($$ select count(*) from public.audit_log
                              where table_name = 'tasks' and record_id = tests.fx('t_edit')::text $$),
  1::bigint, 'proprietária lê a edição auditada da tarefa');

select * from finish();
rollback;
