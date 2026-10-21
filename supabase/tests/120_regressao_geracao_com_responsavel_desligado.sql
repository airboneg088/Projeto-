-- =============================================================================
-- 120 · Regressão R2-FUNC-10: o agendamento cujo responsável fixo saiu da loja
-- (transferido, desligado) não derruba a geração de tarefas
-- (private.instantiate_task, contrato do job diário): a tarefa do dia é gerada
-- para a equipe do setor (assignee nulo), com aviso no log.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(5);

select tests.create_base_fixture();
insert into public.task_templates (id, organization_id, store_id, title)
values (tests.fx('tpl_x'), tests.fx('org_a'), tests.fx('store_p'), 'Abertura');
insert into public.schedules (id, store_id, template_id, sector_id, assignee_id, window_start, window_end)
values (tests.fx('sch_x'), tests.fx('store_p'), tests.fx('tpl_x'), tests.fx('sector_p1'), tests.fx('staff_p1'), '08:00', '09:00'),
       (tests.fx('sch_y'), tests.fx('store_p'), tests.fx('tpl_x'), tests.fx('sector_p2'), tests.fx('staff_p2'), '08:00', '09:00');

-- Colaborador transferido: o vínculo já terminou quando o job roda
update public.memberships set ends_at = now() - interval '1 minute' where id = tests.fx('m_staff_p1');

set local client_min_messages = error; -- o aviso do log não entra na saída TAP
select lives_ok(
  format($$ select private.instantiate_task(%L, %L, %L, %L, now() + interval '1 hour', now() + interval '2 hours', %L, current_date + 1) $$,
         tests.fx('tpl_x'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('staff_p1'), tests.fx('sch_x')),
  'a geração do agendamento continua funcionando depois que o responsável sai da loja');
select lives_ok(
  format($$ select private.instantiate_task(%L, %L, %L, %L, now() + interval '1 hour', now() + interval '2 hours', %L, current_date + 1) $$,
         tests.fx('tpl_x'), tests.fx('store_p'), tests.fx('sector_p2'), tests.fx('staff_p2'), tests.fx('sch_y')),
  'o agendamento de quem continua na loja também é gerado (mesma transação)');
reset client_min_messages;

select is(
  (select assignee_id from public.tasks where schedule_id = tests.fx('sch_x')), null::uuid,
  'a tarefa do dia vai para a equipe do setor, não para quem saiu');
select is(
  (select assignee_id from public.tasks where schedule_id = tests.fx('sch_y')), tests.fx('staff_p2'),
  'quem continua na loja segue como responsável');
select is(
  (select count(*) from public.tasks where schedule_id in (tests.fx('sch_x'), tests.fx('sch_y'))), 2::bigint,
  'as duas tarefas do dia foram geradas');

select * from finish();
rollback;
