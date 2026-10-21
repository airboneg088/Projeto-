-- =============================================================================
-- 105 · Regressão R1-REGRAS-02: o gerente avaliado não apaga uma falha dos
-- indicadores cancelando a tarefa depois do fato.
--   - gerente cancela só tarefa pendente ou em andamento cujo prazo não venceu;
--   - vencida, enviada, reprovada (ou atrasada): só a proprietária (owner_only).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(10);

select tests.create_base_fixture();

-- Tarefas de 2026-05-10: uma venceu sem envio (overdue), outra reprovada com item crítico
insert into public.task_templates (id, organization_id, store_id, title, weight)
values (tests.fx('tc'), tests.fx('org_a'), tests.fx('store_p'), 'Caixa', 5);
insert into public.template_items (id, template_id, position, text, is_critical)
values (tests.fx('tc:1'), tests.fx('tc'), 1, 'Sangria', true);
insert into public.tasks (id, organization_id, store_id, sector_id, template_id, template_version, title, weight,
                          assignee_id, window_start_at, due_at, created_at)
values (tests.fx('od'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('tc'), 1, 'Caixa', 5,
        tests.fx('staff_p1'), '2026-05-10 11:00+00', '2026-05-10 12:00+00', '2026-05-10 03:00+00'),
       (tests.fx('rj'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('tc'), 1, 'Caixa', 5,
        tests.fx('staff_p1'), '2026-05-10 13:00+00', '2026-05-10 14:00+00', '2026-05-10 03:00+00');
insert into public.task_items (id, task_id, template_item_id, position, text, is_critical)
values (tests.fx('rj:1'), tests.fx('rj'), tests.fx('tc:1'), 1, 'Sangria', true);
select tests.walk(tests.fx('od'), 'overdue');
select tests.walk(tests.fx('rj'), 'in_progress');
insert into public.task_attempts (id, task_id, store_id, attempt_number, performed_by, started_at, submitted_at)
values (tests.fx('rj:a1'), tests.fx('rj'), tests.fx('store_p'), 1, tests.fx('staff_p1'),
        '2026-05-10 13:10+00', '2026-05-10 13:30+00');
select tests.walk(tests.fx('rj'), 'submitted');
insert into public.reviews (id, attempt_id, task_id, reviewer_id, decision, reason, reviewed_at)
values (tests.fx('rj:r1'), tests.fx('rj:a1'), tests.fx('rj'), tests.fx('manager_p'), 'rejected', 'Sem sangria',
        '2026-05-10 13:45+00');
insert into public.review_item_flags (review_id, task_id, task_item_id) values (tests.fx('rj:r1'), tests.fx('rj'), tests.fx('rj:1'));
select tests.walk(tests.fx('rj'), 'rejected');

-- Tarefa enviada dentro do prazo (ainda não revisada) e uma pendente futura
select tests.create_task('enviada', 'store_p', 'sector_p1', 'staff_p1');
select tests.walk(tests.fx('enviada'), 'in_progress', 'submitted');
select tests.create_task('futura', 'store_p', 'sector_p1', 'staff_p1');

-- Meses depois, o gerente avaliado tenta cancelar
select tests.authenticate_as('manager_p');
select throws_ok($$ select public.cancel_task(tests.fx('od'), 'Ajuste') $$, 'P0001', 'owner_only',
  'gerente NÃO cancela tarefa que venceu sem envio');
select throws_ok($$ select public.cancel_task(tests.fx('rj'), 'Ajuste') $$, 'P0001', 'owner_only',
  'gerente NÃO cancela tarefa reprovada');
select throws_ok($$ select public.cancel_task(tests.fx('enviada'), 'Ajuste') $$, 'P0001', 'owner_only',
  'gerente NÃO cancela tarefa aguardando aprovação (revisa)');
select lives_ok($$ select public.cancel_task(tests.fx('futura'), 'Loja fechada amanhã') $$,
  'gerente cancela tarefa pendente antes do prazo');

select tests.authenticate_as('owner_a');
select results_eq(
  $$ select previstas, atrasadas, devolvidas
     from public.kpi_summary('2026-05-10', '2026-05-10', array[tests.fx('store_p')]) $$,
  $$ values (2, 2, 1) $$,
  'kpi_summary de 10/05 continua mostrando a falha'
);
select ok(
  exists (select 1 from public.weighted_scores('2026-05-10', '2026-05-10', 'store', array[tests.fx('store_p')])
          where volume = 2 and nota = 0.0 and criticos_reprovados = 1),
  'nota ponderada de 10/05 continua com as duas tarefas e o item crítico'
);
select ok(
  exists (select 1 from public.top_failed_items('2026-05-10', '2026-05-10', array[tests.fx('store_p')])
          where template_item_id = tests.fx('tc:1')),
  'item crítico reprovado continua no top'
);

-- A proprietária pode cancelar (e fica auditado)
select lives_ok($$ select public.cancel_task(tests.fx('od'), 'Loja fechada por obra') $$,
  'proprietária cancela tarefa vencida');
select tests.reset_role();
select results_eq(
  $$ select actor_id, action from public.audit_log where record_id = tests.fx('od')::text $$,
  format($$ values (%L::uuid, 'task_cancelled'::text) $$, tests.fx('owner_a')),
  'cancelamento tardio da proprietária fica no audit_log'
);
select is(
  (select status::text from public.tasks where id = tests.fx('rj')),
  'rejected',
  'tarefa reprovada continua reprovada'
);

select * from finish();
rollback;
