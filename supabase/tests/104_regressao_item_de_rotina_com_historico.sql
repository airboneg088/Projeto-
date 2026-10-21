-- =============================================================================
-- 104 · Regressão R1-FI-11: apagar um item da rotina não apaga a "falha
-- recorrente" dele do indicador top_failed_items.
--   - task_items.template_item_id é ON DELETE RESTRICT: item já usado em
--     tarefa não é apagado (23503); desativa-se (template_items.is_active);
--   - item nunca usado continua podendo ser apagado.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(7);

select tests.create_base_fixture();
select tests.create_store_activity('p');
-- o fixture cria um plano de ação para o item crítico (FK RESTRICT); usamos o item 2
insert into public.review_item_flags (review_id, task_id, task_item_id) values (tests.fx('rev_p'), tests.fx('task_p'), tests.fx('task_p:item2'));
insert into public.template_items (id, template_id, position, text)
values (tests.fx('tpl_p:nunca_usado'), tests.fx('tpl_p'), 3, 'Item nunca usado');

create function tests.falhas_item2() returns bigint language sql as $$
  select count(*) from public.top_failed_items(current_date - 2, current_date + 2, array[tests.fx('store_p')]) f
  where f.template_item_id = tests.fx('tpl_p:item2')
$$;
grant execute on function tests.falhas_item2() to public;

select tests.authenticate_as('manager_p');
select is(tests.falhas_item2(), 1::bigint, 'antes: item 2 aparece em top_failed_items');
select alike(
  tests.exec_result($$ delete from public.template_items where id = tests.fx('tpl_p:item2') $$),
  '23503:%',
  'gerente NÃO apaga item de rotina já usado em tarefa (FK RESTRICT)');
select is(tests.falhas_item2(), 1::bigint, 'depois: a reprovação do item continua em top_failed_items');
select is(
  tests.exec_result($$ update public.template_items set is_active = false where id = tests.fx('tpl_p:item2') $$),
  'ok', 'gerente desativa o item (sai das próximas tarefas)');
select is(tests.falhas_item2(), 1::bigint, 'item desativado continua no histórico do indicador');
select is(
  tests.rows_result($$ delete from public.template_items where id = tests.fx('tpl_p:nunca_usado') $$),
  1, 'item nunca usado em tarefa pode ser apagado');

select tests.reset_role();
select is(
  (select count(*) from public.task_items where task_id = tests.fx('task_p') and template_item_id is not null),
  2::bigint,
  'linhagem dos itens da tarefa preservada'
);

select * from finish();
rollback;
