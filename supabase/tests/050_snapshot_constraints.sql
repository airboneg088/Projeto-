-- =============================================================================
-- 050 · Snapshot da rotina e constraints de integridade (docs §4)
-- Editar rotina/itens não muda tarefas já geradas; item usado não é apagado
-- (desativa); geração idempotente por (agendamento, dia); vínculos sem
-- sobreposição; pesos 1..5; owner/admin sempre de rede, gerente/colaborador
-- sempre com loja; uma pessoa, uma organização.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(46);

select tests.create_base_fixture();

-- Rotina da rede (a versão só sobe com edições feitas depois que alguma tarefa a usou)
create temporary table ref as
  select format('%s/rede/%s/%s.jpg', tests.fx('org_a'), tests.fx('tpl'), tests.fx('ref_abertura')) as path;
grant select on ref to public;
insert into public.task_templates (id, organization_id, store_id, title, instructions, reference_image_path,
                                   default_priority, requires_photo, requires_note, requires_approval, weight)
values (tests.fx('tpl'), tests.fx('org_a'), null, 'Abertura', 'Siga a ordem', (select path from ref),
        'high', false, true, true, 3);
insert into public.template_items (id, template_id, position, text, is_critical, requires_photo, weight)
values (tests.fx('tpl_i1'), tests.fx('tpl'), 1, 'Desligar alarme', true, false, 5),
       (tests.fx('tpl_i2'), tests.fx('tpl'), 2, 'Acender luzes', false, true, 2);
insert into public.schedules (id, store_id, template_id, sector_id, window_start, window_end)
values (tests.fx('sch'), tests.fx('store_p'), tests.fx('tpl'), tests.fx('sector_p1'), '07:30', '08:15');

-- Snapshot na geração --------------------------------------------------------
select is(
  (select version from public.task_templates where id = tests.fx('tpl')),
  1,
  'montar a rotina e os itens antes de qualquer tarefa não conta como edição (versão 1)'
);
select ok(
  private.instantiate_task(tests.fx('tpl'), tests.fx('store_p'), tests.fx('sector_p1'), null,
    '2026-03-10 10:30+00', '2026-03-10 11:15+00', tests.fx('sch'), '2026-03-10') is not null,
  'instantiate_task gera a tarefa e devolve o id'
);

create temporary table gen1 as
  select id from public.tasks where schedule_id = tests.fx('sch') and scheduled_date = '2026-03-10';

select results_eq(
  $$ select title, instructions, reference_image_path, priority::text, requires_photo, requires_note,
            requires_approval, weight, template_version, status::text, organization_id
     from public.tasks where id = (select id from gen1) $$,
  $$ values ('Abertura'::text, 'Siga a ordem'::text, (select path from ref), 'high'::text, false, true,
             true, 3::smallint, 1, 'pending'::text, tests.fx('org_a')) $$,
  'tarefa guarda o snapshot da rotina (título, instruções, imagem, prioridade, exigências, peso, versão)'
);
select results_eq(
  $$ select position, text, is_critical, requires_photo, weight, template_item_id
     from public.task_items where task_id = (select id from gen1) order by position $$,
  $$ values (1::smallint, 'Desligar alarme'::text, true, false, 5::smallint, tests.fx('tpl_i1')),
            (2::smallint, 'Acender luzes'::text, false, true, 2::smallint, tests.fx('tpl_i2')) $$,
  'itens copiados para task_items com a linhagem do item da rotina'
);

-- Idempotência por (agendamento, dia) ----------------------------------------
select is(
  private.instantiate_task(tests.fx('tpl'), tests.fx('store_p'), tests.fx('sector_p1'), null,
    '2026-03-10 10:30+00', '2026-03-10 11:15+00', tests.fx('sch'), '2026-03-10'),
  (select id from gen1),
  'gerar de novo para o mesmo agendamento e dia devolve a mesma tarefa'
);
select results_eq(
  $$ select (select count(*) from public.tasks where schedule_id = tests.fx('sch')),
            (select count(*) from public.task_items where task_id = (select id from gen1)) $$,
  $$ values (1::bigint, 2::bigint) $$,
  'rodar a geração duas vezes não duplica tarefa nem itens'
);
select throws_ok(
  $$ insert into public.tasks (organization_id, store_id, sector_id, schedule_id, scheduled_date, title, due_at)
     values (tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('sch'), '2026-03-10', 'Duplicada', now()) $$,
  '23505', null, 'UNIQUE (schedule_id, scheduled_date) barra a duplicata mesmo por INSERT direto'
);
select isnt(
  private.instantiate_task(tests.fx('tpl'), tests.fx('store_p'), tests.fx('sector_p1'), null,
    '2026-03-11 10:30+00', '2026-03-11 11:15+00', tests.fx('sch'), '2026-03-11', null, 'urgent'),
  (select id from gen1),
  'outro dia gera outra tarefa'
);
select is(
  (select priority::text from public.tasks where schedule_id = tests.fx('sch') and scheduled_date = '2026-03-11'),
  'urgent',
  'prioridade informada substitui a padrão da rotina'
);

-- Editar a rotina não altera tarefas já geradas -------------------------------
update public.task_templates
   set title = 'Abertura revisada', instructions = 'Nova ordem', requires_photo = true, weight = 5,
       default_priority = 'low'
 where id = tests.fx('tpl');
update public.template_items set text = 'Desativar alarme e conferir portas', weight = 4 where id = tests.fx('tpl_i1');
insert into public.template_items (id, template_id, position, text) values (tests.fx('tpl_i3'), tests.fx('tpl'), 3, 'Abrir portas');
-- Item já usado em tarefa não é apagado (linhagem das falhas recorrentes): desativa-se
select throws_ok(
  $$ delete from public.template_items where id = tests.fx('tpl_i2') $$,
  '23503', null, 'item de rotina já usado em tarefa não pode ser apagado'
);
update public.template_items set is_active = false where id = tests.fx('tpl_i2');

select results_eq(
  $$ select title, instructions, requires_photo, weight, priority::text, template_version
     from public.tasks where id = (select id from gen1) $$,
  $$ values ('Abertura'::text, 'Siga a ordem'::text, false, 3::smallint, 'high'::text, 1) $$,
  'tarefa gerada mantém o snapshot depois de editar a rotina'
);
select results_eq(
  $$ select position, text, weight, template_item_id from public.task_items
     where task_id = (select id from gen1) order by position $$,
  $$ values (1::smallint, 'Desligar alarme'::text, 5::smallint, tests.fx('tpl_i1')),
            (2::smallint, 'Acender luzes'::text, 2::smallint, tests.fx('tpl_i2')) $$,
  'itens da tarefa não mudam e mantêm a linhagem, mesmo com o item desativado na rotina'
);
select cmp_ok(
  (select version from public.task_templates where id = tests.fx('tpl')), '>', 1,
  'editar rotina e itens incrementa a versão'
);
select is(
  (select version from public.task_templates where id = tests.fx('tpl')),
  5,
  'versão sobe uma vez por edição (rotina + 3 mudanças de item, inclusive desativar = 5)'
);

select ok(
  private.instantiate_task(tests.fx('tpl'), tests.fx('store_p'), tests.fx('sector_p1'), null,
    '2026-03-12 10:30+00', '2026-03-12 11:15+00', tests.fx('sch'), '2026-03-12') is not null,
  'nova geração depois da edição'
);
select results_eq(
  $$ select t.title, t.weight, t.template_version, array_agg(ti.text order by ti.position)
     from public.tasks t join public.task_items ti on ti.task_id = t.id
     where t.schedule_id = tests.fx('sch') and t.scheduled_date = '2026-03-12'
     group by t.id $$,
  $$ values ('Abertura revisada'::text, 5::smallint, 5,
             array['Desativar alarme e conferir portas', 'Abrir portas']::text[]) $$,
  'tarefas novas usam a versão atual da rotina, só com os itens ativos (numerados em sequência)'
);
select results_eq(
  $$ select array_agg(ti.position order by ti.position)
     from public.tasks t join public.task_items ti on ti.task_id = t.id
     where t.schedule_id = tests.fx('sch') and t.scheduled_date = '2026-03-12' $$,
  $$ values (array[1, 2]::smallint[]) $$,
  'itens da tarefa nova ficam 1, 2 (sem buraco do item desativado)'
);

-- Geração recusa combinações inválidas
insert into public.task_templates (id, organization_id, store_id, title)
values (tests.fx('tpl_c'), tests.fx('org_a'), tests.fx('store_c'), 'Rotina da loja C'),
       (tests.fx('tpl_b'), tests.fx('org_b'), null, 'Rotina da org B');
select throws_ok(
  $$ select private.instantiate_task(tests.fx('tpl_c'), tests.fx('store_p'), tests.fx('sector_p1'), null, now(), now() + interval '1 hour') $$,
  'P0001', 'forbidden', 'rotina de outra loja não gera tarefa nesta loja'
);
select throws_ok(
  $$ select private.instantiate_task(tests.fx('tpl_b'), tests.fx('store_p'), tests.fx('sector_p1'), null, now(), now() + interval '1 hour') $$,
  'P0001', 'forbidden', 'rotina de outra organização não gera tarefa'
);
select throws_ok(
  $$ select private.instantiate_task(gen_random_uuid(), tests.fx('store_p'), tests.fx('sector_p1'), null, now(), now() + interval '1 hour') $$,
  'P0001', 'not_found', 'rotina inexistente: not_found'
);
select throws_ok(
  $$ select private.instantiate_task(tests.fx('tpl'), tests.fx('store_p'), tests.fx('sector_c1'), null, now(), now() + interval '1 hour') $$,
  '23503', null, 'setor de outra loja é recusado (FK composta setor/loja)'
);
select throws_ok(
  $$ insert into public.schedules (store_id, template_id, sector_id, window_start, window_end)
     values (tests.fx('store_p'), tests.fx('tpl_c'), tests.fx('sector_p1'), '08:00', '09:00') $$,
  '23514', 'invalid_template', 'agendamento não usa rotina de outra loja'
);
select throws_ok(
  $$ insert into public.schedules (store_id, template_id, sector_id, window_start, window_end)
     values (tests.fx('store_p'), tests.fx('tpl'), tests.fx('sector_p1'), '09:00', '08:00') $$,
  '23514', null, 'janela do agendamento precisa terminar depois de começar'
);
select throws_ok(
  $$ insert into public.schedules (store_id, template_id, sector_id, frequency, window_start, window_end)
     values (tests.fx('store_p'), tests.fx('tpl'), tests.fx('sector_p1'), 'weekly', '08:00', '09:00') $$,
  '23514', null, 'agendamento semanal exige rule.weekdays'
);

-- Vínculos sem sobreposição ---------------------------------------------------
select throws_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
     values (tests.fx('staff_p1'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p2'), 'staff', now() - interval '1 day') $$,
  '23P01', null, 'mesmo papel na mesma loja com período sobreposto é recusado'
);
select throws_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, role, starts_at, ends_at)
     values (tests.fx('owner_a'), tests.fx('org_a'), null, 'owner', now() - interval '60 days', now() - interval '10 days') $$,
  '23P01', null, 'vínculo de rede (loja nula) também não se sobrepõe'
);
select lives_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
     values (tests.fx('staff_p1'), tests.fx('org_a'), tests.fx('store_c'), tests.fx('sector_c1'), 'staff', now() - interval '1 day') $$,
  'mesma pessoa pode ter vínculo em outra loja no mesmo período'
);
select lives_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at, ends_at)
     values (tests.fx('staff_p2'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'staff',
             now() - interval '90 days', now() - interval '30 days') $$,
  'período anterior que termina quando o atual começa não se sobrepõe'
);
select lives_ok(
  $$
    with fim as (
      update public.memberships set ends_at = now() where id = tests.fx('m_staff_c1') returning profile_id
    )
    insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
    select profile_id, tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p2'), 'staff', now() from fim
  $$,
  'transferência: encerrar um vínculo e abrir outro no mesmo instante'
);
select throws_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, role, starts_at, ends_at)
     values (tests.fx('admin_a'), tests.fx('org_a'), tests.fx('store_p'), 'manager', now(), now() - interval '1 day') $$,
  '23514', null, 'fim do vínculo precisa ser depois do início'
);
select throws_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
     values (tests.fx('owner_a'), tests.fx('org_a'), tests.fx('store_b'), tests.fx('sector_b1'), 'staff') $$,
  '23503', null, 'loja precisa ser da mesma organização do vínculo'
);

-- store_id nulo só para owner e admin -------------------------------------------
select throws_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, role) values (tests.fx('manager_b'), tests.fx('org_a'), null, 'manager') $$,
  '23514', null, 'gerente sem loja é recusado'
);
select throws_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, role) values (tests.fx('manager_b'), tests.fx('org_a'), null, 'staff') $$,
  '23514', null, 'colaborador sem loja é recusado'
);
select tests.create_user('admin_novo', '[TESTE] Admin novo');
select tests.create_user('owner_novo', '[TESTE] Proprietária nova');
select lives_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, role) values (tests.fx('admin_novo'), tests.fx('org_a'), null, 'admin') $$,
  'admin de rede (loja nula) é aceito'
);
select lives_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, role) values (tests.fx('owner_novo'), tests.fx('org_a'), null, 'owner') $$,
  'proprietária de rede (loja nula) é aceita'
);
select throws_ok(
  format($$ insert into public.memberships (profile_id, organization_id, store_id, role) values (%L, %L, %L, %L) $$,
         tests.fx(p.who), tests.fx('org_a'), tests.fx('store_p'), p.role),
  '23514', null, format('%s de uma loja só é recusado (owner e admin são papéis de rede)', p.role)
)
from (values ('owner_novo', 'owner'), ('admin_novo', 'admin')) as p (who, role);               -- 2
select throws_ok(
  $$ insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
     values (tests.fx('staff_b1'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'staff') $$,
  '23514', 'profile_other_organization', 'pessoa de outra organização não recebe vínculo (uma pessoa, uma organização)'
);

-- Pesos de 1 a 5 ---------------------------------------------------------------
select throws_ok(
  format($$ insert into public.task_templates (organization_id, title, weight) values (%L, 'Peso', %s) $$, tests.fx('org_a'), w),
  '23514', null, format('peso %s na rotina é recusado', w)
)
from unnest(array[0, 6]) as w;                                                                   -- 2
select throws_ok(
  format($$ insert into public.template_items (template_id, position, text, weight) values (%L, 9, 'Peso', %s) $$, tests.fx('tpl'), w),
  '23514', null, format('peso %s no item da rotina é recusado', w)
)
from unnest(array[0, 6]) as w;                                                                   -- 2
select throws_ok(
  format($$ update public.tasks set weight = %s where id = %L $$, w, (select id from gen1)),
  '23514', null, format('peso %s na tarefa é recusado', w)
)
from unnest(array[0, 6]) as w;                                                                   -- 2
select throws_ok(
  format($$ update public.task_items set weight = %s where task_id = %L $$, w, (select id from gen1)),
  '23514', null, format('peso %s no item da tarefa é recusado', w)
)
from unnest(array[0, 6]) as w;                                                                   -- 2

select * from finish();
rollback;
