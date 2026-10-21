-- =============================================================================
-- 143 · Regressão R3-REGRAS-03: os itens do snapshot de uma tarefa gerada pela
-- rotina não somem nem mudam de texto sem rastro (D75).
--   - item que veio da rotina não sai da tarefa (invalid_snapshot) e não tem o
--     texto reescrito (o texto, como crítico/foto/peso, é o da rotina);
--   - incluir, alterar ou remover itens pela API fica no audit_log (task_items);
--     a geração pelo sistema não é registrada linha a linha;
--   - o admin não lê esses registros (conteúdo operacional, D15/D24).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(11);

select tests.create_base_fixture();

insert into public.task_templates (id, organization_id, store_id, title, weight)
values (tests.fx('sn_tpl'), tests.fx('org_a'), tests.fx('store_p'), 'Fechamento', 3);
insert into public.template_items (id, template_id, position, text, is_critical, requires_photo)
values (tests.fx('sn_tpl:i1'), tests.fx('sn_tpl'), 1, 'Alarme ligado', true, true),
       (tests.fx('sn_tpl:i2'), tests.fx('sn_tpl'), 2, 'Caixa conferido', true, false),
       (tests.fx('sn_tpl:i3'), tests.fx('sn_tpl'), 3, 'Luzes apagadas', false, false);

-- Geração pelo sistema (job diário / seed): snapshot com os 3 itens, sem auditoria linha a linha
select private.instantiate_task(tests.fx('sn_tpl'), tests.fx('store_p'), tests.fx('sector_p1'), null,
                                now() + interval '1 hour', now() + interval '3 hours') as tarefa
\gset
select is((select count(*)::int from public.audit_log where table_name = 'task_items'), 0,
  'a geração pelo sistema não grava cada item no audit_log');

select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ delete from public.task_items where task_id = %L and template_item_id = %L $$, :'tarefa', tests.fx('sn_tpl:i1')),
  '23514', 'invalid_snapshot', 'gerente NÃO tira o item crítico que veio da rotina');
select throws_ok(
  format($$ update public.task_items set text = 'Caixa conferido (se der tempo)' where task_id = %L and template_item_id = %L $$,
         :'tarefa', tests.fx('sn_tpl:i2')),
  '23514', 'invalid_snapshot', 'gerente NÃO reescreve o texto de item que veio da rotina');
select throws_ok(
  format($$ insert into public.task_items (task_id, template_item_id, position, text, is_critical, requires_photo)
            values (%L, %L, 8, 'Alarme (opcional)', true, true) $$, :'tarefa', tests.fx('sn_tpl:i1')),
  '23514', 'invalid_snapshot', 'item novo com linhagem precisa ter o texto do item da rotina');
select lives_ok(
  format($$ update public.task_items set position = 9 where task_id = %L and template_item_id = %L $$,
         :'tarefa', tests.fx('sn_tpl:i3')),
  'reordenar item continua permitido (com a tarefa pendente)');
select lives_ok(
  format($$ insert into public.task_items (task_id, position, text, is_critical, requires_photo)
            values (%L, 10, 'Item extra sem linhagem', false, true) $$, :'tarefa'),
  'item a mais, sem linhagem, continua permitido');
select lives_ok(
  format($$ delete from public.task_items where task_id = %L and template_item_id is null $$, :'tarefa'),
  'item sem linhagem pode sair');

select tests.reset_role();
select results_eq(
  format($$ select action, actor_id from public.audit_log
            where table_name = 'task_items' and organization_id = %L order by id $$, tests.fx('org_a')),
  format($$ values ('update'::text, %1$L::uuid), ('insert'::text, %1$L::uuid), ('delete'::text, %1$L::uuid) $$,
         tests.fx('manager_p')),
  'reordenar, incluir e remover item pela API ficam no audit_log, com o autor');
select is(
  (select diff -> 'text' ->> 'old' from public.audit_log where table_name = 'task_items' and action = 'delete'),
  'Item extra sem linhagem',
  'o registro da remoção guarda o item removido');
select is(
  (select count(*)::int from public.task_items ti where ti.task_id = :'tarefa' and ti.is_critical),
  2, 'os 2 itens críticos da rotina continuam na tarefa');

select tests.authenticate_as('admin_a');
select is(tests.count_rows($$ select count(*) from public.audit_log where table_name = 'task_items' $$), 0::bigint,
  'admin não lê os registros de itens da tarefa (conteúdo operacional, D15)');

select * from finish();
rollback;
