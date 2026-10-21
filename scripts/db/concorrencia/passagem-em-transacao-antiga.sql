-- =============================================================================
-- Regressão R3-FUNCOES-03 (concorrência): a passagem da tarefa (D52) grava o
-- encerramento da tentativa com o relógio real (clock_timestamp, D81), não com o
-- início da transação (now()). Uma reatribuição numa transação que começou ANTES
-- de a tentativa ser iniciada (Server Action com vários comandos, ou um PATCH em
-- lote do PostgREST que esperou a trava de outra linha) encerra a tentativa em
-- vez de falhar inteira no CHECK task_attempts_abandoned_after_start.
--
-- Precisa de dados COMMITADOS (dblink), então roda fora da suíte pgTAP:
-- scripts/db/__tests__/concorrencia.test.mjs cria um banco descartável, roda
-- este arquivo com psql e apaga o banco. Saída em TAP (pgTAP).
-- =============================================================================
\set ON_ERROR_STOP 1
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(5);

create temporary table ids as
select gen_random_uuid() as org, gen_random_uuid() as store, gen_random_uuid() as sector,
       gen_random_uuid() as staff_a, gen_random_uuid() as staff_b, gen_random_uuid() as manager,
       gen_random_uuid() as task, gen_random_uuid() as task1, gen_random_uuid() as task2,
       format('host=127.0.0.1 port=%s user=postgres password=postgres dbname=%s',
              current_setting('port'), current_database()) as conninfo;

select dblink_connect('setup', conninfo) from ids;
select dblink_exec('setup', format($f$
  insert into public.organizations (id, name, slug) values (%1$L, 'Passagem', 'passagem-' || left(%1$L, 8));
  insert into public.stores (id, organization_id, name) values (%2$L, %1$L, 'Loja');
  insert into public.sectors (id, store_id, name) values (%3$L, %2$L, 'Setor');
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data,
                          raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', u, 'authenticated', 'authenticated',
         'passagem-' || u || '@teste.local', now(), jsonb_build_object('provider', 'email', 'organization_id', %1$L),
         '{"full_name":"[TESTE] Passagem"}', now(), now()
  from unnest(array[%4$L, %5$L, %6$L]::uuid[]) as u;
  insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
  values (%4$L, %1$L, %2$L, %3$L, 'staff', now() - interval '1 day'),
         (%5$L, %1$L, %2$L, %3$L, 'staff', now() - interval '1 day'),
         (%6$L, %1$L, %2$L, null, 'manager', now() - interval '1 day');
  insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at)
  values (%7$L, %1$L, %2$L, %3$L, 'Passagem', %4$L, now() - interval '1 hour', now() + interval '1 day');
  insert into public.task_items (task_id, position, text) values (%7$L, 1, 'Item 1');
  -- Cenário 2 (um único UPDATE em lote, como um PATCH do PostgREST): t1 é criada antes de t2
  insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at)
  values (%8$L, %1$L, %2$L, %3$L, 'Passagem t1', %4$L, now() - interval '1 hour', now() + interval '1 day');
  insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at)
  values (%9$L, %1$L, %2$L, %3$L, 'Passagem t2', %4$L, now() - interval '1 hour', now() + interval '1 day');
$f$, org, store, sector, staff_a, staff_b, manager, task, task1, task2)) from ids;
select dblink_disconnect('setup');

select dblink_connect(c, conninfo) from ids, unnest(array['mgr', 'a']) as c;
select dblink_exec(c, format($f$ set role authenticated; set request.jwt.claims = %L; $f$,
  json_build_object('sub', case c when 'mgr' then manager else staff_a end, 'role', 'authenticated')::text))
from ids, unnest(array['mgr', 'a']) as c;

-- Cenário 1. A transação do gerente começa (ex.: Server Action que lê a equipe antes de reatribuir)
select dblink_exec('mgr', 'begin');
select * from dblink('mgr', 'select now()::text') as t (inicio_mgr text);
select pg_sleep(0.2);
-- 2. A inicia a tarefa (commit)
create temporary table attempt as
select a.id from ids, dblink('a', format('select public.start_attempt(%L, null)', task)) as a (id uuid);
-- 3. O gerente reatribui para B na mesma transação
create temporary table results (result text, err text);
insert into results
select (select r from dblink('mgr', format('update public.tasks set assignee_id = %L where id = %L returning %L',
                                            staff_b, task, 'ok'), false) as t (r text)),
       dblink_error_message('mgr')
from ids;
select dblink_exec('mgr', 'commit');
select diag(format('reatribuição: resultado=%s erro=%s', coalesce(result, '(nenhum)'), err)) from results;

select is((select result from results), 'ok',
  'a reatribuição feita numa transação iniciada antes da tentativa funciona');
select is(
  (select abandoned_reason from public.task_attempts a join attempt x on x.id = a.id),
  'reassigned',
  'a tentativa de A é encerrada sem envio (reassigned)');
select ok(
  (select err from results) not ilike '%abandoned_after_start%',
  'a passagem não esbarra no CHECK task_attempts_abandoned_after_start');

-- ---------------------------------------------------------------------------
-- Cenário 2: UM comando só. O gerente reatribui as tarefas de A em lote
-- (PATCH /rest/v1/tasks?assignee_id=eq.A). O comando espera a trava de t1 (outra
-- edição em andamento); enquanto isso A inicia t2. Quando a trava sai, o lote
-- todo falha no CHECK.
-- ---------------------------------------------------------------------------
select dblink_connect('hold', conninfo) from ids;
select dblink_exec('hold', format($f$ set role authenticated; set request.jwt.claims = %L; $f$,
  json_build_object('sub', manager, 'role', 'authenticated')::text)) from ids;
select dblink_exec('hold', 'begin');
select dblink_exec('hold', format('update public.tasks set title = %L where id = %L', 'Passagem t1 (editando)', task1)) from ids;
select dblink_send_query('mgr', format(
  'update public.tasks set assignee_id = %L where id in (%L, %L) returning id', staff_b, task1, task2)) from ids;
select pg_sleep(0.3);
create temporary table attempt2 as
select a.id from ids, dblink('a', format('select public.start_attempt(%L, null)', task2)) as a (id uuid);
select dblink_exec('hold', 'commit');
select pg_sleep(0.3);
create temporary table results2 (n int, err text);
insert into results2 select (select count(*) from dblink_get_result('mgr', false) as t (id uuid)), dblink_error_message('mgr');
select * from dblink_get_result('mgr', false) as t (id uuid);
select diag(format('lote: linhas=%s erro=%s', n, err)) from results2;
select ok((select err from results2) = 'OK',
  'cenário 2: o PATCH em lote que esperou uma trava reatribui as tarefas (não falha no CHECK)');
select is(
  (select assignee_id from public.tasks t join ids i on i.task2 = t.id),
  (select staff_b from ids),
  'cenário 2: t2 passou para B');
select dblink_disconnect('hold');

select dblink_disconnect(c) from unnest(array['mgr', 'a']) as c;
select * from finish();
rollback;
