-- =============================================================================
-- Regressão R1-FI-06 (concorrência): foto, resposta e envio da MESMA tentativa
-- chegando ao mesmo tempo não geram deadlock (40P01).
--
-- Todas as RPCs de execução/revisão travam a TAREFA antes da TENTATIVA. Antes da
-- correção, register_evidence travava a tentativa e depois (pela FK de
-- evidences) pedia FOR KEY SHARE na tarefa, na ordem inversa de submit_attempt.
--
-- Precisa de dados COMMITADOS (as sessões dblink não enxergam a transação do
-- teste), então NÃO roda na suíte pgTAP normal: o teste
-- scripts/db/__tests__/concorrencia.test.mjs cria um banco descartável, roda
-- este arquivo com psql e apaga o banco. Saída em TAP (pgTAP).
--
-- Para a ordem de chegada ser determinística, a sessão X segura a trava da
-- tarefa (como qualquer RPC em andamento): chega primeiro o envio, depois a
-- foto e a resposta. Ao soltar X, o envio conclui e as outras terminam com
-- erro limpo (attempt_closed), nunca deadlock.
-- =============================================================================
\set ON_ERROR_STOP 1
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(5);

create temporary table ids as
select gen_random_uuid() as org, gen_random_uuid() as store, gen_random_uuid() as sector,
       gen_random_uuid() as staff, gen_random_uuid() as task, gen_random_uuid() as item,
       format('host=127.0.0.1 port=%s user=postgres password=postgres dbname=%s',
              current_setting('port'), current_database()) as conninfo;

-- ---------------------------------------------------------------------------
-- Dados commitados (sessão "setup")
-- ---------------------------------------------------------------------------
select dblink_connect('setup', conninfo) from ids;
select dblink_exec('setup', format($f$
  insert into public.organizations (id, name, slug) values (%1$L, 'Concorrência', 'conc-' || left(%1$L, 8));
  insert into public.stores (id, organization_id, name) values (%2$L, %1$L, 'Loja');
  insert into public.sectors (id, store_id, name) values (%3$L, %2$L, 'Setor');
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data,
                          raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', %4$L, 'authenticated', 'authenticated',
          'conc-' || %4$L || '@teste.local', now(), '{"provider":"email"}', '{"full_name":"[TESTE] Concorrência"}',
          now(), now());
  insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
  values (%4$L, %1$L, %2$L, %3$L, 'staff', now() - interval '1 day');
  insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at)
  values (%5$L, %1$L, %2$L, %3$L, 'Concorrência', %4$L, now() - interval '1 hour', now() + interval '1 day');
  insert into public.task_items (id, task_id, position, text) values (%6$L, %5$L, 1, 'Item 1');
$f$, org, store, sector, staff, task, item)) from ids;

-- Colaborador inicia, responde e envia a foto ao storage (commitado)
select dblink_exec('setup', format($f$
  set role authenticated;
  set request.jwt.claims = %1$L;
$f$, json_build_object('sub', staff, 'role', 'authenticated')::text)) from ids;
create temporary table attempt as
select a.id from ids, dblink('setup', format('select public.start_attempt(%L, null)', task)) as a (id uuid);
select t.r
from attempt a, ids i,
     dblink('setup', format('select public.answer_item(%L, %L, true)::text', a.id, i.item)) as t (r text);
create temporary table photo as
select format('%s/%s/%s/%s/%s.jpg', i.org, i.store, i.task, a.id, gen_random_uuid()) as path
from ids i, attempt a;
select dblink_exec('setup', format(
  $f$ insert into storage.objects (bucket_id, name, owner_id) values ('evidences', %L, %L) $f$, p.path, i.staff))
from photo p, ids i;
select dblink_disconnect('setup');

-- ---------------------------------------------------------------------------
-- Corrida
-- ---------------------------------------------------------------------------
select dblink_connect('x', conninfo) from ids;
select dblink_connect('sub', conninfo) from ids;
select dblink_connect('ev', conninfo) from ids;
select dblink_connect('ans', conninfo) from ids;
select dblink_exec(c, format($f$
  set role authenticated;
  set request.jwt.claims = %1$L;
$f$, json_build_object('sub', staff, 'role', 'authenticated')::text))
from ids, unnest(array['sub', 'ev', 'ans']) as c;

-- X segura a trava da tarefa
select dblink_exec('x', 'begin');
select t.r from ids, dblink('x', format('select id::text from public.tasks where id = %L for update', task)) as t (r text);

-- 1º chega o envio (espera a trava da tarefa)
select dblink_send_query('sub', format('select public.submit_attempt(%L)::text', a.id)) from attempt a;
select pg_sleep(0.3);
-- 2º chegam a foto e a resposta
select dblink_send_query('ev', format(
  $f$ select public.register_evidence(%1$L, null, %2$L, now(), null, null, null, %3$L, null, 1000, true, null)::text $f$,
  a.id, p.path, encode(sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 'hex')))
from attempt a, photo p;
select dblink_send_query('ans', format('select public.answer_item(%L, %L, true)::text', a.id, i.item))
from attempt a, ids i;
select pg_sleep(0.5);
select dblink_exec('x', 'commit');

create temporary table results (who text, result text, err text);
insert into results select 'submit', (select r from dblink_get_result('sub', false) as t (r text)), dblink_error_message('sub');
select * from dblink_get_result('sub', false) as t (r text);
insert into results select 'evidence', (select r from dblink_get_result('ev', false) as t (r text)), dblink_error_message('ev');
select * from dblink_get_result('ev', false) as t (r text);
insert into results select 'answer', (select r from dblink_get_result('ans', false) as t (r text)), dblink_error_message('ans');
select * from dblink_get_result('ans', false) as t (r text);

select diag(format('%s -> resultado=%s erro=%s', who, coalesce(result, '(nenhum)'), err)) from results order by who;

select ok(
  not exists (select 1 from results where err ilike '%deadlock%'),
  'foto, resposta e envio concorrentes na mesma tentativa não geram deadlock (40P01)'
);
select is((select result from results where who = 'submit'), 'submitted', 'o envio conclui (chegou primeiro)');
select ok((select err from results where who = 'evidence') ilike '%attempt_closed%',
  'a foto que chegou depois termina com attempt_closed');
select ok((select err from results where who = 'answer') ilike '%attempt_closed%',
  'a resposta que chegou depois termina com attempt_closed');
select is(
  (select count(*) from public.evidences e join attempt a on a.id = e.attempt_id),
  0::bigint,
  'nenhuma foto entrou na tentativa já enviada'
);

select dblink_disconnect(c) from unnest(array['x', 'sub', 'ev', 'ans']) as c;

select * from finish();
rollback;
