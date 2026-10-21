-- =============================================================================
-- Regressão R2-FUNC-03 (concorrência): o MESMO registro de foto (mesmo
-- client_mutation_id) chegando duas vezes ao mesmo tempo (fila offline
-- reenviando enquanto o 1º pedido ainda está no ar) devolve a mesma evidência
-- nas duas respostas, e não 'duplicate_photo'.
--
-- register_evidence confere o reenvio de novo depois das travas e, se mesmo
-- assim a gravação esbarrar em evidences_client_mutation_id_key, devolve a
-- evidência existente.
--
-- Precisa de dados COMMITADOS (dblink), então roda fora da suíte pgTAP:
-- scripts/db/__tests__/concorrencia.test.mjs cria um banco descartável, roda
-- este arquivo com psql e apaga o banco. Saída em TAP (pgTAP).
-- =============================================================================
\set ON_ERROR_STOP 1
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(3);

create temporary table ids as
select gen_random_uuid() as org, gen_random_uuid() as store, gen_random_uuid() as sector,
       gen_random_uuid() as staff, gen_random_uuid() as task, gen_random_uuid() as item,
       gen_random_uuid() as cmid,
       encode(sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 'hex') as sha,
       format('host=127.0.0.1 port=%s user=postgres password=postgres dbname=%s',
              current_setting('port'), current_database()) as conninfo;

-- ---------------------------------------------------------------------------
-- Dados commitados (sessão "setup")
-- ---------------------------------------------------------------------------
select dblink_connect('setup', conninfo) from ids;
select dblink_exec('setup', format($f$
  insert into public.organizations (id, name, slug) values (%1$L, 'Reenvio da foto', 'reenvio-' || left(%1$L, 8));
  insert into public.stores (id, organization_id, name) values (%2$L, %1$L, 'Loja');
  insert into public.sectors (id, store_id, name) values (%3$L, %2$L, 'Setor');
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data,
                          raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', %4$L, 'authenticated', 'authenticated',
          'reenvio-' || %4$L || '@teste.local', now(), jsonb_build_object('provider', 'email', 'organization_id', %1$L),
          '{"full_name":"[TESTE] Reenvio"}', now(), now());
  insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
  values (%4$L, %1$L, %2$L, %3$L, 'staff', now() - interval '1 day');
  insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at)
  values (%5$L, %1$L, %2$L, %3$L, 'Reenvio da foto', %4$L, now() - interval '1 hour', now() + interval '1 day');
  insert into public.task_items (id, task_id, position, text) values (%6$L, %5$L, 1, 'Item 1');
$f$, org, store, sector, staff, task, item)) from ids;
select dblink_exec('setup', format($f$ set role authenticated; set request.jwt.claims = %L; $f$,
  json_build_object('sub', staff, 'role', 'authenticated')::text)) from ids;
create temporary table attempt as
select a.id from ids, dblink('setup', format('select public.start_attempt(%L, null)', task)) as a (id uuid);
create temporary table photo as
select format('%s/%s/%s/%s/%s.jpg', i.org, i.store, i.task, a.id, gen_random_uuid()) as path from ids i, attempt a;
select dblink_exec('setup', format($f$ insert into storage.objects (bucket_id, name, owner_id) values ('evidences', %L, %L) $f$,
  p.path, i.staff)) from photo p, ids i;
select dblink_disconnect('setup');

-- ---------------------------------------------------------------------------
-- Corrida: X segura a trava da tarefa (como qualquer RPC em andamento); o mesmo
-- registro chega duas vezes e os dois pedidos passam do reenvio (passo 2)
-- antes de qualquer um gravar
-- ---------------------------------------------------------------------------
select dblink_connect(c, conninfo) from ids, unnest(array['x', 'ev1', 'ev2']) as c;
select dblink_exec(c, format($f$ set role authenticated; set request.jwt.claims = %L; $f$,
  json_build_object('sub', staff, 'role', 'authenticated')::text)) from ids, unnest(array['ev1', 'ev2']) as c;
select dblink_exec('x', 'begin');
select t.r from ids, dblink('x', format('select id::text from public.tasks where id = %L for update', task)) as t (r text);

create temporary table call as
select format($f$ select public.register_evidence(%1$L, null, %2$L, now(), null, null, null, %3$L, null, 1000, true, %4$L)::text $f$,
              a.id, p.path, i.sha, i.cmid) as sql
from attempt a, photo p, ids i;
select dblink_send_query('ev1', sql) from call;
select pg_sleep(0.3);
select dblink_send_query('ev2', sql) from call;
select pg_sleep(0.3);
select dblink_exec('x', 'commit');
select pg_sleep(0.3);

create temporary table results (who text, result text, err text);
insert into results select 'ev1', (select r from dblink_get_result('ev1', false) as t (r text)), dblink_error_message('ev1');
select * from dblink_get_result('ev1', false) as t (r text);
insert into results select 'ev2', (select r from dblink_get_result('ev2', false) as t (r text)), dblink_error_message('ev2');
select * from dblink_get_result('ev2', false) as t (r text);
select diag(format('%s -> resultado=%s erro=%s', who, coalesce(result, '(nenhum)'), err)) from results order by who;

select isnt((select result from results where who = 'ev1'), null, 'o 1º registro devolve o id da evidência');
select is((select result from results where who = 'ev2'), (select result from results where who = 'ev1'),
  'reenvio concorrente com o mesmo client_mutation_id devolve a MESMA evidência');
select ok(coalesce((select err from results where who = 'ev2'), '') not ilike '%duplicate_photo%',
  'reenvio concorrente não é acusado de foto repetida (duplicate_photo)');

select dblink_disconnect(c) from unnest(array['x', 'ev1', 'ev2']) as c;
select * from finish();
rollback;
