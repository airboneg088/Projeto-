-- =============================================================================
-- 127 · Regressão R2-REGRAS-04: reatribuir uma tarefa vencida (permitido, D27)
-- não move a falha de pessoa. Na primeira reatribuição depois do prazo, o
-- banco grava quem era o responsável no prazo (assignee_at_due), e a nota por
-- pessoa e o filtro de pessoa do kpi_summary usam esse responsável.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(9);

select tests.create_base_fixture();

-- Tarefa de staff_p1 com prazo 2 dias atrás, nunca feita
insert into public.tasks (id, organization_id, store_id, sector_id, title, weight, assignee_id,
                          window_start_at, due_at, created_at)
values (tests.fx('r2a_t'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Caixa', 5,
        tests.fx('staff_p1'), now() - interval '2 days 1 hour', now() - interval '2 days', now() - interval '2 days 2 hours');
update public.tasks set status = 'overdue' where id = tests.fx('r2a_t');
-- Tarefa de equipe, vencida e nunca feita
insert into public.tasks (id, organization_id, store_id, sector_id, title, weight, assignee_id,
                          window_start_at, due_at, created_at)
values (tests.fx('r2a_eq'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p2'), 'Estoque', 3,
        null, now() - interval '2 days 1 hour', now() - interval '2 days', now() - interval '2 days 2 hours');
update public.tasks set status = 'overdue' where id = tests.fx('r2a_eq');

select tests.authenticate_as('owner_a');
select results_eq(
  $$ select group_id, volume, peso_total, nota from public.weighted_scores(current_date - 5, current_date + 1, 'person')
     where group_id is not null $$,
  format($$ values (%L::uuid, 1, 5, 0.0) $$, tests.fx('staff_p1')),
  'linha de base: a falha é de staff_p1');

-- Gerente reatribui as tarefas vencidas (D27 permite)
select tests.authenticate_as('manager_p');
select is(tests.exec_result(format($$ update public.tasks set assignee_id = null where id = %L $$, tests.fx('r2a_t'))),
  'ok', 'gerente reatribui a tarefa vencida para a equipe');
select is(tests.exec_result(format($$ update public.tasks set assignee_id = %L where id = %L $$, tests.fx('staff_p2'), tests.fx('r2a_eq'))),
  'ok', 'gerente atribui a tarefa de equipe vencida a staff_p2');

select tests.authenticate_as('owner_a');
select results_eq(
  $$ select group_id, volume, peso_total, nota from public.weighted_scores(current_date - 5, current_date + 1, 'person')
     where group_id is not null $$,
  format($$ values (%L::uuid, 1, 5, 0.0) $$, tests.fx('staff_p1')),
  'a falha continua na nota de staff_p1 depois da reatribuição (e staff_p2 não herda a de equipe)');
select is(
  (select atrasadas from public.kpi_summary(current_date - 5, current_date + 1, null, null, array[tests.fx('staff_p1')])),
  1, 'kpi_summary filtrado por staff_p1 continua com a tarefa atrasada');

-- Segunda reatribuição: continua valendo o responsável no prazo
select tests.authenticate_as('manager_p');
select is(tests.exec_result(format($$ update public.tasks set assignee_id = %L where id = %L $$, tests.fx('staff_p2'), tests.fx('r2a_t'))),
  'ok', 'gerente reatribui de novo, agora para staff_p2');
select tests.authenticate_as('owner_a');
select is(
  (select count(*)::int from public.weighted_scores(current_date - 5, current_date + 1, 'person')
    where group_id = tests.fx('staff_p2')),
  0, 'staff_p2 não herda a falha de um prazo que venceu antes de ela ser escalada');

select tests.reset_role();
select results_eq(
  format($$ select assignee_at_due, assignee_at_due_recorded from public.tasks where id = %L $$, tests.fx('r2a_t')),
  format($$ values (%L::uuid, true) $$, tests.fx('staff_p1')),
  'o banco guardou o responsável no prazo');
select ok(
  not has_column_privilege('authenticated', 'public.tasks', 'assignee_at_due', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.tasks', 'assignee_at_due_recorded', 'UPDATE'),
  'o responsável no prazo não é gravável pela API');

select * from finish();
rollback;
