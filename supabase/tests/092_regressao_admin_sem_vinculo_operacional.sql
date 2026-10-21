-- =============================================================================
-- 092 · Regressão R1-ISO-03 e R1-FI-04: admin não se dá vínculo operacional
-- (gerente/colaborador) e não re-aponta vínculo de outra pessoa para si, então
-- continua lendo operação só por admin_read_* (D15) e sem escrever nada.
-- Admin também não mistura papel de rede com papel operacional em outra pessoa.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(15);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_user('admin_a2', '[TESTE] Admin A2', 'org_a');
select tests.create_membership('admin_a2', 'org_a', null, null, 'admin');
select tests.create_user('novo_a', '[TESTE] Pessoa nova da org A', 'org_a');

select tests.authenticate_as('admin_a');
select is(tests.count_rows($$ select count(*) from public.tasks $$), 0::bigint,
  'pré-condição: admin não lê tarefas direto');

-- Vínculos para si mesmo ---------------------------------------------------------
select cmp_ok(
  tests.rows_result(format($$ insert into public.memberships (profile_id, organization_id, store_id, role)
                           values (%L, %L, %L, 'manager') $$, tests.fx('admin_a'), tests.fx('org_a'), tests.fx('store_p'))),
  '<=', 0, 'admin NÃO cria vínculo de gerente para si mesmo');
select cmp_ok(
  tests.rows_result(format($$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
                           values (%L, %L, %L, %L, 'staff') $$,
                        tests.fx('admin_a'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'))),
  '<=', 0, 'admin NÃO cria vínculo de colaborador para si mesmo');
select cmp_ok(
  tests.rows_result(format($$ update public.memberships set role = 'manager', store_id = %L
                           where id = tests.fx('m_admin_a') $$, tests.fx('store_p'))),
  '<=', 0, 'admin NÃO transforma o próprio vínculo em gerente de loja');
select cmp_ok(
  tests.rows_result(format($$ update public.memberships set profile_id = %L where id = %L $$,
                        tests.fx('admin_a'), tests.fx('m_manager_c'))),
  '<=', 0, 'admin NÃO re-aponta o vínculo de um gerente para si');

-- Papel de rede e operacional não se misturam (pelo admin) -----------------------
select cmp_ok(
  tests.rows_result(format($$ insert into public.memberships (profile_id, organization_id, store_id, role)
                           values (%L, %L, %L, 'manager') $$, tests.fx('admin_a2'), tests.fx('org_a'), tests.fx('store_p'))),
  '<=', 0, 'admin NÃO dá vínculo de gerente a outro admin');
select cmp_ok(
  tests.rows_result(format($$ insert into public.memberships (profile_id, organization_id, store_id, role)
                           values (%L, %L, null, 'admin') $$, tests.fx('manager_p'), tests.fx('org_a'))),
  '<=', 0, 'admin NÃO dá papel de admin a um gerente');
select is(
  tests.rows_result(format($$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
                           values (%L, %L, %L, %L, 'staff') $$,
                        tests.fx('novo_a'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'))),
  1, 'admin continua cadastrando vínculo de colaborador para outra pessoa');

-- Consequências: nada de leitura ou escrita operacional direta -------------------
select is(tests.count_rows($$ select count(*) from public.tasks $$), 0::bigint,
  'admin continua sem ler tarefas direto');
select is(tests.count_rows($$ select count(*) from public.evidences $$), 0::bigint,
  'admin continua sem ler evidências direto');
select is(tests.count_rows($$ select count(*) from storage.objects where bucket_id = 'evidences' $$), 0::bigint,
  'admin continua sem ler fotos de evidência no storage');
select throws_ok($$ select public.review_attempt(tests.fx('att_p_sub'), 'approved') $$,
  'P0001', 'forbidden', 'admin NÃO aprova tentativa');
select throws_ok($$ select public.cancel_task(tests.fx('task_p'), 'Cancelada pelo admin') $$,
  'P0001', 'forbidden', 'admin NÃO cancela tarefa');

-- A proprietária pode dar a quem quiser (inclusive a um admin), e fica auditado
select tests.authenticate_as('owner_a');
select is(
  tests.rows_result(format($$ insert into public.memberships (profile_id, organization_id, store_id, role)
                           values (%L, %L, %L, 'manager') $$, tests.fx('admin_a2'), tests.fx('org_a'), tests.fx('store_c'))),
  1, 'proprietária pode dar vínculo de gerente a um admin');
select tests.reset_role();
select is(
  (select count(*) from public.audit_log
   where table_name = 'memberships' and action = 'insert' and actor_id = tests.fx('owner_a')),
  1::bigint, 'o vínculo dado pela proprietária fica no audit_log');

select * from finish();
rollback;
