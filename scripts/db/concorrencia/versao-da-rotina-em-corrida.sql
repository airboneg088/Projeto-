-- =============================================================================
-- Regressão R4-INTEGRIDADE-03 (concorrência): versão da rotina (D57, D99). O
-- gerente inclui um item numa rotina "em montagem" (versão 1, sem tarefa)
-- enquanto o job gera a 1ª tarefa dela. Antes, o gatilho dos itens decidia
-- subir a versão sem travar a rotina e a geração copiava os itens com o próprio
-- snapshot: a tarefa saía na versão 1 sem o item novo e a rotina ficava na
-- versão 1 com ele. Agora o gatilho trava a rotina antes de decidir: a geração
-- espera o commit e copia o item (ou o gatilho vê a tarefa e sobe a versão).
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
       gen_random_uuid() as owner, gen_random_uuid() as manager, gen_random_uuid() as tpl,
       format('host=127.0.0.1 port=%s user=postgres password=postgres dbname=%s',
              current_setting('port'), current_database()) as conninfo;

select dblink_connect('setup', conninfo) from ids;
select dblink_exec('setup', format($f$
  insert into public.organizations (id, name, slug) values (%1$L, 'Versão em corrida', 'versao-' || left(%1$L, 8));
  insert into public.stores (id, organization_id, name) values (%2$L, %1$L, 'Loja');
  insert into public.sectors (id, store_id, name) values (%3$L, %2$L, 'Setor');
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data,
                          raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', u, 'authenticated', 'authenticated',
         'versao-' || u || '@teste.local', now(), jsonb_build_object('provider', 'email', 'organization_id', %1$L),
         '{"full_name":"[TESTE] Versão"}', now(), now()
  from unnest(array[%4$L, %5$L]::uuid[]) as u;
  insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
  values (%4$L, %1$L, null, null, 'owner', now() - interval '1 day'),
         (%5$L, %1$L, %2$L, null, 'manager', now() - interval '1 day');
  -- Rotina da loja, ainda sem tarefa ("em montagem", versão 1), com um item
  insert into public.task_templates (id, organization_id, store_id, title, weight)
  values (%6$L, %1$L, %2$L, 'Rotina em montagem', 2);
  insert into public.template_items (template_id, position, text, is_critical)
  values (%6$L, 1, 'Item 1', false);
$f$, org, store, sector, owner, manager, tpl)) from ids;
select dblink_disconnect('setup');

select dblink_connect(c, conninfo) from ids, unnest(array['mgr', 'job']) as c;
select dblink_exec('mgr', format($f$ set role authenticated; set request.jwt.claims = %L; $f$,
  json_build_object('sub', manager, 'role', 'authenticated')::text)) from ids;

-- 1. O gerente inclui o item crítico (pela API; ainda sem commit: pedido em andamento)
select dblink_exec('mgr', 'begin');
select dblink_exec('mgr', format(
  $f$ insert into public.template_items (template_id, position, text, is_critical)
      values (%L, 2, 'Alarme ligado', true) $f$, tpl)) from ids;
-- 2. O job do sistema gera a 1ª tarefa da rotina (assíncrono: com a correção, espera)
select dblink_send_query('job', format(
  $f$ select private.instantiate_task(%L, %L, %L, null, now() - interval '1 hour', now() + interval '1 day')::text $f$,
  tpl, store, sector)) from ids;
select pg_sleep(0.4);
-- 3. O gerente confirma
select dblink_exec('mgr', 'commit');
select pg_sleep(0.3);
create temporary table task as
select r::uuid as id from dblink_get_result('job') as t (r text);
select * from dblink_get_result('job', false) as t (r text);

select dblink_connect('chk', conninfo) from ids;
create function pg_temp.chk(p_sql text)
returns text
language sql
as $$ select r from dblink('chk', p_sql) as t (r text) $$;

select diag(pg_temp.chk(format(
  $f$ select format('rotina: versão %%s, itens ativos %%s | tarefa: versão %%s, itens %%s',
       (select version from public.task_templates where id = %1$L),
       (select count(*) from public.template_items where template_id = %1$L and is_active),
       (select template_version from public.tasks where id = %2$L),
       (select count(*) from public.task_items where task_id = %2$L)) $f$,
  tpl, (select id from task)))) from ids;

-- Invariante da versão: tarefa e rotina na MESMA versão têm o mesmo checklist
create temporary table q as
select
  format($f$ select (count(*) filter (where ti.id is null))::text
      from public.template_items i
      join public.tasks t on t.template_id = i.template_id and t.id = %2$L
      join public.task_templates tt on tt.id = i.template_id and tt.version = t.template_version
      left join public.task_items ti on ti.task_id = t.id and ti.template_item_id = i.id
      where i.template_id = %1$L and i.is_active $f$, tpl, (select id from task)) as missing,
  format($f$ select (exists (select 1 from public.task_items ti join public.template_items i on i.id = ti.template_item_id
                      where ti.task_id = %2$L and i.is_critical)
              or (select version from public.task_templates where id = %1$L) > 1)::text $f$,
         tpl, (select id from task)) as critical,
  format($f$ select ((select version from public.task_templates where id = %1$L)
              <> (select template_version from public.tasks where id = %2$L)
              or (select count(*) from public.template_items where template_id = %1$L and is_active)
                 = (select count(*) from public.task_items where task_id = %2$L))::text $f$,
         tpl, (select id from task)) as same_count
from ids;

select is((select pg_temp.chk(missing) from q), '0',
  'nenhum item ativo da rotina falta na tarefa gerada com a MESMA versão');
select ok((select pg_temp.chk(critical)::boolean from q),
  'ou a tarefa tem o item crítico, ou a rotina subiu de versão');
select ok((select pg_temp.chk(same_count)::boolean from q),
  'mesma versão = mesmo número de itens');

select dblink_disconnect(c) from unnest(array['mgr', 'job', 'chk']) as c;
select * from finish();
rollback;
