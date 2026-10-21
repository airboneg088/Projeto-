-- =============================================================================
-- 129 · Regressão R2-REGRAS-06: "todos os itens respondidos" (docs §2). Item
-- desmarcado COM observação é uma resposta ("não conforme"): o envio é aceito
-- e a tentativa vai para o gerente decidir, mesmo em tarefa sem exigência de
-- aprovação. Item desmarcado sem observação continua "não respondido".
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(7);
select tests.create_base_fixture();
select tests.create_task('r2nc', 'store_p', 'sector_p1', 'staff_p1');
select tests.create_task('r2nc_auto', 'store_p', 'sector_p1', 'staff_p1', p_requires_approval => false);
select tests.create_task('r2nc_vazio', 'store_p', 'sector_p1', 'staff_p1');

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('r2nc'), gen_random_uuid()) is not null as iniciada;
select public.answer_item(tests.attempt_of('r2nc', 1), tests.fx('r2nc:item1'), false, 'Alarme com defeito, técnico chamado');
select public.answer_item(tests.attempt_of('r2nc', 1), tests.fx('r2nc:item2'), true);
select lives_ok(
  format($$ select public.submit_attempt(%L) $$, tests.attempt_of('r2nc', 1)),
  'todos os itens respondidos (um deles "não", com observação): o envio é aceito');
select is((select status::text from public.tasks where id = tests.fx('r2nc')), 'submitted',
  'a tentativa chega ao gerente com o item não conforme');

-- Sem exigência de aprovação: com item não conforme, não é auto-aprovada
select public.start_attempt(tests.fx('r2nc_auto'), gen_random_uuid()) is not null as iniciada;
select public.answer_item(tests.attempt_of('r2nc_auto', 1), tests.fx('r2nc_auto:item1'), false, 'Faltou produto no estoque');
select public.answer_item(tests.attempt_of('r2nc_auto', 1), tests.fx('r2nc_auto:item2'), true);
select is(public.submit_attempt(tests.attempt_of('r2nc_auto', 1))::text, 'submitted',
  'tarefa sem exigência de aprovação, com item não conforme, vai para o gerente (não é auto-aprovada)');
select is((select count(*) from public.reviews where task_id = tests.fx('r2nc_auto')), 0::bigint,
  'nenhuma revisão automática foi gravada');

-- Desmarcado sem observação = não respondido
select public.start_attempt(tests.fx('r2nc_vazio'), gen_random_uuid()) is not null as iniciada;
select public.answer_item(tests.attempt_of('r2nc_vazio', 1), tests.fx('r2nc_vazio:item1'), false, '   ');
select public.answer_item(tests.attempt_of('r2nc_vazio', 1), tests.fx('r2nc_vazio:item2'), true);
select throws_ok(
  format($$ select public.submit_attempt(%L) $$, tests.attempt_of('r2nc_vazio', 1)),
  'P0001', 'items_incomplete', 'item desmarcado sem observação continua sem resposta');

-- O gerente vê o item não conforme e decide
select tests.authenticate_as('manager_p');
select results_eq(
  format($$ select checked, note from public.attempt_item_answers where attempt_id = %L and task_item_id = %L $$,
         tests.attempt_of('r2nc', 1), tests.fx('r2nc:item1')),
  $$ values (false, 'Alarme com defeito, técnico chamado'::text) $$,
  'gerente lê o item não conforme com a observação');
select is(public.review_attempt(tests.attempt_of('r2nc', 1), 'approved')::text, 'approved',
  'gerente aprova (o problema foi tratado)');

select * from finish();
rollback;
