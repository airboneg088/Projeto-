-- =============================================================================
-- 102 · Regressão R1-FI-08 / R2-FUNC-06: os eventos do app não gravam payload
-- arbitrário no audit_log (append-only, nunca limpo).
--   export (log_event, gerente/proprietária): objeto de até 2 KB, só com as
--     chaves formato, escopo, filtros, periodo, linhas e valores simples.
--   admin_login (log_admin_login): só a chave secreta grava (o servidor, logo
--     depois do login); ip só se for endereço válido, user_agent cortado e no
--     máximo um registro por admin por minuto.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(12);

select tests.create_base_fixture();

select tests.authenticate_as('manager_p');
select throws_ok(
  $$ select public.log_event('export', jsonb_build_object('formato', repeat('x', 2000000))) $$,
  'P0001', 'invalid_details', 'gerente NÃO grava 2 MB no audit_log via log_event');
select throws_ok(
  $$ select public.log_event('export', '{"action":"task_cancelled","table_name":"tasks","actor":"owner_a"}'::jsonb) $$,
  'P0001', 'invalid_details', 'detalhes de export com chaves fora do formato (imitando outro evento) são recusados');
select throws_ok(
  $$ select public.log_event('export', '["formato", "csv"]'::jsonb) $$,
  'P0001', 'invalid_details', 'detalhes que não são objeto são recusados');
select throws_ok(
  $$ select public.log_event('export', jsonb_build_object('filtros', jsonb_build_object('x', repeat('a', 1900)))) $$,
  'P0001', 'invalid_details', 'valor aninhado (objeto) é recusado');
select lives_ok(
  $$ select public.log_event('export', '{"formato": "xlsx", "escopo": "loja", "filtros": "setor=Caixa", "linhas": 120}'::jsonb) $$,
  'export com as chaves conhecidas e valores simples é aceito');

-- admin_login: nunca pelo navegador
select tests.authenticate_as('admin_a');
select throws_ok(
  $$ select public.log_event('admin_login', '{"ip": "203.0.113.9", "user_agent": "forjado"}'::jsonb) $$,
  'P0001', 'forbidden', 'admin NÃO grava login pela API com ip/user_agent escolhidos por ele');
select throws_ok(
  format($$ select public.log_admin_login(%L, '203.0.113.9', 'forjado') $$, tests.fx('admin_a')),
  '42501', null, 'admin NÃO chama log_admin_login (só a chave secreta)');

-- Pelo servidor (chave secreta)
select tests.authenticate_service_role();
select is(public.log_admin_login(tests.fx('manager_p'), '127.0.0.1', 'Teste'), false,
  'quem não é admin vigente não gera registro de login de admin');
select is(public.log_admin_login(tests.fx('admin_a'), 'não é ip', repeat('a', 5000)), true,
  'servidor registra o login do admin');
select is(public.log_admin_login(tests.fx('admin_a'), '127.0.0.1', 'Teste'), false,
  'segundo login no mesmo minuto não gera outro registro');

select tests.reset_role();
select results_eq(
  $$ select diff ? 'ip', char_length(diff ->> 'user_agent') from public.audit_log where action = 'admin_login' $$,
  $$ values (false, 300) $$,
  'ip inválido não é gravado e o user_agent é cortado em 300 caracteres'
);
select is(
  (select count(*) from public.audit_log where action in ('export', 'admin_login')),
  2::bigint,
  'só os 2 eventos válidos foram gravados'
);

select * from finish();
rollback;
