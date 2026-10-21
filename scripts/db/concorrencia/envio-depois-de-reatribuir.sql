-- =============================================================================
-- Regressão R2-REGRAS-S6 (concorrência): submit_attempt confere de novo, depois
-- de travar a tarefa, se ela ainda é de quem envia. A iniciou e respondeu; o
-- gerente reatribui a tarefa para B enquanto o envio de A espera a trava: A
-- recebe 'forbidden', a tentativa de A fica no histórico encerrada sem envio
-- (reassigned) e B inicia a tentativa seguinte.
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
       gen_random_uuid() as task,
       format('host=127.0.0.1 port=%s user=postgres password=postgres dbname=%s',
              current_setting('port'), current_database()) as conninfo;

-- ---------------------------------------------------------------------------
-- Dados commitados (sessão "setup")
-- ---------------------------------------------------------------------------
select dblink_connect('setup', conninfo) from ids;
select dblink_exec('setup', format($f$
  insert into public.organizations (id, name, slug) values (%1$L, 'Envio', 'envio-' || left(%1$L, 8));
  insert into public.stores (id, organization_id, name) values (%2$L, %1$L, 'Loja');
  insert into public.sectors (id, store_id, name) values (%3$L, %2$L, 'Setor');
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data,
                          raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', u, 'authenticated', 'authenticated',
         'envio-' || u || '@teste.local', now(), jsonb_build_object('provider', 'email', 'organization_id', %1$L),
         '{"full_name":"[TESTE] Envio"}', now(), now()
  from unnest(array[%4$L, %5$L, %6$L]::uuid[]) as u;
  insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
  values (%4$L, %1$L, %2$L, %3$L, 'staff', now() - interval '1 day'),
         (%5$L, %1$L, %2$L, %3$L, 'staff', now() - interval '1 day'),
         (%6$L, %1$L, %2$L, null, 'manager', now() - interval '1 day');
  insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at)
  values (%7$L, %1$L, %2$L, %3$L, 'Envio', %4$L, now() - interval '1 hour', now() + interval '1 day');
  insert into public.task_items (task_id, position, text) values (%7$L, 1, 'Item 1');
$f$, org, store, sector, staff_a, staff_b, manager, task)) from ids;
-- A inicia e responde o item (commitado)
select dblink_exec('setup', format($f$ set role authenticated; set request.jwt.claims = %L; $f$,
  json_build_object('sub', staff_a, 'role', 'authenticated')::text)) from ids;
create temporary table attempt as
select a.id from ids, dblink('setup', format('select public.start_attempt(%L, null)', task)) as a (id uuid);
select t.r from attempt a, ids,
  dblink('setup', format('select public.answer_item(%L, i.id, true)::text from public.task_items i where i.task_id = %L',
                         a.id, ids.task)) as t (r text);
select dblink_disconnect('setup');

-- ---------------------------------------------------------------------------
-- Corrida
-- ---------------------------------------------------------------------------
select dblink_connect(c, conninfo) from ids, unnest(array['mgr', 'a', 'b']) as c;
select dblink_exec(c, format($f$ set role authenticated; set request.jwt.claims = %L; $f$,
  json_build_object('sub', case c when 'mgr' then manager when 'a' then staff_a else staff_b end, 'role', 'authenticated')::text))
from ids, unnest(array['mgr', 'a', 'b']) as c;

-- Gerente reatribui a tarefa de A para B (transação ainda aberta)
select dblink_exec('mgr', 'begin');
select dblink_exec('mgr', format('update public.tasks set assignee_id = %L where id = %L', staff_b, task)) from ids;
-- A toca em "Enviar" (no instante da checagem sem trava a tentativa ainda é dele)
select dblink_send_query('a', format('select public.submit_attempt(%L)::text', a.id)) from attempt a;
select pg_sleep(0.3);
select dblink_exec('mgr', 'commit');
select pg_sleep(0.3);

create temporary table results (who text, result text, err text);
insert into results select 'a', (select r from dblink_get_result('a', false) as t (r text)), dblink_error_message('a');
select * from dblink_get_result('a', false) as t (r text);
select dblink_send_query('b', format('select public.start_attempt(%L, null)::text', task)) from ids;
select pg_sleep(0.2);
insert into results select 'b', (select r from dblink_get_result('b', false) as t (r text)), dblink_error_message('b');
select * from dblink_get_result('b', false) as t (r text);
select diag(format('%s -> resultado=%s erro=%s', who, coalesce(result, '(nenhum)'), err)) from results order by who;

select ok((select err from results where who = 'a') ilike '%forbidden%',
  'A (que deixou de ser o responsável enquanto esperava a trava) NÃO envia a tarefa');
select is((select status::text from public.tasks t join ids i on i.task = t.id), 'in_progress',
  'a tarefa não foi enviada');
select results_eq(
  $$ select a.attempt_number::int, a.performed_by, a.submitted_at is null, a.abandoned_reason
     from public.task_attempts a join ids i on i.task = a.task_id order by a.attempt_number $$,
  $$ select 1, staff_a, true, 'reassigned'::text from ids
     union all select 2, staff_b, true, null::text from ids $$,
  'a tentativa de A fica no histórico, encerrada sem envio; B iniciou a tentativa 2');
select is(
  (select count(*)::int from public.attempt_item_answers ans join attempt a on a.id = ans.attempt_id),
  1, 'as respostas de A ficam no histórico');
select ok(
  exists (select 1 from public.audit_log l join attempt a on l.record_id = a.id::text
          where l.action = 'attempt_abandoned'),
  'a passagem ficou no audit_log');

select dblink_disconnect(c) from unnest(array['mgr', 'a', 'b']) as c;
select * from finish();
rollback;
