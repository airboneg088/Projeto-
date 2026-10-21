-- =============================================================================
-- 106 · Regressão R1-REGRAS-03: janela = intervalo permitido de execução.
--   - start_attempt recusa iniciar antes de window_start_at (window_not_open);
--   - o indicador media_min_atribuicao_envio nunca fica negativo (envio antes
--     da janela gravado pelo sistema conta como zero).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(6);

select tests.create_base_fixture();

-- Abertura amanhã cedo: janela abre daqui a 2 h, prazo em 3 h; criada há 1 h
insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id,
                          window_start_at, due_at, created_at)
values (tests.fx('early'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Abertura',
        tests.fx('staff_p1'), now() + interval '2 hours', now() + interval '3 hours', now() - interval '1 hour');
insert into public.task_items (id, task_id, position, text) values (tests.fx('early:i1'), tests.fx('early'), 1, 'Item');
-- Avulsa sem janela (aberta desde a criação)
insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at)
values (tests.fx('sem_janela'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Avulsa',
        tests.fx('staff_p1'), null, now() + interval '3 hours');

select tests.authenticate_as('staff_p1');
select throws_ok($$ select public.start_attempt(tests.fx('early'), gen_random_uuid()) $$,
  'P0001', 'window_not_open', 'executar antes de window_start_at é recusado');
select is((select status::text from public.tasks where id = tests.fx('early')), 'pending',
  'a tarefa continua pendente');
select ok(public.start_attempt(tests.fx('sem_janela'), gen_random_uuid()) is not null,
  'tarefa sem início de janela pode ser iniciada a qualquer momento');

-- A janela abre (o gerente antecipa o início para agora; nunca para o passado): agora pode
select tests.authenticate_as('manager_p');
update public.tasks set window_start_at = now() where id = tests.fx('early');
select tests.authenticate_as('staff_p1');
select ok(public.start_attempt(tests.fx('early'), gen_random_uuid()) is not null,
  'com a janela aberta, a tarefa é iniciada');

-- Envio antes da janela gravado pelo sistema (dado antigo): duração conta como zero
select tests.reset_role();
insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id,
                          window_start_at, due_at, created_at)
values (tests.fx('early2'), tests.fx('org_a'), tests.fx('store_c'), tests.fx('sector_c1'), 'Abertura C',
        tests.fx('staff_c1'), now() + interval '2 hours', now() + interval '3 hours', now() - interval '1 hour');
select tests.walk(tests.fx('early2'), 'in_progress');
insert into public.task_attempts (task_id, store_id, attempt_number, performed_by, started_at, submitted_at)
values (tests.fx('early2'), tests.fx('store_c'), 1, tests.fx('staff_c1'), now() - interval '5 minutes', now());
select tests.walk(tests.fx('early2'), 'submitted');

select tests.authenticate_as('owner_a');
select is(
  (select media_min_atribuicao_envio from public.kpi_summary(
     (now() at time zone 'America/Sao_Paulo')::date - 1, (now() at time zone 'America/Sao_Paulo')::date + 1,
     array[tests.fx('store_c')])),
  0.0::numeric,
  'media_min_atribuicao_envio não fica negativa (envio antes da janela conta 0)'
);
select ok(
  coalesce((select media_min_atribuicao_envio from public.kpi_summary(
     (now() at time zone 'America/Sao_Paulo')::date - 1, (now() at time zone 'America/Sao_Paulo')::date + 1)), 0) >= 0,
  'media_min_atribuicao_envio nunca é negativa'
);

select * from finish();
rollback;
