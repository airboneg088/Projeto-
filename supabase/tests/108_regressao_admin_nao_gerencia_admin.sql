-- =============================================================================
-- 108 · Regressão R2-ISO-07 / R2-FUNC-01: vínculo de admin (e de proprietária)
-- só a proprietária cria, encerra, estende ou reabre. Um admin não derruba os
-- outros admins, não readmite um admin que a proprietária tirou e não cria
-- admins novos (D23). Admin continua cuidando de gerentes e colaboradores.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(13);

select tests.create_base_fixture();
select tests.create_user('admin_a2', '[TESTE] Admin A2', 'org_a');
select tests.create_membership('admin_a2', 'org_a', null, null, 'admin');
select tests.create_user('admin_a3', '[TESTE] Admin A3 (demitido)', 'org_a');
select tests.create_membership('admin_a3', 'org_a', null, null, 'admin');
select tests.create_user('admin_a4', '[TESTE] Admin A4', 'org_a');
select tests.create_membership('admin_a4', 'org_a', null, null, 'admin');
select tests.create_user('livre', '[TESTE] Conta nova da org A', 'org_a');

-- A proprietária tira o admin A3
select tests.authenticate_as('owner_a');
select is(tests.rows_result(format(
  $$ update public.memberships set ends_at = now() where id = %L $$, tests.fx('m_admin_a3'))), 1,
  'controle: a proprietária encerra o vínculo do admin A3');

select tests.authenticate_as('admin_a');
select cmp_ok(tests.rows_result(format(
  $$ update public.memberships set ends_at = now() + interval '1 minute' where id = %L $$, tests.fx('m_admin_a2'))),
  '<=', 0, 'admin NÃO encerra o vínculo de outro admin (só a proprietária)');
select cmp_ok(tests.rows_result(format(
  $$ update public.memberships set ends_at = null where id = %L $$, tests.fx('m_admin_a3'))),
  '<=', 0, 'admin NÃO reabre o vínculo de um admin tirado pela proprietária');
select cmp_ok(tests.rows_result(format(
  $$ update public.memberships set starts_at = now() + interval '10 years' where id = %L $$, tests.fx('m_admin_a4'))),
  '<=', 0, 'admin NÃO adia (desliga) o vínculo de outro admin');
select cmp_ok(tests.rows_result(format(
  $$ update public.memberships set ends_at = now() + interval '5 years' where id = %L $$, tests.fx('m_admin_a3'))),
  '<=', 0, 'admin NÃO estende o vínculo de outro admin');
select isnt(tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, role) values (%L, %L, null, 'admin') $$,
  tests.fx('livre'), tests.fx('org_a'))), 'ok',
  'admin NÃO cria vínculo de admin (só a proprietária dá papel de rede)');
-- Controle: gerente e colaborador continuam com o admin
select is(tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role) values (%L, %L, %L, %L, 'staff') $$,
  tests.fx('livre'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'))), 'ok',
  'admin continua cadastrando vínculo de colaborador');

select tests.reset_role();
select is((select ends_at is null from public.memberships where id = tests.fx('m_admin_a2')), true,
  'o vínculo do admin A2 continua sem fim');
select is((select ends_at is not null and ends_at <= now() from public.memberships where id = tests.fx('m_admin_a3')), true,
  'o admin A3 continua fora');
select is((select starts_at < now() from public.memberships where id = tests.fx('m_admin_a4')), true,
  'o vínculo do admin A4 continua vigente');
select is((select count(*) from public.memberships where profile_id = tests.fx('livre') and role = 'admin'), 0::bigint,
  'nenhum admin novo foi criado pelo admin');

-- A proprietária continua gerenciando os admins
select tests.authenticate_as('owner_a');
select is(tests.rows_result(format(
  $$ update public.memberships set ends_at = now() + interval '1 day' where id = %L $$, tests.fx('m_admin_a2'))), 1,
  'a proprietária agenda o fim do vínculo de um admin');
select is(tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, role) values (%L, %L, null, 'admin') $$,
  tests.fx('admin_a3'), tests.fx('org_a'))), 'ok',
  'a proprietária readmite o admin A3 com um vínculo novo');

select * from finish();
rollback;
