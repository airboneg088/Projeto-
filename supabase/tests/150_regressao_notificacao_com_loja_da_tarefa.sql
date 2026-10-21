-- =============================================================================
-- 150 · Regressão R3-ISOLAMENTO-06: notificação de tarefa leva a loja DA tarefa
-- (D85). store_id é o que a RLS usa para cortar quem saiu da loja, então não
-- pode ficar nulo nem apontar para outra loja (CHECK + FK composta para
-- tasks (id, store_id)). Quem foi transferido deixa de ler as notificações da
-- loja antiga.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(5);

select tests.create_base_fixture();
select tests.create_task('nt', 'store_p', 'sector_p2', 'staff_p2', p_items => 1);

select throws_ok(
  format($$ insert into public.notifications (recipient_id, store_id, task_id, type, dedupe_key, payload)
            values (%L, null, %L, 'due_soon', 'teste:sem-loja', '{"titulo": "Tarefa nt"}') $$,
         tests.fx('staff_p2'), tests.fx('nt')),
  '23514', null, 'notificação de tarefa sem loja é recusada');
select throws_ok(
  format($$ insert into public.notifications (recipient_id, store_id, task_id, type, dedupe_key, payload)
            values (%L, %L, %L, 'due_soon', 'teste:outra-loja', '{"titulo": "Tarefa nt"}') $$,
         tests.fx('staff_p2'), tests.fx('store_c'), tests.fx('nt')),
  '23503', null, 'notificação de tarefa com a loja de outra tarefa é recusada');
select lives_ok(
  format($$ insert into public.notifications (recipient_id, store_id, task_id, type, dedupe_key, payload)
            values (%L, %L, %L, 'due_soon', 'teste:certa', '{"titulo": "Tarefa nt"}') $$,
         tests.fx('staff_p2'), tests.fx('store_p'), tests.fx('nt')),
  'notificação de tarefa com a loja da tarefa é aceita');
select lives_ok(
  format($$ insert into public.notifications (recipient_id, store_id, task_id, type, dedupe_key)
            values (%L, null, null, 'daily_summary', 'teste:rede') $$, tests.fx('owner_a')),
  'notificação de rede (sem tarefa) continua sem loja');

-- staff_p2 é transferido da loja P para a loja C: deixa de ler a notificação da tarefa da loja P
update public.memberships set ends_at = now() where id = tests.fx('m_staff_p2');
insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
values (tests.fx('staff_p2'), tests.fx('org_a'), tests.fx('store_c'), tests.fx('sector_c1'), 'staff', now());
select tests.authenticate_as('staff_p2');
select is((select count(*)::int from public.notifications), 0,
  'transferido para a loja C não lê mais a notificação da tarefa da loja P');

select * from finish();
rollback;
