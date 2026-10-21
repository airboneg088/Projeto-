-- =============================================================================
-- 109 · Regressão R2-ISO-01: os gatilhos de validação (BEFORE, SECURITY
-- DEFINER) rodam antes do WITH CHECK da RLS. Quem grava pela API sem poder
-- gravar no destino recebia 23514 invalid_* quando a referência não valia lá e
-- 42501 quando valia: um oráculo de vínculos, da loja de uma rotina, da versão
-- de uma rotina e da linhagem de itens de outra loja/organização (D25).
-- Agora quem não tem alcance recebe sempre o erro da RLS, antes de qualquer
-- consulta; a validação só roda para quem pode gravar ali.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(14);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('c');
select tests.create_store_activity('b');

create function tests.probe_task(p_assignee text) returns text language sql as $$
  select tests.exec_result(format(
    $q$ insert into public.tasks (organization_id, store_id, sector_id, title, assignee_id, due_at)
        values (%L, %L, %L, 'x', %L, now() + interval '1 day') $q$,
    tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx(p_assignee)))
$$;
create function tests.probe_version(p_version integer) returns text language sql as $$
  select tests.exec_result(format(
    $q$ insert into public.tasks (organization_id, store_id, sector_id, title, template_id, template_version, weight, due_at)
        values (%L, %L, %L, 'x', %L, %s, 2, now() + interval '1 day') $q$,
    tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('tpl_p'), p_version))
$$;
create function tests.probe_sector(p_responsible text) returns text language sql as $$
  select tests.exec_result(format(
    $q$ insert into public.sectors (store_id, name, responsible_id) values (%L, 'Sonda', %L) $q$,
    tests.fx('store_p'), tests.fx(p_responsible)))
$$;
create function tests.probe_schedule(p_template text) returns text language sql as $$
  select tests.exec_result(format(
    $q$ insert into public.schedules (store_id, template_id, sector_id, window_start, window_end)
        values (%L, %L, %L, '08:00', '09:00') $q$,
    tests.fx('store_p'), tests.fx(p_template), tests.fx('sector_p1')))
$$;
create function tests.probe_plan(p_owner text) returns text language sql as $$
  select tests.exec_result(format(
    $q$ insert into public.action_plans (store_id, template_item_id, what, owner_id) values (%L, %L, 'x', %L) $q$,
    tests.fx('store_p'), tests.fx('tpl_p:item2'), tests.fx(p_owner)))
$$;
create function tests.probe_item(p_template_item text) returns text language sql as $$
  select tests.exec_result(format(
    $q$ insert into public.task_items (task_id, template_item_id, position, text) values (%L, %L, 9, 'x') $q$,
    tests.fx('task_p'), tests.fx(p_template_item)))
$$;
create function tests.probe_membership(p_profile text) returns text language sql as $$
  select tests.exec_result(format(
    $q$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
        values (%L, %L, %L, %L, 'staff') $q$,
    tests.fx(p_profile), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1')))
$$;
grant execute on all functions in schema tests to public;

-- Gerente da organização B sonda a loja P (organização A)
select tests.authenticate_as('manager_b');
select is(tests.probe_task('staff_p1'), tests.probe_task('staff_c1'),
  'gerente da org B NÃO descobre se uma pessoa tem vínculo na loja P (tasks.assignee_id)');
select is(tests.probe_version(1), tests.probe_version(2),
  'gerente da org B NÃO descobre a versão de uma rotina da org A (tasks.template_version)');
select is(tests.probe_sector('staff_p1'), tests.probe_sector('staff_c1'),
  'gerente da org B NÃO descobre vínculos da loja P (sectors.responsible_id)');
select is(tests.probe_schedule('tpl_p'), tests.probe_schedule('tpl_c'),
  'gerente da org B NÃO descobre a que loja pertence uma rotina da org A (schedules.template_id)');
select is(tests.probe_plan('staff_p1'), tests.probe_plan('staff_c1'),
  'gerente da org B NÃO descobre vínculos da loja P (action_plans.owner_id)');
select is(tests.probe_item('tpl_p:item1'), tests.probe_item('tpl_c:item1'),
  'gerente da org B NÃO descobre a linhagem de uma tarefa da org A (task_items.template_item_id)');
select is(tests.probe_membership('staff_p1'), tests.probe_membership('staff_b1'),
  'gerente da org B NÃO descobre pelo erro se uma pessoa é da org A (memberships)');
select alike(tests.probe_task('staff_p1'), '42501:new row violates row-level security policy for table "tasks"',
  'a resposta é o erro da RLS');

-- Colaborador da loja C (mesma organização) sonda a loja P
select tests.authenticate_as('staff_c1');
select is(tests.probe_task('staff_p2'), tests.probe_task('staff_b1'),
  'colaborador da loja C NÃO descobre quem tem vínculo na loja P (tasks.assignee_id)');
select is(tests.probe_sector('staff_p2'), tests.probe_sector('staff_b1'),
  'colaborador da loja C NÃO descobre vínculos da loja P (sectors.responsible_id)');

-- Controle: para quem pode gravar na loja, a validação continua valendo
select tests.authenticate_as('manager_p');
select alike(tests.probe_task('staff_c1'), '23514:invalid_assignee%',
  'gerente da loja P: responsável sem vínculo na loja continua recusado (invalid_assignee)');
select alike(tests.probe_version(2), '23514:invalid_template_version%',
  'gerente da loja P: versão diferente da atual continua recusada');
select alike(tests.probe_schedule('tpl_c'), '23514:invalid_template%',
  'gerente da loja P: rotina de outra loja continua recusada no agendamento');
select is(tests.probe_task('staff_p1'), 'ok',
  'gerente da loja P: tarefa com responsável da loja é aceita');

select * from finish();
rollback;
