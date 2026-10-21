-- =============================================================================
-- 141 · Regressão R3-REGRAS-02: "% aprovadas na 1ª tentativa" conta o primeiro
-- ENVIO (D73). A tentativa encerrada sem envio numa passagem da tarefa (D52)
-- continua numerada no histórico, mas não é execução de ninguém: a tarefa
-- aprovada no único envio de quem a recebeu conta como aprovada na 1ª tentativa,
-- para a loja e para a pessoa. Reprovada e refeita continua não contando.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(5);

select tests.create_base_fixture();
select tests.create_task('pt', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.create_task('pt_rep', 'store_p', 'sector_p2', 'staff_p2', p_items => 1);

-- pt: staff_p1 inicia; o gerente passa a tarefa para staff_p2, que envia uma vez e é aprovado
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('pt'), gen_random_uuid());
select tests.authenticate_as('manager_p');
update public.tasks set assignee_id = tests.fx('staff_p2') where id = tests.fx('pt');
select tests.authenticate_as('staff_p2');
select public.start_attempt(tests.fx('pt'), gen_random_uuid());
select public.answer_item(tests.attempt_of('pt', 2), tests.fx('pt:item1'), true);
select public.submit_attempt(tests.attempt_of('pt', 2));

-- pt_rep: staff_p2 envia, é reprovado, refaz e é aprovado (2º envio)
select public.start_attempt(tests.fx('pt_rep'), gen_random_uuid());
select public.answer_item(tests.attempt_of('pt_rep', 1), tests.fx('pt_rep:item1'), true);
select public.submit_attempt(tests.attempt_of('pt_rep', 1));
select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('pt', 2), 'approved');
select public.review_attempt(tests.attempt_of('pt_rep', 1), 'rejected', 'Refazer');
select tests.authenticate_as('staff_p2');
select public.start_attempt(tests.fx('pt_rep'), gen_random_uuid());
select public.answer_item(tests.attempt_of('pt_rep', 2), tests.fx('pt_rep:item1'), true);
select public.submit_attempt(tests.attempt_of('pt_rep', 2));
select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('pt_rep', 2), 'approved');

select tests.reset_role();
select results_eq(
  format($$ select attempt_number, abandoned_reason, submitted_at is not null from public.task_attempts
            where task_id = %L order by attempt_number $$, tests.fx('pt')),
  $$ values (1::smallint, 'reassigned'::text, false), (2::smallint, null::text, true) $$,
  'sanidade: a tentativa 1 (encerrada sem envio) continua numerada no histórico');

select tests.authenticate_as('owner_a');
select is(
  (select pct_aprovadas_primeira_tentativa from public.kpi_summary(current_date - 2, current_date + 2, null, null, null)),
  50.0::numeric,
  'loja: pt (aprovada no 1º envio, depois da passagem) conta; pt_rep (aprovada no 2º envio) não: 1/2');
select is(
  (select pct_aprovadas_primeira_tentativa from public.kpi_summary(current_date - 2, current_date + 2, null, null,
                                                                   array[tests.fx('staff_p2')])),
  50.0::numeric,
  'pessoa (staff_p2): a aprovação no 1º envio dela conta como 1ª tentativa');

-- Só a tarefa da passagem (setor P1): 100%, não 0%
select is(
  (select pct_aprovadas_primeira_tentativa
   from public.kpi_summary(current_date - 2, current_date + 2, null, array[tests.fx('sector_p1')], null)),
  100.0::numeric,
  'a tarefa aprovada no único envio, depois da passagem, conta como aprovada na 1ª tentativa (100%, não 0%)');
select tests.reset_role();
select is(
  (select count(*)::int from public.task_attempts a where a.task_id = tests.fx('pt') and a.submitted_at is not null),
  1, 'sanidade: pt teve um único envio');

select * from finish();
rollback;
