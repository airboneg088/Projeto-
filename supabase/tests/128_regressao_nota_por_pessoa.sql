-- =============================================================================
-- 128 · Regressão R2-REGRAS-05: nota ponderada por pessoa e filtro de pessoa do
-- kpi_summary usam a MESMA regra (private.task_person): quem executou a
-- última tentativa (a aprovada, se houver); sem tentativa, o responsável.
-- Falha em tarefa de equipe pesa para quem a executou; cada tarefa conta para
-- uma pessoa só; item crítico reprovado conta para quem executou a tentativa
-- reprovada, não para quem corrigiu depois.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(7);

select tests.create_base_fixture();

-- Quatro tarefas da equipe do setor P1 (assignee nulo), peso 2 cada
select tests.create_task('r2e_t1', 'store_p', 'sector_p1');
select tests.create_task('r2e_t2', 'store_p', 'sector_p1');
select tests.create_task('r2e_t3', 'store_p', 'sector_p1');
select tests.create_task('r2e_t4', 'store_p', 'sector_p1');
update public.task_items set is_critical = true where id = tests.fx('r2e_t4:item1');
select tests.create_user('staff_p3', '[TESTE] Colaborador P3', 'org_a');
select tests.create_membership('staff_p3', 'org_a', 'store_p', 'sector_p1', 'staff');

create function tests.r2e_execute(p_task text, p_number integer) returns void language plpgsql as $$
begin
  perform public.start_attempt(tests.fx(p_task), gen_random_uuid());
  perform public.answer_item(tests.attempt_of(p_task, p_number), tests.fx(p_task || ':item1'), true);
  perform public.answer_item(tests.attempt_of(p_task, p_number), tests.fx(p_task || ':item2'), true);
  perform public.submit_attempt(tests.attempt_of(p_task, p_number));
end;
$$;
grant execute on function tests.r2e_execute(text, integer) to public;

select tests.authenticate_as('staff_p1');
select tests.r2e_execute('r2e_t1', 1);                               -- t1: executada (aprovada depois)
select tests.r2e_execute('r2e_t2', 1);                               -- t2: executada (reprovada depois, não corrigida)
select public.start_attempt(tests.fx('r2e_t3'), gen_random_uuid()) is not null as iniciada; -- t3: iniciada e abandonada

-- t4: staff_p3 erra o crítico; staff_p1 corrige e é aprovado
select tests.authenticate_as('staff_p3');
select tests.r2e_execute('r2e_t4', 1);
select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('r2e_t4', 1), 'rejected', 'Crítico errado', array[tests.fx('r2e_t4:item1')]);
select tests.authenticate_as('staff_p1');
select tests.r2e_execute('r2e_t4', 2);
select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('r2e_t4', 2), 'approved');
select public.review_attempt(tests.attempt_of('r2e_t1', 1), 'approved');
select public.review_attempt(tests.attempt_of('r2e_t2', 1), 'rejected', 'Faltou conferir', array[tests.fx('r2e_t2:item1')]);

select tests.authenticate_as('owner_a');
-- staff_p1: t1 aprovada (2), t2 reprovada (2), t3 abandonada (2), t4 aprovada por ele na #2 (2)
--   -> volume 4, peso 8, aprovadas 4 -> 50.0
select results_eq(
  format($$ select group_id, volume, peso_total, nota from public.weighted_scores(current_date - 2, current_date + 2, 'person')
            where group_id = %L $$, tests.fx('staff_p1')),
  format($$ values (%L::uuid, 4, 8, 50.0) $$, tests.fx('staff_p1')),
  'nota de staff_p1 inclui as tarefas de equipe que ele executou e não concluiu');
select is(
  (select count(*)::int from public.weighted_scores(current_date - 2, current_date + 2, 'person') where group_id is null),
  0, 'nada executado por alguém vai para "Sem responsável"');
select is(
  (select volume from public.weighted_scores(current_date - 2, current_date + 2, 'person') where group_id = tests.fx('staff_p1')),
  (select previstas from public.kpi_summary(current_date - 2, current_date + 2, null, null, array[tests.fx('staff_p1')])),
  'volume da nota por pessoa = previstas do kpi_summary filtrado pela mesma pessoa');
select is(
  (select criticos_reprovados from public.weighted_scores(current_date - 2, current_date + 2, 'person') where group_id = tests.fx('staff_p1')),
  0, 'o crítico reprovado na tentativa de staff_p3 não aparece na linha de staff_p1');
select results_eq(
  format($$ select volume, peso_total, nota, criticos_reprovados from public.weighted_scores(current_date - 2, current_date + 2, 'person')
            where group_id = %L $$, tests.fx('staff_p3')),
  $$ values (0, 0, null::numeric, 1) $$,
  'staff_p3 aparece com o crítico que reprovou (volume 0: a tarefa foi concluída por outra pessoa)');
select is(
  (select sum(previstas)::int from (
     select (public.kpi_summary(current_date - 2, current_date + 2, null, null, array[p])).previstas
     from unnest(array[tests.fx('staff_p1'), tests.fx('staff_p3')]) as p) x),
  (select previstas from public.kpi_summary(current_date - 2, current_date + 2, array[tests.fx('store_p')])),
  'as previstas por pessoa somam as da loja (cada tarefa conta para uma pessoa só)');
select is(
  (select aprovadas from public.kpi_summary(current_date - 2, current_date + 2, null, null, array[tests.fx('staff_p3')])),
  0, 'a aprovação de t4 não conta também para staff_p3');

select * from finish();
rollback;
