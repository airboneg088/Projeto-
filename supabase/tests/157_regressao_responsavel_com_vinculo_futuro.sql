-- =============================================================================
-- 157 · Regressão R4-REGRAS-06: responsável de tarefa precisa de vínculo de
-- colaborador que começa ANTES do prazo (D100). A D86 aceitava quem só começa
-- no futuro: a tarefa de hoje ficava com uma pessoa que não consegue iniciá-la,
-- e a equipe do setor também não (responsável preenchido) — a tarefa vencia.
-- Agendamento (sem prazo) continua aceitando quem começa no futuro; a geração
-- da tarefa do dia manda para a equipe do setor (D42) quando o responsável fixo
-- só começa depois do prazo.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(6);

select tests.create_base_fixture();
select tests.create_user('staff_novo', '[TESTE] Colaborador que entra semana que vem', 'org_a');
insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
values (tests.fx('staff_novo'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'staff',
        now() + interval '7 days');

-- Gerente cria a tarefa de hoje para quem só começa daqui a 7 dias: recusada
select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, title, assignee_id, due_at)
            values (%L, %L, %L, 'Reposição de hoje', %L, now() + interval '2 hours') $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('staff_novo')),
  '23514', 'invalid_assignee', 'tarefa de hoje não aceita como responsável quem ainda não começou');
-- Tarefa com prazo depois do início do vínculo: aceita (planejamento da semana que vem)
select lives_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, title, assignee_id, due_at)
            values (%L, %L, %L, 'Reposição da semana que vem', %L, now() + interval '8 days') $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('staff_novo')),
  'tarefa com prazo depois do início do vínculo aceita o novo colaborador');
-- Reatribuir a tarefa de hoje para ele também é recusado
select tests.reset_role();
select tests.create_task('hoje', 'store_p', 'sector_p1', 'staff_p1');
update public.tasks set due_at = now() + interval '2 hours' where id = tests.fx('hoje');
select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ update public.tasks set assignee_id = %L where id = %L $$, tests.fx('staff_novo'), tests.fx('hoje')),
  '23514', 'invalid_assignee', 'reatribuir a tarefa de hoje para quem ainda não começou é recusado');

-- Geração pelo agendamento com responsável fixo que ainda não começou
select tests.reset_role();
insert into public.task_templates (id, organization_id, store_id, title, weight)
values (tests.fx('tpl'), tests.fx('org_a'), tests.fx('store_p'), 'Rotina', 2);
select lives_ok(
  format($$ insert into public.schedules (id, store_id, template_id, sector_id, assignee_id, window_start, window_end)
            values (%L, %L, %L, %L, %L, '08:00', '09:00') $$,
         tests.fx('sch'), tests.fx('store_p'), tests.fx('tpl'), tests.fx('sector_p1'), tests.fx('staff_novo')),
  'agendamento com responsável futuro é aceito (gera para ele quando ele entrar)');
set local client_min_messages = error; -- o aviso de que a tarefa foi para a equipe é esperado
select private.instantiate_task(tests.fx('tpl'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('staff_novo'),
                                now() - interval '1 hour', now() + interval '2 hours',
                                tests.fx('sch'), current_date, null, null);
select is(
  (select assignee_id from public.tasks where schedule_id = tests.fx('sch')),
  null::uuid,
  'a tarefa de hoje gerada para quem ainda não começou vai para a equipe do setor (D42)');

-- A equipe do setor consegue iniciar a tarefa de hoje
create temporary table gerada as select id from public.tasks where schedule_id = tests.fx('sch');
grant select on gerada to public;
select tests.authenticate_as('staff_p1');
select lives_ok(
  format($$ select public.start_attempt(%L, gen_random_uuid()) $$, (select id from gerada)),
  'alguém da equipe do setor consegue iniciar a tarefa de hoje');

select tests.reset_role();
select * from finish();
rollback;
