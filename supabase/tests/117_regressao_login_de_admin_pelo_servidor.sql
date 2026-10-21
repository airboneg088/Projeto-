-- =============================================================================
-- 117 · Regressão R2-FUNC-06: o registro de login de admin não fica aberto ao
-- navegador. log_event não aceita mais admin_login; o login é gravado por
-- log_admin_login, que só a chave secreta (o servidor) executa, com valores de
-- texto curtos e no máximo um registro por admin por minuto.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(7);

select tests.create_base_fixture();
create temporary table marca as select coalesce(max(id), 0) as last_id from public.audit_log;
grant select on marca to public;

select tests.authenticate_as('admin_a');
select isnt(
  tests.exec_result($$ select public.log_event('admin_login', '{"ip": "203.0.113.9", "user_agent": "forjado"}') $$),
  'ok', 'admin NÃO grava, pela API, um login com ip/user_agent que ele mesmo escolhe');
select isnt(
  tests.exec_result($$ select public.log_event('admin_login', jsonb_build_object('ip', jsonb_build_object('x', repeat('a', 1900)))) $$),
  'ok', 'detalhes aninhados não passam');
select isnt(
  tests.exec_result(format($$ select public.log_admin_login(%L, '203.0.113.9', 'forjado') $$, tests.fx('admin_a'))),
  'ok', 'admin NÃO chama a função do servidor');
select is(
  tests.exec_result($$ select count(public.log_event('admin_login', '{}')) from generate_series(1, 500) $$) like 'P0001:forbidden%',
  true, '500 chamadas seguidas pela API são recusadas');

-- O servidor (chave secreta) registra o login real; repetições no mesmo minuto não viram linhas
select tests.authenticate_service_role();
select is(
  (select count(*) filter (where r) from (select public.log_admin_login(tests.fx('admin_a'), '198.51.100.7', 'Navegador') as r
                                          from generate_series(1, 500)) x),
  1::bigint, '500 chamadas do servidor no mesmo minuto gravam um registro só');

select tests.reset_role();
select cmp_ok(
  (select count(*) from public.audit_log, marca where id > marca.last_id and action = 'admin_login'),
  '<', 10::bigint, '500 chamadas seguidas não viram 500 registros de login eternos');
select results_eq(
  $$ select actor_id, diff from public.audit_log where action = 'admin_login' $$,
  format($$ values (%L::uuid, '{"ip": "198.51.100.7", "user_agent": "Navegador"}'::jsonb) $$, tests.fx('admin_a')),
  'o registro tem o autor real e só ip e user_agent');

select * from finish();
rollback;
