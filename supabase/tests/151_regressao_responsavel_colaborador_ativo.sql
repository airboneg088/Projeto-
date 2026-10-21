-- =============================================================================
-- 151 · Regressão R3-REGRAS-05: responsável de tarefa e de agendamento precisa
-- ser colaborador ativo da loja (D86): vínculo de staff não encerrado na loja e
-- perfil ativo. Gerente, proprietária ou perfil inativo como responsável deixavam
-- a tarefa sem ninguém que pudesse iniciá-la (vencia e contava como atrasada).
-- A geração por agendamento manda para a equipe do setor quando o responsável
-- fixo deixou de ser colaborador ativo.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(8);

select tests.create_base_fixture();
insert into public.task_templates (id, organization_id, store_id, title)
values (tests.fx('rq_tpl'), tests.fx('org_a'), tests.fx('store_p'), 'Abertura');

select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, title, assignee_id, due_at)
            values (%L, %L, %L, 'Conferir validade', %L, now() + interval '2 hours') $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('manager_p')),
  '23514', 'invalid_assignee', 'tarefa não é atribuída ao gerente (não é colaborador)');
select throws_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, title, assignee_id, due_at)
            values (%L, %L, %L, 'Conferir validade', %L, now() + interval '2 hours') $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('owner_a')),
  '23514', 'invalid_assignee', 'tarefa não é atribuída à proprietária');
select throws_ok(
  format($$ insert into public.schedules (store_id, template_id, sector_id, assignee_id, window_start, window_end)
            values (%L, %L, %L, %L, '07:30', '08:15') $$,
         tests.fx('store_p'), tests.fx('rq_tpl'), tests.fx('sector_p1'), tests.fx('manager_p')),
  '23514', 'invalid_assignee', 'agendamento não tem gerente como responsável fixo');
select lives_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, title, assignee_id, due_at)
            values (%L, %L, %L, 'Repor gôndola', %L, now() + interval '2 hours') $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('staff_p1')),
  'controle: colaborador ativo da loja continua aceito');

-- Colaborador com perfil inativo (vínculo ainda aberto)
select tests.reset_role();
update public.profiles set status = 'inactive' where id = tests.fx('staff_p2');
select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, title, assignee_id, due_at)
            values (%L, %L, %L, 'Repor gôndola', %L, now() + interval '2 hours') $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p2'), tests.fx('staff_p2')),
  '23514', 'invalid_assignee', 'tarefa não é atribuída a colaborador com perfil inativo');
select throws_ok(
  format($$ update public.tasks set assignee_id = %L where title = 'Repor gôndola' $$, tests.fx('manager_p')),
  '23514', 'invalid_assignee', 'reatribuir ao gerente também é recusado');

-- Geração: responsável fixo que virou inativo -> equipe do setor
select tests.reset_role();
alter table public.schedules disable trigger schedules_validate_assignee;
insert into public.schedules (id, store_id, template_id, sector_id, assignee_id, window_start, window_end)
values (tests.fx('rq_sch'), tests.fx('store_p'), tests.fx('rq_tpl'), tests.fx('sector_p2'), tests.fx('staff_p2'), '07:30', '08:15');
alter table public.schedules enable trigger schedules_validate_assignee;
set local client_min_messages = error; -- o aviso "tarefa gerada para a equipe do setor" é esperado
select private.instantiate_task(tests.fx('rq_tpl'), tests.fx('store_p'), tests.fx('sector_p2'), tests.fx('staff_p2'),
                                now() + interval '1 hour', now() + interval '2 hours', tests.fx('rq_sch'), current_date + 1)
  as tarefa_inativo \gset
select private.instantiate_task(tests.fx('rq_tpl'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('manager_p'),
                                now() + interval '1 hour', now() + interval '2 hours')
  as tarefa_gerente \gset
select is((select assignee_id from public.tasks where id = :'tarefa_inativo'), null,
  'geração com responsável inativo manda a tarefa para a equipe do setor');
select is((select assignee_id from public.tasks where id = :'tarefa_gerente'), null,
  'geração com o gerente como responsável manda a tarefa para a equipe do setor');

select * from finish();
rollback;
