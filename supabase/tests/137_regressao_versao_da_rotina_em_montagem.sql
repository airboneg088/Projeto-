-- =============================================================================
-- 137 · Regressão R2-REGRAS-S4 (R1-REGRAS-12): rotina montada pela API em
-- vários pedidos (rotina, depois itens, depois imagem de referência) nasce e
-- fica na versão 1 enquanto nenhuma tarefa a usou. Depois do primeiro uso, cada
-- edição do conteúdo ou dos itens sobe a versão de 1 em 1.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(5);

select tests.create_base_fixture();

-- Pedido 1 (POST /rest/v1/task_templates), feito "há 1 segundo"
select tests.authenticate_as('manager_p');
insert into public.task_templates (organization_id, store_id, title)
values (tests.fx('org_a'), tests.fx('store_p'), 'Rotina nova');
select tests.reset_role();
create temporary table nova as select id from public.task_templates where title = 'Rotina nova';
grant select on nova to public;
update public.task_templates set created_at = now() - interval '1 second' where id = (select id from nova);

-- Pedido 2 (POST /rest/v1/template_items com 3 itens)
select tests.authenticate_as('manager_p');
insert into public.template_items (template_id, position, text)
select n.id, i, 'Item ' || i from nova n, generate_series(1, 3) as i;
-- Pedido 3: imagem de referência enviada depois (o caminho leva o id da rotina)
update public.task_templates
   set reference_image_path = format('%s/%s/%s/%s.jpg', tests.fx('org_a'), tests.fx('store_p'),
                                     (select id from nova), tests.fx('ref_nova'))
 where id = (select id from nova);
select tests.reset_role();
select is((select version from public.task_templates where id = (select id from nova)), 1,
  'rotina montada em vários pedidos, sem nenhuma tarefa, continua na versão 1');

-- Primeira tarefa usa a versão 1
create temporary table gerada as
  select private.instantiate_task((select id from nova), tests.fx('store_p'), tests.fx('sector_p1'), null,
                                  now(), now() + interval '1 hour') as id;
select is((select t.template_version from public.tasks t join gerada g on g.id = t.id), 1,
  'a primeira tarefa guarda a versão 1');

-- Depois do uso, editar é nova versão (uma por edição)
select tests.authenticate_as('manager_p');
update public.task_templates set title = 'Rotina nova (revisada)' where id = (select id from nova);
select tests.reset_role();
select is((select version from public.task_templates where id = (select id from nova)), 2,
  'editar a rotina já usada sobe a versão');
select tests.authenticate_as('manager_p');
insert into public.template_items (template_id, position, text) select n.id, 4, 'Item 4' from nova n;
select tests.reset_role();
select is((select version from public.task_templates where id = (select id from nova)), 3,
  'incluir item na rotina já usada sobe a versão');
select is(
  (select template_version from public.tasks where template_id = (select id from nova)),
  1, 'a tarefa gerada antes continua com o snapshot da versão 1');

select * from finish();
rollback;
