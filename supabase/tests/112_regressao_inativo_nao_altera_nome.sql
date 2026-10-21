-- =============================================================================
-- 112 · Regressão R2-ISO-04: pessoa desativada ou com vínculo encerrado não
-- altera mais o próprio nome (que aparece no histórico para a organização).
-- Correção depois disso: pedido do titular (data_requests, kind correction).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(5);

select tests.create_base_fixture();

-- staff_p1 desativado; vínculo de staff_c1 encerrado agora
update public.profiles set status = 'inactive' where id = tests.fx('staff_p1');
update public.memberships set ends_at = now() where id = tests.fx('m_staff_c1');

select tests.authenticate_as('staff_p1');
select is(tests.rows_result($$ update public.profiles set full_name = 'Gerente P (oficial)' where id = auth.uid() $$), 0,
  'pessoa desativada NÃO altera o próprio nome');
select tests.authenticate_as('staff_c1');
select is(tests.rows_result($$ update public.profiles set full_name = 'Proprietária' where id = auth.uid() $$), 0,
  'pessoa com vínculo encerrado (ends_at = now()) NÃO altera o próprio nome');

-- Controle: quem tem vínculo vigente altera
select tests.authenticate_as('staff_p2');
select is(tests.rows_result($$ update public.profiles set full_name = '[TESTE] Colaboradora P2' where id = auth.uid() $$), 1,
  'pessoa ativa com vínculo vigente altera o próprio nome');

select tests.authenticate_as('manager_p');
select is((select full_name from public.profiles where id = tests.fx('staff_p1')), '[TESTE] Colaborador P1',
  'gerente P continua vendo o nome original da pessoa desativada');
select tests.authenticate_as('manager_c');
select is((select full_name from public.profiles where id = tests.fx('staff_c1')), '[TESTE] Colaborador C1',
  'gerente C continua vendo o nome original de quem saiu');

select * from finish();
rollback;
