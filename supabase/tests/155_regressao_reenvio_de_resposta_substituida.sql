-- =============================================================================
-- 155 · Regressão R4-REGRAS-01: o reenvio de um client_mutation_id já aplicado
-- não muda nada, mesmo depois de uma resposta mais nova no mesmo item (D93).
-- Antes, só o id da resposta ATUAL era lembrado: o reenvio do pedido antigo
-- (resposta HTTP perdida, repetido pela fila ou pelo fetch) caía na comparação
-- de horários e voltava a valer quando não havia horário do aparelho (uso
-- online) ou o relógio estava adiantado (limitado a agora). O item "não
-- conforme" voltava a "feito" e a tarefa sem exigência de aprovação era
-- auto-aprovada (contra a D47).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(13);

select tests.create_base_fixture();
-- Tarefas SEM exigência de aprovação (auto-aprovadas quando tudo conforme), 1 item
select tests.create_task('a', 'store_p', 'sector_p1', 'staff_p1', false, false, false, 1);
select tests.create_task('b', 'store_p', 'sector_p1', 'staff_p1', false, false, false, 1);
select tests.create_task('c', 'store_p', 'sector_p1', 'staff_p1', false, false, false, 2);

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('a'), gen_random_uuid()) is not null as iniciada_a;
select public.start_attempt(tests.fx('b'), gen_random_uuid()) is not null as iniciada_b;
select public.start_attempt(tests.fx('c'), gen_random_uuid()) is not null as iniciada_c;

-- Caso A: online, sem horário do aparelho -----------------------------------------
select public.answer_item(tests.attempt_of('a', 1), tests.fx('a:item1'), true, null, tests.fx('cm_a1'));
select public.answer_item(tests.attempt_of('a', 1), tests.fx('a:item1'), false, 'Alarme com defeito',
                          tests.fx('cm_a2'));
select is(
  public.answer_item(tests.attempt_of('a', 1), tests.fx('a:item1'), true, null, tests.fx('cm_a1')),
  false, 'A: reenvio de resposta já substituída devolve false (não vale)');
select results_eq(
  format($$ select checked, note, client_mutation_id from public.attempt_item_answers
            where attempt_id = %L and task_item_id = %L $$, tests.attempt_of('a', 1), tests.fx('a:item1')),
  format($$ values (false, 'Alarme com defeito'::text, %L::uuid) $$, tests.fx('cm_a2')),
  'A: a resposta mais nova (não conforme) continua valendo');
select is(
  public.answer_item(tests.attempt_of('a', 1), tests.fx('a:item1'), false, 'Alarme com defeito',
                     tests.fx('cm_a2')),
  true, 'A: reenvio da resposta atual devolve true');
select is(public.submit_attempt(tests.attempt_of('a', 1)), 'submitted'::public.task_status,
  'A: com item não conforme a tarefa vai para o gerente (não é auto-aprovada)');

-- Depois do envio: o reenvio da resposta substituída devolve false, sem erro (D88)
select is(
  public.answer_item(tests.attempt_of('a', 1), tests.fx('a:item1'), true, null, tests.fx('cm_a1')),
  false, 'A: depois do envio, reenvio de resposta substituída (sem horário) devolve false, não attempt_closed');

-- Caso B: relógio do aparelho 1 h adiantado (horários limitados a agora) ------------
select public.answer_item(tests.attempt_of('b', 1), tests.fx('b:item1'), true, null, tests.fx('cm_b1'),
                          now() + interval '60 minutes');
select public.answer_item(tests.attempt_of('b', 1), tests.fx('b:item1'), false, 'Prateleira vazia',
                          tests.fx('cm_b2'), now() + interval '61 minutes');
select is(
  public.answer_item(tests.attempt_of('b', 1), tests.fx('b:item1'), true, null, tests.fx('cm_b1'),
                     now() + interval '60 minutes'),
  false, 'B: reenvio antigo com relógio adiantado é ignorado');
select results_eq(
  format($$ select checked, note from public.attempt_item_answers
            where attempt_id = %L and task_item_id = %L $$, tests.attempt_of('b', 1), tests.fx('b:item1')),
  $$ values (false, 'Prateleira vazia'::text) $$,
  'B: a resposta mais nova continua valendo');
select is(public.submit_attempt(tests.attempt_of('b', 1)), 'submitted'::public.task_status,
  'B: com item não conforme a tarefa vai para o gerente (não é auto-aprovada)');

-- Caso C: id substituído não pode ser reaproveitado em outro item ------------------
select public.answer_item(tests.attempt_of('c', 1), tests.fx('c:item1'), true, null, tests.fx('cm_c1'));
select public.answer_item(tests.attempt_of('c', 1), tests.fx('c:item1'), false, 'Etiqueta faltando',
                          tests.fx('cm_c2'));
select throws_ok(
  format($$ select public.answer_item(%L, %L, true, null, %L) $$,
         tests.attempt_of('c', 1), tests.fx('c:item2'), tests.fx('cm_c1')),
  'P0001', 'forbidden', 'C: id já usado (e substituído) em outro item é recusado');
select throws_ok(
  format($$ select public.answer_item(%L, %L, true, null, %L) $$,
         tests.attempt_of('b', 1), tests.fx('b:item1'), tests.fx('cm_c1')),
  'P0001', 'forbidden', 'C: id já usado em outra tentativa é recusado');

-- Histórico de ids: guarda o atual e os substituídos; resposta sem id não apaga nada
select public.answer_item(tests.attempt_of('c', 1), tests.fx('c:item1'), true);
select is(
  (select applied_mutation_ids from public.attempt_item_answers
   where attempt_id = tests.attempt_of('c', 1) and task_item_id = tests.fx('c:item1')),
  array[tests.fx('cm_c1'), tests.fx('cm_c2')],
  'C: applied_mutation_ids guarda os ids aplicados, na ordem');
select is(
  public.answer_item(tests.attempt_of('c', 1), tests.fx('c:item1'), false, 'Etiqueta faltando', tests.fx('cm_c2')),
  false, 'C: reenvio de id substituído por resposta sem id devolve false');

-- Limite: só os 200 mais recentes
select count(*) from (
  select public.answer_item(tests.attempt_of('c', 1), tests.fx('c:item2'), (i % 2 = 0), 'Nota ' || i,
                            gen_random_uuid())
  from generate_series(1, 205) as i
) x;
select is(
  (select cardinality(applied_mutation_ids) from public.attempt_item_answers
   where attempt_id = tests.attempt_of('c', 1) and task_item_id = tests.fx('c:item2')),
  200, 'o histórico de ids fica nos 200 mais recentes');

select tests.reset_role();
select * from finish();
rollback;
