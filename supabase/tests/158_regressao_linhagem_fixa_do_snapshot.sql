-- =============================================================================
-- 158 · Regressão R4-REGRAS-09: a linhagem dos itens (D48, D75) é conferida com
-- o snapshot, não com o item ATUAL da rotina (D101). Depois que a rotina subia
-- de versão (o item crítico deixa de ser crítico na v2), o gerente conseguia
-- "alinhar" o item da tarefa de hoje, gerada na v1, ao conteúdo da v2: o item
-- crítico do snapshot v1 deixava de ser crítico e a tarefa continuava dizendo
-- template_version = 1. Agora o item que veio da rotina só muda de posição, e
-- item novo com linhagem só entra em tarefa da versão atual da rotina.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(7);

select tests.create_base_fixture();
insert into public.task_templates (id, organization_id, store_id, title, weight)
values (tests.fx('tpl'), tests.fx('org_a'), tests.fx('store_p'), 'Fechamento', 3);
insert into public.template_items (id, template_id, position, text, is_critical)
values (tests.fx('tpl:alarme'), tests.fx('tpl'), 1, 'Alarme ligado', true),
       (tests.fx('tpl:luzes'), tests.fx('tpl'), 2, 'Luzes apagadas', false);

-- Geração da tarefa de hoje (v1)
create temporary table gerada as
  select private.instantiate_task(tests.fx('tpl'), tests.fx('store_p'), tests.fx('sector_p1'), null,
                                  now() + interval '1 hour', now() + interval '3 hours') as id;
grant select on gerada to public;
select is((select template_version from public.tasks where id = (select id from gerada)), 1, 'tarefa gerada na v1');

-- Gerente edita a rotina para as próximas tarefas: o alarme deixa de ser crítico (v2)
select tests.authenticate_as('manager_p');
update public.template_items set is_critical = false, text = 'Alarme ligado (se houver)'
 where id = tests.fx('tpl:alarme');

select throws_ok(
  format($$ update public.task_items set is_critical = false, text = 'Alarme ligado (se houver)'
            where task_id = %L and template_item_id = %L $$, (select id from gerada), tests.fx('tpl:alarme')),
  '23514', 'invalid_snapshot', 'o item com linhagem da tarefa v1 não muda para o conteúdo da v2');
select tests.reset_role();
select throws_ok(
  format($$ update public.task_items set template_item_id = null where task_id = %L and template_item_id = %L $$,
         (select id from gerada), tests.fx('tpl:alarme')),
  '23514', 'invalid_snapshot', 'nem o sistema tira a linhagem (para depois editar o item à mão)');
select tests.authenticate_as('manager_p');
select lives_ok(
  format($$ update public.task_items set position = 9 where task_id = %L and template_item_id = %L $$,
         (select id from gerada), tests.fx('tpl:alarme')),
  'reordenar o item com linhagem continua permitido');

-- Item novo da rotina (v3) incluído na tarefa da v1: recusado (misturaria as versões)
select tests.reset_role();
insert into public.template_items (id, template_id, position, text, is_critical)
values (tests.fx('tpl:portas'), tests.fx('tpl'), 3, 'Portas trancadas', true);
select is((select version from public.task_templates where id = tests.fx('tpl')), 3,
  'contexto: a rotina está na v3');
select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ insert into public.task_items (task_id, template_item_id, position, text, is_critical)
            values (%L, %L, 3, 'Portas trancadas', true) $$, (select id from gerada), tests.fx('tpl:portas')),
  '23514', 'invalid_snapshot', 'item com linhagem não entra em tarefa de versão antiga da rotina');

select tests.reset_role();
select results_eq(
  format($$ select text, is_critical from public.task_items where task_id = %L and template_item_id = %L $$,
         (select id from gerada), tests.fx('tpl:alarme')),
  $$ values ('Alarme ligado'::text, true) $$,
  'o snapshot da v1 continua: item crítico');

select * from finish();
rollback;
