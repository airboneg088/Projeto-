-- =============================================================================
-- 090 · Regressão R1-ISO-01: papel de proprietária/admin de OUTRA organização
-- não vale na nossa.
--   1. Uma pessoa pertence a uma única organização: dono/admin de uma org não
--      vincula pessoa de outra (nem conta criada para outra org).
--   2. Mesmo que um vínculo duplo exista (gravado pelo sistema, gatilho
--      desligado só aqui), as funções de acesso falham fechadas: o papel da
--      org B não dá poder nenhum na org A.
--   3. Vínculo antigo injetado em outra org não tira o dono B da própria org.
--   4. A exclusão de sobreposição inclui a organização.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(19);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('c');
select tests.create_store_activity('b');

-- 1. Uma pessoa, uma organização --------------------------------------------
select tests.authenticate_as('owner_b');
select alike(
  tests.exec_result(format(
    $$ insert into public.memberships (profile_id, organization_id, store_id, role) values (%L, %L, null, 'owner') $$,
    tests.fx('staff_p1'), tests.fx('org_b'))),
  '23514:profile_other_organization%',
  'dono da org B NÃO cria vínculo (owner na org B) para colaborador da org A'
);

select tests.authenticate_as('admin_a');
select matches(
  tests.exec_result(format(
    $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
       values (%L, %L, %L, %L, 'staff', '2000-01-01') $$,
    tests.fx('owner_b'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'))),
  '^(42501|23514):',
  'admin da org A NÃO cria vínculo para o dono da org B (RLS ou uma pessoa, uma organização)'
);

-- Conta criada para a org B (app_metadata) não é "capturada" pela org A
select tests.reset_role();
select tests.create_user('novo_b', '[TESTE] Pessoa nova da org B');
update auth.users
   set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('organization_id', tests.fx('org_b'))
 where id = tests.fx('novo_b');
select tests.authenticate_as('admin_a');
select alike(
  tests.exec_result(format(
    $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
       values (%L, %L, %L, %L, 'staff') $$,
    tests.fx('novo_b'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'))),
  '23514:profile_other_organization%',
  'admin da org A NÃO vincula conta criada para a org B'
);
select tests.authenticate_as('owner_b');
select is(
  tests.exec_result(format(
    $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
       values (%L, %L, %L, %L, 'staff') $$,
    tests.fx('novo_b'), tests.fx('org_b'), tests.fx('store_b'), tests.fx('sector_b1'))),
  'ok',
  'dono da org B vincula a conta criada para a org B'
);

-- 2. Vínculo duplo gravado pelo sistema: falha fechada ------------------------
select tests.reset_role();
alter table public.memberships disable trigger memberships_single_organization;
insert into public.memberships (profile_id, organization_id, store_id, role, starts_at)
values (tests.fx('staff_p1'), tests.fx('org_b'), null, 'owner', now() - interval '1 day');
alter table public.memberships enable trigger memberships_single_organization;

select tests.authenticate_as('staff_p1');
select is((select private.current_org_id()), null::uuid,
  'pessoa com vínculos vigentes em duas organizações não tem organização atual (falha fechada)');
select ok(not (select private.is_owner()), 'papel de dono na org B não vale como dono');
select is(tests.count_rows($$ select count(*) from public.memberships
                              where organization_id = tests.fx('org_a') and profile_id <> auth.uid() $$),
  0::bigint, 'colaborador P1 (dono na org B) NÃO lê vínculos alheios da org A');
select is(tests.count_rows($$ select count(*) from public.audit_log where organization_id = tests.fx('org_a') $$),
  0::bigint, 'colaborador P1 (dono na org B) NÃO lê a auditoria da org A');
select is(tests.count_rows($$ select count(*) from public.data_requests
                              where organization_id = tests.fx('org_a') and profile_id <> auth.uid() $$),
  0::bigint, 'colaborador P1 (dono na org B) NÃO lê pedidos LGPD de outras pessoas da org A');
select is(tests.count_rows($$ select count(*) from public.profiles where id <> auth.uid() $$),
  0::bigint, 'colaborador P1 (dono na org B) só vê o próprio perfil');
select isnt(
  tests.exec_result(format($$ insert into public.task_templates (organization_id, store_id, title) values (%L, null, 'Rotina invasora') $$,
                        tests.fx('org_a'))),
  'ok', 'colaborador P1 (dono na org B) NÃO cria rotina da rede na org A');
select isnt(
  tests.exec_result(format($$ insert into public.memberships (profile_id, organization_id, store_id, role) values (%L, %L, %L, 'manager') $$,
                        tests.fx('staff_p1'), tests.fx('org_a'), tests.fx('store_c'))),
  'ok', 'colaborador P1 (dono na org B) NÃO se torna gerente da loja C');
select isnt(
  tests.exec_result(format($$ insert into public.memberships (profile_id, organization_id, store_id, role) values (%L, %L, null, 'owner') $$,
                        tests.fx('manager_b'), tests.fx('org_a'))),
  'ok', 'colaborador P1 (dono na org B) NÃO cria proprietária na org A');
select is(tests.affected_rows(format($$ update public.memberships set ends_at = now() where id = %L $$, tests.fx('m_owner_a'))),
  0, 'colaborador P1 (dono na org B) NÃO encerra o vínculo da dona da org A');
select is(tests.count_rows($$ select count(*) from public.tasks where store_id = tests.fx('store_c') $$),
  0::bigint, 'colaborador P1 continua sem ver tarefas da loja C');
select is(tests.count_rows($$ select count(*) from public.tasks where store_id = tests.fx('store_b') $$),
  0::bigint, 'nem as tarefas da org B: com duas organizações vigentes, nada é liberado');

-- 3. Vínculo antigo em outra org (gravado pelo sistema) não muda a org do dono B
select tests.reset_role();
update public.memberships set ends_at = now() - interval '1 hour'
 where profile_id = tests.fx('staff_p1') and organization_id = tests.fx('org_b');
alter table public.memberships disable trigger memberships_single_organization;
insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at, ends_at)
values (tests.fx('owner_b'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'staff',
        '2000-01-01', '2000-02-01');
alter table public.memberships enable trigger memberships_single_organization;

select tests.authenticate_as('owner_b');
select is(tests.count_rows($$ select count(*) from public.organizations where id = tests.fx('org_b') $$),
  1::bigint, 'dono da org B continua vendo a própria organização');
select is(tests.count_rows($$ select count(*) from public.audit_log where organization_id = tests.fx('org_a') $$),
  0::bigint, 'dono da org B NÃO passa a ler a auditoria da org A');

-- 4. Sobreposição de vínculos inclui a organização ----------------------------
select tests.reset_role();
select matches(
  (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'memberships_no_overlap'),
  'organization_id WITH =',
  'memberships_no_overlap compara também a organização'
);

select * from finish();
rollback;
