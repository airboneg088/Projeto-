-- =============================================================================
-- Regressão R4-INTEGRIDADE-01 / R4-REGRAS-07 (concorrência): a passagem por
-- mudança de vínculo ou de perfil (D82) não deixa tentativa aberta de quem
-- iniciou a tarefa enquanto a mudança ainda não estava commitada. O gatilho
-- AFTER (release_attempts_of_person) procura as tentativas que já existem;
-- start_attempt trava FOR SHARE os vínculos de colaborador da pessoa na loja e
-- o perfil antes da tarefa (D97): o início espera o commit da mudança e recebe
-- 'forbidden' (fim imediato do vínculo, troca de setor, desativação).
--
-- Precisa de dados COMMITADOS (dblink), então roda fora da suíte pgTAP:
-- scripts/db/__tests__/concorrencia.test.mjs cria um banco descartável, roda
-- este arquivo com psql e apaga o banco. Saída em TAP (pgTAP).
-- =============================================================================
\set ON_ERROR_STOP 1
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(9);

create temporary table ids as
select gen_random_uuid() as org, gen_random_uuid() as store, gen_random_uuid() as sector1,
       gen_random_uuid() as sector2, gen_random_uuid() as owner,
       gen_random_uuid() as staff_a, gen_random_uuid() as staff_b, gen_random_uuid() as staff_c,
       gen_random_uuid() as task_a, gen_random_uuid() as task_b, gen_random_uuid() as task_c,
       format('host=127.0.0.1 port=%s user=postgres password=postgres dbname=%s',
              current_setting('port'), current_database()) as conninfo;

select dblink_connect('setup', conninfo) from ids;
select dblink_exec('setup', format($f$
  insert into public.organizations (id, name, slug) values (%1$L, 'Mudança de vínculo', 'vinculo-' || left(%1$L, 8));
  insert into public.stores (id, organization_id, name) values (%2$L, %1$L, 'Loja');
  insert into public.sectors (id, store_id, name) values (%3$L, %2$L, 'Setor 1'), (%4$L, %2$L, 'Setor 2');
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data,
                          raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', u, 'authenticated', 'authenticated',
         'vinculo-' || u || '@teste.local', now(), jsonb_build_object('provider', 'email', 'organization_id', %1$L),
         '{"full_name":"[TESTE] Vínculo"}', now(), now()
  from unnest(array[%5$L, %6$L, %7$L, %8$L]::uuid[]) as u;
  insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
  values (%5$L, %1$L, null, null, 'owner', now() - interval '1 day'),
         (%6$L, %1$L, %2$L, %3$L, 'staff', now() - interval '1 day'),
         (%7$L, %1$L, %2$L, %3$L, 'staff', now() - interval '1 day'),
         (%8$L, %1$L, %2$L, %3$L, 'staff', now() - interval '1 day');
  -- Tarefas de equipe do Setor 1 (qualquer colaborador vigente do setor inicia)
  insert into public.tasks (id, organization_id, store_id, sector_id, title, window_start_at, due_at)
  values (%9$L,  %1$L, %2$L, %3$L, 'Corrida A', now() - interval '1 hour', now() + interval '1 day'),
         (%10$L, %1$L, %2$L, %3$L, 'Corrida B', now() - interval '1 hour', now() + interval '1 day'),
         (%11$L, %1$L, %2$L, %3$L, 'Corrida C', now() - interval '1 hour', now() + interval '1 day');
  insert into public.task_items (task_id, position, text)
  select t, 1, 'Item 1' from unnest(array[%9$L, %10$L, %11$L]::uuid[]) as t;
$f$, org, store, sector1, sector2, owner, staff_a, staff_b, staff_c, task_a, task_b, task_c)) from ids;
select dblink_disconnect('setup');

select dblink_connect(c, conninfo) from ids, unnest(array['own', 'a', 'b', 'c']) as c;
select dblink_exec(c, format($f$ set role authenticated; set request.jwt.claims = %L; $f$,
  json_build_object('sub', case c when 'own' then owner when 'a' then staff_a
                                  when 'b' then staff_b else staff_c end,
                    'role', 'authenticated')::text))
from ids, unnest(array['own', 'a', 'b', 'c']) as c;

-- Executa: a proprietária muda o vínculo/perfil (sem commit); a pessoa inicia a tarefa
-- (assíncrono: com a correção, o início espera o commit da mudança); a proprietária
-- confirma; lê o resultado do início.
create function pg_temp.race(p_who text, p_change text, p_task uuid)
returns text
language plpgsql
as $$
declare
  v_res text;
begin
  perform dblink_exec('own', 'begin');
  perform dblink_exec('own', p_change);
  perform dblink_send_query(p_who, format('select public.start_attempt(%L, null)::text', p_task));
  perform pg_sleep(0.4);
  perform dblink_exec('own', 'commit');
  perform pg_sleep(0.2);
  begin
    select r into v_res from dblink_get_result(p_who) as t (r text);
  exception when others then
    v_res := 'erro: ' || sqlerrm;
  end;
  -- esvazia o resultado final da consulta assíncrona
  perform * from dblink_get_result(p_who, false) as t (r text);
  return coalesce(v_res, 'nulo');
end;
$$;

-- Cenário 1: fim imediato do vínculo de A (ends_at = agora) x A inicia a tarefa A
create temporary table r1 as
select pg_temp.race('a', format('update public.memberships set ends_at = now() where profile_id = %L', staff_a), task_a) as res
from ids;
-- Cenário 2: B muda do Setor 1 para o Setor 2 x B inicia a tarefa de equipe do Setor 1
create temporary table r2 as
select pg_temp.race('b', format('update public.memberships set sector_id = %L where profile_id = %L', sector2, staff_b), task_b) as res
from ids;
-- Cenário 3: perfil de C desativado (como set_profile_status) x C inicia a tarefa C
--   (como postgres na sessão 'own', o mesmo UPDATE que a RPC do admin faz)
select dblink_exec('own', 'reset role; reset request.jwt.claims');
create temporary table r3 as
select pg_temp.race('c', format('update public.profiles set status = %L where id = %L', 'inactive', staff_c), task_c) as res
from ids;

select diag('início de A: ' || res) from r1;
select diag('início de B: ' || res) from r2;
select diag('início de C: ' || res) from r3;

select ok((select res from r1) ilike '%forbidden%',
  'cenário 1: o início que esperou o fim do vínculo recebe forbidden');
select ok((select res from r2) ilike '%forbidden%',
  'cenário 2: o início que esperou a troca de setor recebe forbidden');
select ok((select res from r3) ilike '%forbidden%',
  'cenário 3: o início que esperou a desativação do perfil recebe forbidden');

-- O que a D82 promete: depois da mudança, a pessoa não tem tentativa aberta numa tarefa
-- que já não pode executar (ou o início foi recusado, ou a tentativa foi encerrada).
-- As conferências rodam numa conexão nova (transação que começa depois dos commits:
-- now() desta transação de teste é anterior ao ends_at gravado).
select dblink_connect('chk', conninfo) from ids;
create function pg_temp.chk(p_sql text)
returns text
language sql
as $$ select r from dblink('chk', p_sql) as t (r text) $$;

select is((select pg_temp.chk(format(
  'select count(*)::text from public.task_attempts a where a.performed_by = %L and a.task_id = %L and a.submitted_at is null and a.abandoned_at is null',
  staff_a, task_a)) from ids), '0',
  'cenário 1: quem teve o vínculo encerrado não fica com tentativa aberta');
select is((select pg_temp.chk(format('select private.stale_attempt_reason(%L, %L)', task_a, staff_a)) from ids),
  'access_lost',
  'cenário 1 (contexto): A já não pode executar a tarefa (access_lost)');
select is((select pg_temp.chk(format(
  'select count(*)::text from public.task_attempts a where a.performed_by = %L and a.task_id = %L and a.submitted_at is null and a.abandoned_at is null',
  staff_b, task_b)) from ids), '0',
  'cenário 2: quem mudou de setor não fica com tentativa aberta na tarefa do setor antigo');
select is((select pg_temp.chk(format('select private.stale_attempt_reason(%L, %L)', task_b, staff_b)) from ids),
  'reassigned',
  'cenário 2 (contexto): B já não pode executar a tarefa (reassigned)');
select is((select pg_temp.chk(format(
  'select count(*)::text from public.task_attempts a where a.performed_by = %L and a.task_id = %L and a.submitted_at is null and a.abandoned_at is null',
  staff_c, task_c)) from ids), '0',
  'cenário 3: quem foi desativado não fica com tentativa aberta');
-- Efeito nos indicadores: a tarefa (ainda no prazo) conta para quem saiu
select is((select pg_temp.chk(format('select coalesce(private.task_person(%L, null, null, false)::text, %L)', task_a, 'Sem responsável')) from ids),
  'Sem responsável',
  'cenário 1: a tarefa de equipe não conta para quem já saiu (pessoa da tarefa)');
select dblink_disconnect('chk');

select dblink_disconnect(c) from unnest(array['own', 'a', 'b', 'c']) as c;
select * from finish();
rollback;
