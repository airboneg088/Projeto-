-- =============================================================================
-- 144 · Regressão R3-FUNCOES-01: o audit_log append-only não é inundado pelas
-- portas abertas ao navegador (D76). O tamanho já era limitado (D38); agora a
-- QUANTIDADE também:
--   - pedido do titular (data_requests): um em andamento por tipo e pessoa
--     (índice data_requests_one_open_per_kind). Um POST em lote do PostgREST é um
--     INSERT só: com 2+ linhas do mesmo tipo, nada é gravado;
--   - log_event('export'): no máximo 10 por minuto e 200 por dia por pessoa
--     (rate_limited); acima disso a exportação é recusada (o Route Handler
--     registra antes de exportar).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(12);

select tests.create_base_fixture();

-- Colaborador: um único comando em lote (equivale a um POST com array no PostgREST)
select tests.authenticate_as('staff_p1');
select is(
  tests.exec_result($$
    insert into public.data_requests (organization_id, profile_id, kind, details)
    select tests.fx('org_a'), tests.fx('staff_p1'), 'export', repeat('Quero meus dados. ', 222)
    from generate_series(1, 500)
  $$),
  '23505:duplicate key value violates unique constraint "data_requests_one_open_per_kind"',
  'lote de 500 pedidos do mesmo tipo é recusado inteiro');
select tests.reset_role();
select is(
  (select count(*)::int from public.audit_log where table_name = 'data_requests' and actor_id = tests.fx('staff_p1')),
  0, 'o lote recusado não deixa nenhuma linha permanente no audit_log');

select tests.authenticate_as('staff_p2');
select is(tests.exec_result($$
    insert into public.data_requests (organization_id, profile_id, kind, details)
    values (tests.fx('org_a'), tests.fx('staff_p2'), 'correction', 'Corrigir meu nome') $$),
  'ok', '1º pedido de correção é aceito');
select isnt(tests.exec_result($$
    insert into public.data_requests (organization_id, profile_id, kind, details)
    values (tests.fx('org_a'), tests.fx('staff_p2'), 'correction', 'Corrigir meu nome de novo') $$),
  'ok', '2º pedido de correção, com o 1º em andamento, é recusado');
select is(tests.exec_result($$
    insert into public.data_requests (organization_id, profile_id, kind, details)
    values (tests.fx('org_a'), tests.fx('staff_p2'), 'export', 'Quero meus dados') $$),
  'ok', 'pedido de outro tipo (exportação) é aceito');

-- Em análise continua contando; depois de concluído, a pessoa pode pedir de novo
select tests.authenticate_as('admin_a');
update public.data_requests set status = 'in_progress' where profile_id = tests.fx('staff_p2') and kind = 'correction';
select tests.authenticate_as('staff_p2');
select isnt(tests.exec_result($$
    insert into public.data_requests (organization_id, profile_id, kind, details)
    values (tests.fx('org_a'), tests.fx('staff_p2'), 'correction', 'De novo') $$),
  'ok', 'pedido em análise (in_progress) também segura um novo do mesmo tipo');
select tests.authenticate_as('admin_a');
update public.data_requests set status = 'done', resolution = 'Nome corrigido'
 where profile_id = tests.fx('staff_p2') and kind = 'correction';
select tests.authenticate_as('staff_p2');
select is(tests.exec_result($$
    insert into public.data_requests (organization_id, profile_id, kind, details)
    values (tests.fx('org_a'), tests.fx('staff_p2'), 'correction', 'Outra correção') $$),
  'ok', 'depois de atendido, a pessoa abre outro pedido do mesmo tipo');

-- Gerente: log_event('export') limitado por minuto
select tests.authenticate_as('manager_p');
create temporary table export_results as
select i, tests.exec_result($$ select public.log_event('export', '{"formato": "csv"}') $$) as r
from generate_series(1, 300) as i;
grant select on export_results to public;
select is((select count(*)::int from export_results where r = 'ok'), 10,
  '300 exportações seguidas: só as 10 do minuto são registradas');
select is((select r from export_results where i = 11), 'P0001:rate_limited',
  'a 11ª do minuto é recusada (rate_limited), e a exportação não acontece sem registro');
select tests.reset_role();
select is((select count(*)::int from public.audit_log where action = 'export' and actor_id = tests.fx('manager_p')), 10,
  'o audit_log ganhou 10 linhas, não 300');

-- ... e por dia (200 em 24 h)
insert into public.audit_log (occurred_at, organization_id, actor_id, action, diff)
select now() - interval '2 hours', tests.fx('org_a'), tests.fx('owner_a'), 'export', '{"formato": "csv"}'
from generate_series(1, 199);
select tests.authenticate_as('owner_a');
select is(tests.exec_result($$ select public.log_event('export', '{"formato": "xlsx"}') $$), 'ok',
  'a 200ª exportação do dia é registrada');
select is(tests.exec_result($$ select public.log_event('export', '{"formato": "xlsx"}') $$), 'P0001:rate_limited',
  'a 201ª exportação do dia é recusada');

select * from finish();
rollback;
