-- =============================================================================
-- 125 · Regressão R2-REGRAS-02 (correção incompleta de R1-REGRAS-01/R1-FI-05):
-- tarefa criada pela API não nasce com prazo vencido (deadline_locked), então
-- o gerente não infla a nota de um período já fechado. A criação pela API
-- fica no audit_log; a geração pelo sistema (sem usuário) continua livre.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(7);

select tests.create_base_fixture();

create function tests.r2_d0() returns date language sql stable as
$$ select (now() at time zone 'America/Sao_Paulo')::date - 10 $$;
grant execute on function tests.r2_d0() to public;

-- Tarefa original de D0: vencida e não feita (criada pelo sistema na época)
insert into public.tasks (id, organization_id, store_id, sector_id, title, weight, assignee_id,
                          window_start_at, due_at, created_at)
values (tests.fx('r2r_orig'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Abertura', 5,
        tests.fx('staff_p1'),
        (tests.r2_d0() + time '07:30') at time zone 'America/Sao_Paulo',
        (tests.r2_d0() + time '08:15') at time zone 'America/Sao_Paulo',
        (tests.r2_d0() + time '00:05') at time zone 'America/Sao_Paulo');
update public.tasks set status = 'overdue' where id = tests.fx('r2r_orig');

select tests.authenticate_as('owner_a');
select results_eq(
  $$ select volume, peso_total, nota from public.weighted_scores(tests.r2_d0(), tests.r2_d0(), 'store') $$,
  $$ values (1, 5, 0.0) $$,
  'linha de base: D0 com 1 tarefa vencida, nota 0.0');

-- Gerente cria hoje uma tarefa com prazo em D0 (10 dias atrás)
select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, title, weight, requires_approval,
                                     assignee_id, due_at)
            values (%L, %L, %L, 'Abertura (refeita)', 5, false, %L,
                    (tests.r2_d0() + time '08:15') at time zone 'America/Sao_Paulo') $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('staff_p1')),
  'P0001', 'deadline_locked',
  'tarefa nova não pode nascer com prazo no passado'
);
select throws_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, title, due_at)
            values (%L, %L, %L, 'Prazo agora', now()) $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1')),
  'P0001', 'deadline_locked',
  'nem com prazo igual ao instante atual'
);
-- Controle: tarefa avulsa com prazo futuro é criada e auditada
select is(tests.exec_result(format(
  $$ insert into public.tasks (organization_id, store_id, sector_id, title, assignee_id, due_at)
     values (%L, %L, %L, 'Avulsa futura', %L, now() + interval '2 hours') $$,
  tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('staff_p1'))), 'ok',
  'tarefa avulsa com prazo no futuro é criada');

select tests.authenticate_as('owner_a');
select results_eq(
  $$ select volume, peso_total, nota from public.weighted_scores(tests.r2_d0(), tests.r2_d0(), 'store') $$,
  $$ values (1, 5, 0.0) $$,
  'nota da Loja P em D0 não muda depois do fato');
select results_eq(
  $$ select previstas, aprovadas from public.kpi_summary(tests.r2_d0(), tests.r2_d0()) $$,
  $$ values (1, 0) $$,
  'kpi_summary de D0 não ganha aprovada retroativa');
select results_eq(
  $$ select l.actor_id, l.action, l.diff -> 'title' ->> 'new'
     from public.audit_log l join public.tasks t on t.id::text = l.record_id
     where l.table_name = 'tasks' and t.title = 'Avulsa futura' $$,
  format($$ values (%L::uuid, 'insert'::text, 'Avulsa futura'::text) $$, tests.fx('manager_p')),
  'a criação da tarefa pela API fica no audit_log (autor, ação e dados)');

select * from finish();
rollback;
