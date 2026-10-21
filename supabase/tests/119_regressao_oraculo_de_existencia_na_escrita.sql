-- =============================================================================
-- 119 · Regressão R2-FUNC-09: a escrita direta responde igual para "não existe"
-- e "é de outra organização" (D25).
--   a) o id das linhas é gerado pelo banco: a API não informa id (uma chave
--      primária repetida revelaria ids de outra organização);
--   b) vínculo para perfil inexistente, de outra organização ou dona/admin de
--      outra organização dá a mesma resposta (profile_other_organization).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(5);

select tests.create_base_fixture();
select tests.create_store_activity('b');

create temporary table r (k text, v text);
grant all on r to public;

select tests.authenticate_as('manager_p');
insert into r select 'task_existente_outra_org', tests.exec_result(format(
  $$ insert into public.tasks (id, organization_id, store_id, sector_id, title, due_at)
     values (%L, %L, %L, %L, 'Sonda', now() + interval '1 day') $$,
  tests.fx('task_b'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1')));
insert into r select 'task_inexistente', tests.exec_result(format(
  $$ insert into public.tasks (id, organization_id, store_id, sector_id, title, due_at)
     values (%L, %L, %L, %L, 'Sonda', now() + interval '1 day') $$,
  gen_random_uuid(), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1')));

select tests.authenticate_as('admin_a');
insert into r select 'perfil_dono_outra_org', tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
     values (%L, %L, %L, %L, 'staff') $$, tests.fx('owner_b'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1')));
insert into r select 'perfil_colab_outra_org', tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
     values (%L, %L, %L, %L, 'staff') $$, tests.fx('staff_b1'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1')));
insert into r select 'perfil_inexistente', tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
     values (%L, %L, %L, %L, 'staff') $$, gen_random_uuid(), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1')));
select tests.reset_role();

select is(
  (select split_part(v, ':', 1) from r where k = 'task_existente_outra_org'),
  (select split_part(v, ':', 1) from r where k = 'task_inexistente'),
  'id de tarefa de outra organização e id novo têm a mesma resposta (sem oráculo pela chave primária)');
select alike((select v from r where k = 'task_inexistente'), '42501:permission denied%',
  'a API não informa o id da linha (gerado pelo banco)');
select is(
  (select count(distinct v) from r where k like 'perfil_%'),
  1::bigint,
  'vínculo para dona de outra org, colaborador de outra org e perfil inexistente: mesmo erro');
select alike((select v from r where k = 'perfil_inexistente'), '23514:profile_other_organization%',
  'a resposta é profile_other_organization');

select is_empty(
  $$
    select format('%s.id', c.relname)
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and a.attname = 'id' and not a.attisdropped
      and has_column_privilege('authenticated', c.oid, a.attnum, 'INSERT')
  $$,
  'nenhuma tabela de public deixa authenticated informar o id no INSERT'
);

select * from finish();
rollback;
