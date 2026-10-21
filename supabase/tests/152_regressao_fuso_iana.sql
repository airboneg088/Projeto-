-- =============================================================================
-- 152 · Regressão R3-REGRAS-04: stores.timezone só aceita fuso IANA no formato
-- Região/Cidade (D87). 'UTC-3', 'GMT-3', '-03' e 'Etc/GMT-3' são entendidos pelo
-- Postgres com o sinal invertido (valem UTC+3) e jogariam todo "dia local da
-- loja" (indicadores, geração por agendamento) 6 h para a frente.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(9);

select tests.create_base_fixture();

select tests.authenticate_as('admin_a');
select throws_ok(format($$ update public.stores set timezone = %L where id = %L $$, z, tests.fx('store_p')),
                 '23514', null, format('%L não é aceito como fuso da loja', z))
from unnest(array['UTC-3', 'GMT-3', '-03', 'Etc/GMT-3', 'BRT', 'posix/America/Sao_Paulo', 'America/Nao_Existe']) as z;
select lives_ok(format($$ update public.stores set timezone = 'America/Manaus' where id = %L $$, tests.fx('store_p')),
  'fuso IANA (America/Manaus) é aceito');
select lives_ok(format($$ update public.stores set timezone = 'America/Sao_Paulo' where id = %L $$, tests.fx('store_p')),
  'fuso IANA (America/Sao_Paulo) é aceito');

select * from finish();
rollback;
