-- =============================================================================
-- 091 · Regressão R1-ISO-02, R1-FI-01 e R1-FI-03: admin (suporte) não rebaixa,
-- não encerra e não desativa a proprietária (nem outro admin).
--   - No UPDATE de memberships só mudam setor e período (privilégio de coluna):
--     papel, loja, pessoa e organização não mudam (troca = encerrar e abrir).
--   - A policy de UPDATE exige no USING (linha atual) o mesmo que no WITH
--     CHECK: vínculo de proprietária só a proprietária altera.
--   - set_profile_status recusa proprietária e admin como alvo.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(16);

select tests.create_base_fixture();
select tests.create_user('admin_a2', '[TESTE] Admin A2', 'org_a');
select tests.create_membership('admin_a2', 'org_a', null, null, 'admin');

select tests.authenticate_as('admin_a');

-- Vínculo da proprietária -----------------------------------------------------
select cmp_ok(
  tests.rows_result($$ update public.memberships set role = 'admin' where profile_id = tests.fx('owner_a') $$),
  '<=', 0, 'admin NÃO rebaixa o vínculo da proprietária (owner -> admin)');
select cmp_ok(
  tests.rows_result($$ update public.memberships set role = 'admin', ends_at = now() + interval '1 minute'
                    where profile_id = tests.fx('owner_a') $$),
  '<=', 0, 'admin NÃO encerra o vínculo da proprietária trocando o papel junto');
select cmp_ok(
  tests.rows_result($$ update public.memberships set role = 'manager', store_id = tests.fx('store_p')
                    where id = tests.fx('m_owner_a') $$),
  '<=', 0, 'admin NÃO converte o vínculo da proprietária em gerente');
select is(
  tests.rows_result($$ update public.memberships set ends_at = now() + interval '1 minute' where id = tests.fx('m_owner_a') $$),
  0, 'admin NÃO encerra o vínculo da proprietária (a linha atual de owner fica fora do alcance)');
select throws_ok(
  $$ update public.memberships set role = 'manager' where id = tests.fx('m_staff_p1') $$,
  '42501', null, 'papel não muda por UPDATE nem em vínculo comum (troca = encerrar e abrir outro)');

-- Situação da pessoa ------------------------------------------------------------
select throws_ok($$ select public.set_profile_status(tests.fx('owner_a'), 'inactive') $$,
  'P0001', 'forbidden', 'admin NÃO desativa a proprietária');
select throws_ok($$ select public.set_profile_status(tests.fx('admin_a2'), 'inactive') $$,
  'P0001', 'forbidden', 'admin NÃO desativa outro admin');
select lives_ok($$ select public.set_profile_status(tests.fx('staff_p2'), 'inactive') $$,
  'admin continua desativando colaborador da organização');

-- Controle: o admin segue encerrando vínculo de colaborador
select is(tests.affected_rows($$ update public.memberships set ends_at = now() + interval '1 day' where id = tests.fx('m_staff_p1') $$),
  1, 'admin encerra (agenda o fim de) um vínculo de colaborador');

select tests.reset_role();
select is((select role::text from public.memberships where id = tests.fx('m_owner_a')), 'owner',
  'vínculo da proprietária continua owner');
select ok((select ends_at is null and store_id is null from public.memberships where id = tests.fx('m_owner_a')),
  'vínculo da proprietária continua vigente e de rede');
select is((select status::text from public.profiles where id = tests.fx('owner_a')), 'active',
  'perfil da proprietária continua ativo');
select is((select status::text from public.profiles where id = tests.fx('admin_a2')), 'active',
  'perfil do outro admin continua ativo');

select tests.authenticate_as('owner_a');
select ok((select private.is_owner()), 'proprietária continua sendo proprietária depois das tentativas do admin');
-- A proprietária gerencia os admins
select is(tests.affected_rows($$ update public.memberships set ends_at = now() + interval '1 hour' where id = tests.fx('m_admin_a2') $$),
  1, 'proprietária encerra o vínculo de um admin');
-- Única proprietária não encerra o próprio vínculo (R2-FUNC-11: a organização ficaria sem dona)
select throws_ok($$ update public.memberships set ends_at = now() + interval '1 hour' where id = tests.fx('m_owner_a') $$,
  '23514', 'last_owner', 'a única proprietária não encerra o próprio vínculo (last_owner)');

select * from finish();
rollback;
