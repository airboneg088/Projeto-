-- =============================================================================
-- 113 · Regressão R2-ISO-05: conta sem organização declarada
-- (app_metadata.organization_id) não é "capturada" pela primeira organização
-- que a vincular. Pela API, o 1º vínculo exige a conta criada para ESTA
-- organização (D21); quem cria a conta com a chave secreta grava a organização.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(6);

select tests.create_base_fixture();
select tests.create_user('novata', '[TESTE] Novata da loja P');           -- sem organização
select tests.create_user('novata_a', '[TESTE] Novata da org A', 'org_a'); -- criada para a org A

select tests.authenticate_as('owner_b');
select alike(tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
     values (%L, %L, %L, %L, 'staff') $$,
  tests.fx('novata'), tests.fx('org_b'), tests.fx('store_b'), tests.fx('sector_b1'))),
  '23514:profile_other_organization%',
  'proprietária da org B NÃO vincula conta que não foi criada para a org B');
select alike(tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
     values (%L, %L, %L, %L, 'staff') $$,
  tests.fx('novata_a'), tests.fx('org_b'), tests.fx('store_b'), tests.fx('sector_b1'))),
  '23514:profile_other_organization%',
  'nem conta criada para a org A');

select tests.reset_role();
select is((select count(*) from public.memberships where profile_id = tests.fx('novata')), 0::bigint,
  'a conta sem organização declarada não ficou presa à org B');

-- A org A vincula a conta criada para ela (admin e proprietária)
select tests.authenticate_as('admin_a');
select is(tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
     values (%L, %L, %L, %L, 'staff') $$,
  tests.fx('novata_a'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'))),
  'ok', 'admin da org A vincula a conta criada para a org A');
select alike(tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
     values (%L, %L, %L, %L, 'staff') $$,
  tests.fx('novata'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'))),
  '23514:profile_other_organization%',
  'conta sem organização declarada também não é vinculada pela org A pela API');

-- O sistema (chave secreta/seed) pode dar o 1º vínculo a uma conta antiga sem metadata
select tests.authenticate_service_role();
select is(tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
     values (%L, %L, %L, %L, 'staff') $$,
  tests.fx('novata'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'))),
  'ok', 'a chave secreta vincula conta sem organização declarada');

select * from finish();
rollback;
