-- =============================================================================
-- 111 · Regressão R2-ISO-03 / R2-FUNC-08: pedido do titular (LGPD).
-- Quem concluiu (resolved_by) e quando (resolved_at) são gravados pelo sistema
-- quando a situação vira done/rejected: o admin não informa outra pessoa (de
-- outra organização ou a proprietária) como autora da conclusão, e o FK não
-- revela se um id de perfil existe. Abertura e tratamento vão para o audit_log.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(9);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('b');

select tests.authenticate_as('admin_a');
select throws_ok(format(
  $$ update public.data_requests set status = 'done', resolution = 'Dados exportados', resolved_by = %L where id = %L $$,
  tests.fx('owner_b'), tests.fx('dr_p')),
  '42501', null, 'admin NÃO informa quem resolveu (sem privilégio na coluna resolved_by)');
select throws_ok(format(
  $$ update public.data_requests set resolved_at = '2020-01-01' where id = %L $$, tests.fx('dr_p')),
  '42501', null, 'admin NÃO informa quando foi resolvido');
select throws_ok(format(
  $$ update public.data_requests set resolved_by = %L where id = %L $$, gen_random_uuid(), tests.fx('dr_p')),
  '42501', null, 'perfil inexistente dá o mesmo erro (sem oráculo pelo FK)');

-- Caminho legítimo: o admin conclui sem informar o autor
select is(tests.rows_result(format(
  $$ update public.data_requests set status = 'done', resolution = 'Exportação enviada' where id = %L $$, tests.fx('dr_p'))),
  1, 'admin conclui o pedido');
select tests.reset_role();
select results_eq(
  format($$ select status, resolved_by, resolved_at = now() from public.data_requests where id = %L $$, tests.fx('dr_p')),
  format($$ values ('done'::text, %L::uuid, true) $$, tests.fx('admin_a')),
  'resolved_by = quem concluiu (o admin logado) e resolved_at = agora');

-- Uma nova edição do texto não troca o autor da conclusão
select tests.authenticate_as('admin_a');
select is(tests.rows_result(format(
  $$ update public.data_requests set resolution = 'Exportação reenviada' where id = %L $$, tests.fx('dr_p'))),
  1, 'admin corrige a resposta');
select tests.reset_role();
select is((select resolved_by from public.data_requests where id = tests.fx('dr_p')), tests.fx('admin_a'),
  'o autor da conclusão não muda');

-- A chave secreta também não forja o autor (sem usuário logado = sistema)
select tests.authenticate_service_role();
update public.data_requests set status = 'rejected', resolved_by = tests.fx('owner_a') where id = tests.fx('dr_b');
select tests.reset_role();
select is((select resolved_by from public.data_requests where id = tests.fx('dr_b')), null::uuid,
  'chave secreta conclui como sistema (autor nulo), nunca outra pessoa');

select ok(
  exists (select 1 from public.audit_log
          where table_name = 'data_requests' and record_id = tests.fx('dr_p')::text and action = 'update'
            and actor_id = tests.fx('admin_a') and diff -> 'status' ->> 'new' = 'done'),
  'a conclusão do pedido do titular fica no audit_log, com o autor');

select * from finish();
rollback;
