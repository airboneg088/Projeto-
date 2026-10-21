-- =============================================================================
-- 126 · Regressão R2-REGRAS-03: o início da janela (window_start_at) só muda com
-- a tarefa pendente e sem tentativas, e nunca para o passado (deadline_locked).
-- Assim "Tempo atribuição -> envio" não é encurtado depois do fato e nenhuma
-- tentativa fica registrada como iniciada antes da janela (D29).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(8);

select tests.create_base_fixture();

-- t1, t2: janela aberta há 2 h; t3: janela abre daqui a 2 h (ainda pendente)
insert into public.tasks (id, organization_id, store_id, sector_id, title, weight, assignee_id,
                          window_start_at, due_at, created_at)
values (tests.fx('r2w_t1'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Reposição', 2,
        tests.fx('staff_p1'), now() - interval '2 hours', now() + interval '2 hours', now() - interval '3 hours'),
       (tests.fx('r2w_t2'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Estoque', 2,
        tests.fx('staff_p1'), now() - interval '2 hours', now() + interval '2 hours', now() - interval '3 hours'),
       (tests.fx('r2w_t3'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Limpeza', 2,
        tests.fx('staff_p1'), now() + interval '2 hours', now() + interval '4 hours', now() - interval '3 hours');

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('r2w_t1'), gen_random_uuid());
select public.start_attempt(tests.fx('r2w_t2'), gen_random_uuid());

select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ update public.tasks set window_start_at = now() - interval '1 minute' where id = %L $$, tests.fx('r2w_t1')),
  'P0001', 'deadline_locked',
  'início da janela não vai para o passado (e não muda com tentativa aberta)'
);
select throws_ok(
  format($$ update public.tasks set window_start_at = now() + interval '30 minutes' where id = %L $$, tests.fx('r2w_t2')),
  'P0001', 'deadline_locked',
  'início da janela não passa para depois do início da tentativa já aberta'
);
select throws_ok(
  format($$ update public.tasks set window_start_at = now() - interval '1 hour' where id = %L $$, tests.fx('r2w_t3')),
  'P0001', 'deadline_locked',
  'tarefa pendente: início da janela também não vai para o passado'
);
select throws_ok(
  format($$ update public.tasks set window_start_at = null where id = %L $$, tests.fx('r2w_t3')),
  'P0001', 'deadline_locked',
  'tirar o início da janela (= aberta desde a criação, no passado) também é recusado'
);
select is(tests.exec_result(format(
  $$ update public.tasks set window_start_at = now() + interval '1 hour' where id = %L $$, tests.fx('r2w_t3'))),
  'ok', 'controle: tarefa pendente, sem tentativa, pode ter o início da janela movido no futuro');

select tests.authenticate_as('staff_p1');
select public.submit_attempt(tests.attempt_of('r2w_t1', 1), null, gen_random_uuid());

select tests.authenticate_as('owner_a');
-- atribuição→envio esperado: envio (now) − greatest(created now-3h, janela now-2h) = 120 min
select is(
  (select media_min_atribuicao_envio
     from public.kpi_summary(current_date - 2, current_date + 2, null, null, array[tests.fx('staff_p1')])),
  120.0, 'tempo atribuição→envio reflete a janela original (120 min), não a editada');
select is(
  (select count(*)::int
     from public.task_attempts a join public.tasks t on t.id = a.task_id
    where t.id in (tests.fx('r2w_t1'), tests.fx('r2w_t2')) and a.started_at < t.window_start_at),
  0, 'nenhuma tentativa fica registrada como iniciada antes da janela');
select is(
  (select window_start_at from public.tasks where id = tests.fx('r2w_t1')), now() - interval '2 hours',
  'o início da janela da tarefa executada não mudou');

select * from finish();
rollback;
