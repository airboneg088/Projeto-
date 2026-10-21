-- =============================================================================
-- 130 · Regressão R2-REGRAS-07: o snapshot da rotina não é forjável. Tarefa
-- nova que cita uma rotina usa a versão ATUAL dela e as mesmas exigências e
-- peso (invalid_template_version, invalid_snapshot); item que cita um item de
-- rotina usa o mesmo crítico, foto e peso.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(7);
select tests.create_base_fixture();

insert into public.task_templates (id, organization_id, store_id, title, requires_photo, requires_approval, weight)
values (tests.fx('r2s_tpl'), tests.fx('org_a'), tests.fx('store_p'), 'Caixa', true, true, 1);
insert into public.template_items (id, template_id, position, text, is_critical, requires_photo)
values (tests.fx('r2s_ti1'), tests.fx('r2s_tpl'), 1, 'Sangria no cofre', true, true);

select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, template_id, template_version, title,
                                     requires_photo, requires_approval, weight, assignee_id, due_at)
            values (%L, %L, %L, %L, 1, 'Caixa', false, false, 5, %L, now() + interval '2 hours') $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('r2s_tpl'), tests.fx('staff_p1')),
  '23514', 'invalid_snapshot',
  'tarefa que cita a rotina Caixa v1 não pode ter peso, aprovação e foto diferentes da v1');
select throws_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, template_id, template_version, title,
                                     requires_photo, requires_approval, weight, due_at)
            values (%L, %L, %L, %L, null, 'Caixa', true, true, 1, now() + interval '2 hours') $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('r2s_tpl')),
  '23514', 'invalid_template_version',
  'tarefa que cita a rotina precisa citar a versão atual');

-- Caminho certo: a cópia fiel da v1
select is(tests.exec_result(format(
  $$ insert into public.tasks (organization_id, store_id, sector_id, template_id, template_version, title,
                               requires_photo, requires_approval, weight, assignee_id, due_at)
     values (%L, %L, %L, %L, 1, 'Caixa', true, true, 1, %L, now() + interval '2 hours') $$,
  tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('r2s_tpl'), tests.fx('staff_p1'))), 'ok',
  'tarefa com o snapshot da versão atual é aceita');

create temporary table nova as select id from public.tasks where template_id = tests.fx('r2s_tpl');
grant select on nova to public;
select throws_ok(
  format($$ insert into public.task_items (task_id, template_item_id, position, text, is_critical, requires_photo)
            values (%L, %L, 1, 'Sangria no cofre', false, false) $$, (select id from nova), tests.fx('r2s_ti1')),
  '23514', 'invalid_snapshot',
  'item que cita o item crítico da rotina não pode nascer como não crítico e sem foto');
select is(tests.exec_result(format(
  $$ insert into public.task_items (task_id, template_item_id, position, text, is_critical, requires_photo)
     values (%L, %L, 1, 'Sangria no cofre', true, true) $$, (select id from nova), tests.fx('r2s_ti1'))), 'ok',
  'item com o mesmo crítico, foto e peso do item da rotina é aceito');
select throws_ok(
  format($$ update public.task_items set is_critical = false where task_id = %L $$, (select id from nova)),
  '23514', 'invalid_snapshot',
  'o gerente não desmarca o crítico de um item que veio da rotina');

-- A geração pelo sistema copia a versão atual (mesmo depois de editar a rotina)
select tests.reset_role();
update public.task_templates set weight = 4 where id = tests.fx('r2s_tpl');
create temporary table gerada as
select private.instantiate_task(tests.fx('r2s_tpl'), tests.fx('store_p'), tests.fx('sector_p1'), null,
                                now() + interval '1 hour', now() + interval '2 hours') as id;
select is(
  (select row(t.template_version, t.weight)::text from public.tasks t join gerada g on g.id = t.id),
  '(2,4)', 'instantiate_task copia a versão atual (v2, peso 4)');

select * from finish();
rollback;
