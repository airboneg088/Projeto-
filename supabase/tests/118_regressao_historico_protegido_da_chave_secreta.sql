-- =============================================================================
-- 118 · Regressão R2-FUNC-07: a chave secreta (ou um bug no servidor) não
-- reescreve o histórico sem rastro.
--   a) tasks não são apagadas (nem pela service_role, nem pelo postgres);
--   b) itens de tarefa já executada/fechada não mudam (task_closed);
--   c) purged_at só depois do prazo de retenção e sempre com o horário do servidor;
--   d) marcação de reprovação e resposta só com item da MESMA tarefa (FK composta);
--   e) created_by não é informado pela chave secreta (sem usuário = sistema).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(12);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('b');
select tests.create_task('t_atrasada', 'store_p', 'sector_p1', 'staff_p1');
select tests.walk(tests.fx('t_atrasada'), 'overdue');
select tests.create_task('t_aprovada', 'store_p', 'sector_p1', 'staff_p1');
select tests.walk(tests.fx('t_aprovada'), 'in_progress', 'submitted', 'approved');
select tests.create_task('t_aberta', 'store_p', 'sector_p1', 'staff_p1');
select tests.walk(tests.fx('t_aberta'), 'in_progress');
insert into public.task_attempts (id, task_id, store_id, attempt_number, performed_by)
values (tests.fx('att_aberta'), tests.fx('t_aberta'), tests.fx('store_p'), 1, tests.fx('staff_p1'));
select tests.create_task('t_pendente', 'store_p', 'sector_p1', 'staff_p1');

select tests.authenticate_service_role();
-- a) apagar a falha
select isnt(tests.exec_result($$ delete from public.task_items where task_id = tests.fx('t_atrasada') $$), 'ok',
  'service_role NÃO apaga itens de tarefa atrasada');
select isnt(tests.exec_result($$ delete from public.tasks where id = tests.fx('t_atrasada') $$), 'ok',
  'service_role NÃO apaga tarefa atrasada (tarefa se cancela com motivo, não some)');
-- b) reescrever o snapshot de tarefa fechada
select alike(
  tests.exec_result($$ update public.task_items set text = 'reescrito', is_critical = true, weight = 5
                       where task_id = tests.fx('t_aprovada') $$),
  'P0001:task_closed%', 'itens de tarefa aprovada não mudam (task_closed vale para o snapshot dos itens)');
select alike(
  tests.exec_result($$ insert into public.task_items (task_id, position, text) values (tests.fx('t_aprovada'), 9, 'novo') $$),
  'P0001:task_closed%', 'tarefa aprovada não ganha item novo');
-- c) retenção
select alike(tests.exec_result($$ update public.evidences set purged_at = now() where id = tests.fx('ev_p') $$),
  'P0001:retention_not_reached%', 'purged_at não é aceito em foto recebida agora (retenção da organização = 180 dias)');
select alike(tests.exec_result($$ update public.evidences set purged_at = '1900-01-01' where id = tests.fx('ev_b') $$),
  'P0001:retention_not_reached%', 'purged_at com data anterior ao recebimento também não');
-- d) itens de outra tarefa/organização
select alike(
  tests.exec_result($$ insert into public.review_item_flags (review_id, task_id, task_item_id)
                       values (tests.fx('rev_p'), tests.fx('task_p'), tests.fx('task_b:item1')) $$),
  '23503:%', 'review_item_flags recusa item de outra tarefa (outra organização)');
select alike(
  tests.exec_result($$ insert into public.review_item_flags (review_id, task_id, task_item_id)
                       values (tests.fx('rev_p'), tests.fx('task_b'), tests.fx('task_b:item1')) $$),
  '23503:%', 'review_item_flags recusa revisão e tarefa que não combinam');
select alike(
  tests.exec_result($$ insert into public.attempt_item_answers (attempt_id, task_id, task_item_id, checked)
                       values (tests.fx('att_aberta'), tests.fx('t_aberta'), tests.fx('task_b:item2'), true) $$),
  '23503:%', 'attempt_item_answers recusa item de outra tarefa (outra organização)');
-- e) autor não forjável
insert into public.task_templates (id, organization_id, store_id, title, created_by)
values (tests.fx('tpl_forjada'), tests.fx('org_a'), tests.fx('store_p'), 'Rotina', tests.fx('owner_a'));

select tests.reset_role();
select is((select created_by from public.task_templates where id = tests.fx('tpl_forjada')), null::uuid,
  'a chave secreta não atribui a autoria de uma rotina a outra pessoa (sistema = nulo)');
select throws_ok($$ delete from public.tasks where id = tests.fx('t_pendente') $$, 'P0001', 'immutable',
  'nem o postgres apaga tarefa');
select ok(exists (select 1 from public.tasks where id = tests.fx('t_atrasada'))
          and (select count(*) from public.task_items where task_id = tests.fx('t_atrasada')) = 2,
  'a tarefa atrasada e os itens dela continuam existindo');

select * from finish();
rollback;
