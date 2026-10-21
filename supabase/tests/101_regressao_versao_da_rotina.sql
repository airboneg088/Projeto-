-- =============================================================================
-- 101 · Regressão R1-FI-07: a versão da rotina (e o que a controla) não é
-- adulterável.
--   - authenticated não grava version, created_at nem created_by
--     (privilégio de coluna);
--   - nem a chave secreta grava version direto: o gatilho mantém a versão e só
--     ela sobe, de 1 em 1, com a edição do conteúdo ou dos itens.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(9);

select tests.create_base_fixture();
select tests.create_store_activity('p');
-- A rotina já foi usada (task_p cita tpl_p): editar sobe a versão

select tests.authenticate_as('manager_p');
-- Edição legítima: versão 1 -> 2
update public.task_templates set title = 'Rotina p (revisada)' where id = tests.fx('tpl_p');

select throws_ok($$ update public.task_templates set version = 1 where id = tests.fx('tpl_p') $$,
  '42501', null, 'gerente NÃO reescreve task_templates.version');
select throws_ok($$ update public.task_templates set created_at = '2999-01-01' where id = tests.fx('tpl_p') $$,
  '42501', null, 'gerente NÃO altera task_templates.created_at (coluna do sistema)');
select throws_ok($$ update public.task_templates set created_by = tests.fx('owner_a') where id = tests.fx('tpl_p') $$,
  '42501', null, 'gerente NÃO forja o autor da rotina');

insert into public.template_items (template_id, position, text) values (tests.fx('tpl_p'), 3, 'Item novo');

select tests.reset_role();
select is((select version from public.task_templates where id = tests.fx('tpl_p')), 3,
  'incluir item continua incrementando a versão (1 -> 2 -> 3)');

-- Nem a chave secreta grava a versão direto
select tests.authenticate_service_role();
update public.task_templates set version = 99 where id = tests.fx('tpl_p');
select is((select version from public.task_templates where id = tests.fx('tpl_p')), 3,
  'service_role: UPDATE só de version é ignorado (versão continua 3)');
update public.task_templates set version = 1, title = 'Rotina p (de novo)' where id = tests.fx('tpl_p');
select is((select version from public.task_templates where id = tests.fx('tpl_p')), 4,
  'service_role: editar o conteúdo sobe de 1 em 1, mesmo pedindo outra versão');
update public.task_templates set created_by = tests.fx('owner_a') where id = tests.fx('tpl_p');
select is((select created_by from public.task_templates where id = tests.fx('tpl_p')), null::uuid,
  'autor da rotina não muda depois de gravado (nem pela chave secreta)');

-- Item desativado também é edição (e a tarefa nova não o recebe)
select tests.authenticate_as('manager_p');
update public.template_items set is_active = false where id = tests.fx('tpl_p:item2');
select tests.reset_role();
select is((select version from public.task_templates where id = tests.fx('tpl_p')), 5,
  'desativar item sobe a versão');
create temporary table gerada as
  select private.instantiate_task(tests.fx('tpl_p'), tests.fx('store_p'), tests.fx('sector_p1'), null,
                                  now(), now() + interval '1 hour') as id;
select is(
  (select array_agg(ti.text order by ti.position)
   from public.task_items ti
   where ti.task_id = (select id from gerada)),
  array['Item crítico', 'Item novo']::text[],
  'tarefa gerada depois leva só os itens ativos'
);

select * from finish();
rollback;
