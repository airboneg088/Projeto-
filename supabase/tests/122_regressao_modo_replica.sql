-- =============================================================================
-- 122 · Regressão R2-FUNC-12: session_replication_role = replica (o modo das
-- importações de dados) não desliga a imutabilidade nem a máquina de estados:
-- os gatilhos de guarda são ENABLE ALWAYS. INSERT de linha histórica continua
-- passando (restauração de dados), mas nada já gravado é reescrito.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(10);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_task('t_pend', 'store_p', 'sector_p1', 'staff_p1');

set local session_replication_role = replica;
select throws_ok($$ delete from public.audit_log where id = (select max(id) from public.audit_log) $$,
  'P0001', 'immutable', 'modo réplica: DELETE no audit_log continua proibido');
select throws_ok($$ update public.evidences set sha256 = repeat('0', 64) where id = tests.fx('ev_p') $$,
  'P0001', 'immutable', 'modo réplica: evidência continua imutável');
select throws_ok($$ delete from public.reviews where id = tests.fx('rev_p') $$,
  'P0001', 'immutable', 'modo réplica: revisão continua imutável');
select throws_ok($$ update public.task_attempts set note = 'reescrita' where id = tests.fx('att_p') $$,
  'P0001', 'immutable', 'modo réplica: tentativa enviada continua imutável');
select throws_ok($$ update public.tasks set status = 'approved' where id = tests.fx('t_pend') $$,
  'P0001', 'invalid_transition', 'modo réplica: pending -> approved continua fora da máquina de estados');
select throws_ok($$ delete from public.tasks where id = tests.fx('t_pend') $$,
  'P0001', 'immutable', 'modo réplica: tarefa continua sem DELETE');
select throws_ok($$ truncate public.audit_log $$,
  'P0001', 'immutable', 'modo réplica: TRUNCATE do audit_log continua bloqueado');
select throws_ok($$ truncate public.tasks cascade $$,
  'P0001', 'immutable', 'modo réplica: TRUNCATE de tarefas continua bloqueado');
-- Restauração: a linha histórica (já aprovada) entra como está
select lives_ok(
  format($$ insert into public.tasks (organization_id, store_id, sector_id, title, status, due_at)
            values (%L, %L, %L, 'Restaurada', 'approved', now() - interval '30 days') $$,
         tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1')),
  'modo réplica: INSERT de tarefa histórica (restauração) passa');
set local session_replication_role = origin;

select is(
  (select count(*) from pg_trigger t
   where t.tgrelid = any (array['public.audit_log', 'public.evidences', 'public.reviews', 'public.review_item_flags',
                                'public.task_attempts', 'public.attempt_item_answers', 'public.tasks',
                                'public.task_items']::regclass[])
     and t.tgname in ('audit_log_forbid_change', 'audit_log_forbid_truncate', 'evidences_guard_change',
                      'evidences_forbid_truncate', 'reviews_forbid_change', 'reviews_forbid_truncate',
                      'review_item_flags_forbid_change', 'review_item_flags_forbid_truncate',
                      'task_attempts_guard_change', 'task_attempts_forbid_truncate',
                      'attempt_item_answers_guard_change', 'attempt_item_answers_forbid_truncate',
                      'tasks_enforce_status', 'tasks_forbid_delete', 'tasks_forbid_truncate',
                      'task_items_guard_change', 'task_items_forbid_truncate')
     and t.tgenabled = 'A'),
  17::bigint, 'os 17 gatilhos de guarda estão ENABLE ALWAYS');

select * from finish();
rollback;
