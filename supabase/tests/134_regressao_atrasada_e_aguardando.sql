-- =============================================================================
-- 134 · Regressão R2-REGRAS-S1 (R1-REGRAS-07): "Atrasada" = venceu sem envio
-- (PRODUCT.md §7). Tarefa enviada até o prazo e ainda sem revisão continua
-- "Aguardando aprovação" depois do prazo (a demora da revisão do gerente não é
-- atraso de quem executou); enviada depois do prazo, nunca enviada ou reprovada
-- e não reenviada até o prazo vencer contam como atrasadas. submitted nunca
-- conta como aprovada.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(4);

select tests.create_base_fixture();

-- Todas no dia local 10/05/2026, janela 11:00-12:00Z (prazo já vencido)
create function tests.s1_task(p_name text) returns void language sql as $$
  insert into public.tasks (id, organization_id, store_id, sector_id, title, weight, assignee_id,
                            window_start_at, due_at, created_at)
  values (tests.fx(p_name), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'S1 ' || p_name, 1,
          tests.fx('staff_p1'), '2026-05-10 11:00+00', '2026-05-10 12:00+00', '2026-05-10 03:00+00')
$$;
create function tests.s1_attempt(p_name text, p_number integer, p_submitted timestamptz) returns void language sql as $$
  insert into public.task_attempts (id, task_id, store_id, attempt_number, performed_by, started_at, submitted_at)
  values (tests.fx(p_name || ':a' || p_number), tests.fx(p_name), tests.fx('store_p'), p_number, tests.fx('staff_p1'),
          p_submitted - interval '10 minutes', p_submitted)
$$;

-- a: enviada 11:30 (dentro do prazo), sem revisão -> Aguardando aprovação
select tests.s1_task('s1_a');
select tests.walk(tests.fx('s1_a'), 'in_progress');
select tests.s1_attempt('s1_a', 1, '2026-05-10 11:30+00');
select tests.walk(tests.fx('s1_a'), 'submitted');
-- b: enviada 12:30 (depois do prazo), sem revisão -> Atrasada
select tests.s1_task('s1_b');
select tests.walk(tests.fx('s1_b'), 'in_progress');
select tests.s1_attempt('s1_b', 1, '2026-05-10 12:30+00');
select tests.walk(tests.fx('s1_b'), 'submitted');
-- c: nunca enviada -> Atrasada
select tests.s1_task('s1_c');
select tests.walk(tests.fx('s1_c'), 'overdue');
-- d: enviada a tempo e reprovada, sem reenvio até o prazo -> Atrasada
select tests.s1_task('s1_d');
select tests.walk(tests.fx('s1_d'), 'in_progress');
select tests.s1_attempt('s1_d', 1, '2026-05-10 11:20+00');
select tests.walk(tests.fx('s1_d'), 'submitted');
insert into public.reviews (attempt_id, task_id, reviewer_id, decision, reason, reviewed_at)
values (tests.fx('s1_d:a1'), tests.fx('s1_d'), tests.fx('manager_p'), 'rejected', 'Foto escura', '2026-05-10 11:40+00');
select tests.walk(tests.fx('s1_d'), 'rejected');
-- e: reprovada a tempo e reenviada até o prazo, sem revisão -> Aguardando aprovação
select tests.s1_task('s1_e');
select tests.walk(tests.fx('s1_e'), 'in_progress');
select tests.s1_attempt('s1_e', 1, '2026-05-10 11:10+00');
select tests.walk(tests.fx('s1_e'), 'submitted');
insert into public.reviews (attempt_id, task_id, reviewer_id, decision, reason, reviewed_at)
values (tests.fx('s1_e:a1'), tests.fx('s1_e'), tests.fx('manager_p'), 'rejected', 'Faltou um item', '2026-05-10 11:25+00');
select tests.walk(tests.fx('s1_e'), 'rejected', 'in_progress');
select tests.s1_attempt('s1_e', 2, '2026-05-10 11:55+00');
select tests.walk(tests.fx('s1_e'), 'submitted');
-- f: aprovada
select tests.s1_task('s1_f');
select tests.walk(tests.fx('s1_f'), 'in_progress');
select tests.s1_attempt('s1_f', 1, '2026-05-10 11:15+00');
select tests.walk(tests.fx('s1_f'), 'submitted');
insert into public.reviews (attempt_id, task_id, reviewer_id, decision, reviewed_at)
values (tests.fx('s1_f:a1'), tests.fx('s1_f'), tests.fx('manager_p'), 'approved', '2026-05-10 11:45+00');
select tests.walk(tests.fx('s1_f'), 'approved');

select tests.authenticate_as('owner_a');
select results_eq(
  $$ select previstas, aprovadas, atrasadas, pendentes, aguardando_aprovacao
     from public.kpi_summary('2026-05-10', '2026-05-10', array[tests.fx('store_p')]) $$,
  $$ values (6, 1, 3, 2, 2) $$,
  'atrasadas = venceram sem envio (b, c, d); enviadas até o prazo seguem aguardando aprovação (a, e)'
);
select is(
  (select status::text from public.tasks where id = tests.fx('s1_a')),
  'submitted', 'o status exibido da enviada a tempo é "Aguardando aprovação"');
select is(
  (select aprovadas from public.kpi_summary('2026-05-10', '2026-05-10', array[tests.fx('store_p')])),
  1, 'submitted nunca conta como aprovada');

-- Enviada a tempo e só aprovada depois do prazo: aprovada (não atrasada)
select tests.reset_role();
insert into public.reviews (attempt_id, task_id, reviewer_id, decision, reviewed_at)
values (tests.fx('s1_a:a1'), tests.fx('s1_a'), tests.fx('manager_p'), 'approved', now());
select tests.walk(tests.fx('s1_a'), 'approved');
select tests.authenticate_as('owner_a');
select results_eq(
  $$ select aprovadas, atrasadas, aguardando_aprovacao
     from public.kpi_summary('2026-05-10', '2026-05-10', array[tests.fx('store_p')]) $$,
  $$ values (2, 3, 1) $$,
  'a revisão tardia de um envio feito a tempo não gera atraso'
);

select * from finish();
rollback;
