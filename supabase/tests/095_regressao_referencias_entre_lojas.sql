-- =============================================================================
-- 095 · Regressão R1-ISO-06 e R1-FI-09: escrita direta não aceita referência a
-- outra loja/organização (rotina, item de rotina, responsável, imagem de
-- referência), e o erro é o mesmo para id inexistente e id alheio.
-- Também: created_by é sempre quem está logado (R1-FI-07, parte de autoria).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(23);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('c');
select tests.create_store_activity('b');
select tests.create_task('t_pend', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);

select tests.authenticate_as('manager_p');

-- Recusas (mesmas do relatório) ------------------------------------------------
select isnt(tests.exec_result(format(
  $$ insert into public.tasks (organization_id, store_id, sector_id, template_id, template_version, title, due_at)
     values (%L, %L, %L, %L, 1, 'Avulsa', now() + interval '1 day') $$,
  tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('tpl_b'))), 'ok',
  'gerente P NÃO cria tarefa ligada a rotina de outra organização');
select isnt(tests.exec_result(format(
  $$ insert into public.tasks (organization_id, store_id, sector_id, template_id, template_version, title, due_at)
     values (%L, %L, %L, %L, 1, 'Avulsa', now() + interval '1 day') $$,
  tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('tpl_c'))), 'ok',
  'gerente P NÃO cria tarefa ligada a rotina da loja C');
select isnt(tests.exec_result(format(
  $$ insert into public.task_items (task_id, template_item_id, position, text) values (%L, %L, 9, 'Item') $$,
  tests.fx('t_pend'), tests.fx('tpl_b:item1'))), 'ok',
  'gerente P NÃO liga item de tarefa a item de rotina de outra organização');
select isnt(tests.exec_result(format(
  $$ insert into public.action_plans (store_id, template_item_id, what) values (%L, %L, 'Plano') $$,
  tests.fx('store_p'), tests.fx('tpl_b:item1'))), 'ok',
  'gerente P NÃO cria plano de ação para item de rotina de outra organização');
select isnt(tests.exec_result(format(
  $$ insert into public.schedules (store_id, template_id, sector_id, assignee_id, window_start, window_end)
     values (%L, %L, %L, %L, '08:00', '09:00') $$,
  tests.fx('store_p'), tests.fx('tpl_p'), tests.fx('sector_p1'), tests.fx('staff_b1'))), 'ok',
  'gerente P NÃO agenda rotina para pessoa de outra organização');
select isnt(tests.exec_result(format(
  $$ update public.tasks set assignee_id = %L where id = %L $$, tests.fx('staff_b1'), tests.fx('t_pend'))), 'ok',
  'gerente P NÃO atribui tarefa a pessoa de outra organização');
select isnt(tests.exec_result(format(
  $$ update public.task_templates set reference_image_path = %L where id = %L $$,
  format('%s/%s/%s/%s.jpg', tests.fx('org_b'), tests.fx('store_b'), tests.fx('tpl_b'), tests.fx('reffile_b')),
  tests.fx('tpl_p'))), 'ok',
  'gerente P NÃO aponta a imagem de referência para arquivo de outra organização');
select isnt(tests.exec_result(format(
  $$ insert into public.tasks (organization_id, store_id, sector_id, title, assignee_id, due_at)
     values (%L, %L, %L, 'Para a org B', %L, now() + interval '1 day') $$,
  tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('staff_b1'))), 'ok',
  'gerente P NÃO cria tarefa para pessoa de outra organização');
select isnt(tests.exec_result(format(
  $$ update public.task_items set template_item_id = %L where id = %L $$,
  tests.fx('tpl_b:item1'), tests.fx('t_pend:item1'))), 'ok',
  'gerente P NÃO troca a linhagem de item de tarefa');
select isnt(tests.exec_result(format(
  $$ update public.schedules set assignee_id = %L where id = %L $$, tests.fx('staff_b1'), tests.fx('sch_p'))), 'ok',
  'gerente P NÃO põe pessoa de outra organização como responsável do agendamento');
select isnt(tests.exec_result(format(
  $$ update public.sectors set responsible_id = %L where id = %L $$, tests.fx('manager_b'), tests.fx('sector_p1'))), 'ok',
  'gerente P NÃO põe pessoa de outra organização como responsável do setor');
select isnt(tests.exec_result(format(
  $$ update public.action_plans set owner_id = %L where id = %L $$, tests.fx('staff_b1'), tests.fx('ap_p'))), 'ok',
  'gerente P NÃO põe pessoa de outra organização como responsável do plano');
select isnt(tests.exec_result(format(
  $$ update public.action_plans set template_item_id = %L where id = %L $$, tests.fx('tpl_b:item2'), tests.fx('ap_p'))), 'ok',
  'gerente P NÃO troca o item do plano de ação');

-- Chaves de erro e mesma loja/organização ----------------------------------------
select is(
  tests.exec_result(format(
    $$ insert into public.tasks (organization_id, store_id, sector_id, template_id, template_version, title, due_at)
       values (%L, %L, %L, %L, 1, 'Avulsa', now() + interval '1 day') $$,
    tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('tpl_b'))),
  tests.exec_result(format(
    $$ insert into public.tasks (organization_id, store_id, sector_id, template_id, template_version, title, due_at)
       values (%L, %L, %L, %L, 1, 'Avulsa', now() + interval '1 day') $$,
    tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), gen_random_uuid())),
  'rotina de outra organização e rotina inexistente dão o mesmo erro (sem oráculo)'
);
select alike(tests.exec_result(format(
  $$ insert into public.tasks (organization_id, store_id, sector_id, template_id, template_version, title, due_at)
     values (%L, %L, %L, %L, 99, 'Versão inventada', now() + interval '1 day') $$,
  tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('tpl_p'))),
  '23514:invalid_template_version%', 'versão de snapshot que a rotina nunca teve é recusada');
select alike(tests.exec_result(format(
  $$ insert into public.tasks (organization_id, store_id, sector_id, title, assignee_id, due_at)
     values (%L, %L, %L, 'Para a loja C', %L, now() + interval '1 day') $$,
  tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('staff_c1'))),
  '23514:invalid_assignee%', 'responsável sem vínculo na loja da tarefa (mesmo da organização) é recusado');
select alike(tests.exec_result(format(
  $$ update public.tasks set reference_image_path = %L where id = %L $$,
  format('%s/%s/%s/%s.jpg', tests.fx('org_a'), tests.fx('store_c'), tests.fx('tpl_c'), tests.fx('reffile_c')),
  tests.fx('t_pend'))),
  '23514:invalid_reference_path%', 'imagem de referência de outra loja da organização é recusada na tarefa');
select alike(tests.exec_result(format(
  $$ update public.task_templates set reference_image_path = %L where id = %L $$,
  format('%s/%s/%s/%s.jpg', tests.fx('org_a'), tests.fx('store_p'), tests.fx('tpl_c'), tests.fx('reffile_x')),
  tests.fx('tpl_p'))),
  '23514:invalid_reference_path%', 'rotina só aponta imagem no caminho do próprio id');

-- O que é da própria loja continua aceito ------------------------------------------
select is(tests.exec_result(format(
  $$ insert into public.tasks (organization_id, store_id, sector_id, template_id, template_version, title, weight,
                               assignee_id, reference_image_path, due_at)
     values (%L, %L, %L, %L, 1, 'Da rotina', 2, %L, %L, now() + interval '1 day') $$,
  tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('tpl_p'), tests.fx('staff_p2'),
  format('%s/%s/%s/%s.jpg', tests.fx('org_a'), tests.fx('store_p'), tests.fx('tpl_p'), tests.fx('reffile_p')))), 'ok',
  'tarefa com rotina, responsável e imagem da própria loja é aceita');
select is(tests.exec_result(format(
  $$ update public.task_templates set reference_image_path = %L where id = %L $$,
  format('%s/%s/%s/%s.png', tests.fx('org_a'), tests.fx('store_p'), tests.fx('tpl_p'), tests.fx('nova_ref')),
  tests.fx('tpl_p'))), 'ok',
  'rotina aponta imagem no próprio caminho');
select is(tests.exec_result(format(
  $$ insert into public.action_plans (store_id, template_item_id, what, owner_id) values (%L, %L, 'Plano novo', %L) $$,
  tests.fx('store_p'), tests.fx('tpl_p:item2'), tests.fx('staff_p2'))), 'ok',
  'plano de ação com item da rotina da loja e responsável da loja é aceito');

-- created_by é quem está logado -----------------------------------------------------
select is(tests.exec_result(format(
  $$ insert into public.task_templates (organization_id, store_id, title) values (%L, %L, 'Rotina nova') $$,
  tests.fx('org_a'), tests.fx('store_p'))), 'ok', 'gerente cria rotina');
select tests.reset_role();
select results_eq(
  $$ select (select created_by from public.task_templates where title = 'Rotina nova'),
            (select created_by from public.action_plans where what = 'Plano novo') $$,
  $$ values (tests.fx('manager_p'), tests.fx('manager_p')) $$,
  'created_by de rotina e plano é quem estava logado'
);

select * from finish();
rollback;
