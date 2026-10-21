-- =============================================================================
-- 121 · Regressão R2-FUNC-11: a organização nunca fica sem proprietária.
-- Encerrar, agendar o fim, adiar o início ou apagar o último vínculo vigente de
-- proprietária é recusado (last_owner), para qualquer papel. Com outra
-- proprietária vigente e sem fim, pode.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(9);

select tests.create_base_fixture();

select tests.authenticate_as('owner_a');
select throws_ok($$ update public.memberships set ends_at = now() + interval '1 second' where id = tests.fx('m_owner_a') $$,
  '23514', 'last_owner', 'a única proprietária não encerra (nem agenda o fim do) próprio vínculo');
select throws_ok($$ update public.memberships set starts_at = now() + interval '1 year' where id = tests.fx('m_owner_a') $$,
  '23514', 'last_owner', 'a única proprietária não adia o próprio vínculo');
select tests.reset_role();
select throws_ok($$ delete from public.memberships where id = tests.fx('m_owner_a') $$,
  '23514', 'last_owner', 'nem o postgres apaga o último vínculo de proprietária');
select tests.authenticate_service_role();
select throws_ok($$ update public.memberships set ends_at = now() where id = tests.fx('m_owner_a') $$,
  '23514', 'last_owner', 'nem a chave secreta encerra o último vínculo de proprietária');

select tests.reset_role();
select ok(
  (select ends_at is null and starts_at <= now() from public.memberships where id = tests.fx('m_owner_a')),
  'o único vínculo de proprietária da org A continua vigente e sem fim');
select tests.authenticate_as('owner_a');
select ok((select private.is_owner()), 'a proprietária continua com acesso de proprietária');

-- Com uma segunda proprietária, a primeira pode sair
select tests.reset_role();
select tests.create_user('owner_a2', '[TESTE] Dona A2', 'org_a');
select tests.authenticate_as('owner_a');
select is(tests.exec_result(format(
  $$ insert into public.memberships (profile_id, organization_id, store_id, role) values (%L, %L, null, 'owner') $$,
  tests.fx('owner_a2'), tests.fx('org_a'))), 'ok', 'a proprietária cadastra outra proprietária');
select is(tests.rows_result($$ update public.memberships set ends_at = now() + interval '1 hour' where id = tests.fx('m_owner_a') $$),
  1, 'com outra proprietária vigente, o vínculo pode ser encerrado');
select tests.authenticate_as('owner_a2');
select throws_ok(format(
  $$ update public.memberships set ends_at = now() + interval '1 day'
     where profile_id = %L and role = 'owner' $$, tests.fx('owner_a2')),
  '23514', 'last_owner', 'a segunda não encerra o próprio vínculo se a primeira já tem fim marcado');

select * from finish();
rollback;
