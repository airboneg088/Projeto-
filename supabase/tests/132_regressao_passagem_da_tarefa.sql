-- =============================================================================
-- 132 · Regressão R2-REGRAS-S6 (R1-REGRAS-05): a tarefa não fica presa a quem
-- saiu. A tentativa aberta de quem deixou de poder executar a tarefa
-- (reatribuída, fora da equipe do setor, sem vínculo na loja) é encerrada sem
-- envio (abandoned_at + motivo, auditado), fica no histórico e congela; o novo
-- responsável inicia a tentativa seguinte. Quem saiu não responde, não registra
-- foto e não envia a tarefa de outra pessoa (acesso conferido de novo depois
-- das travas).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(17);

select tests.create_base_fixture();
select tests.create_user('staff_p3', '[TESTE] Colaborador P3', 'org_a');
select tests.create_membership('staff_p3', 'org_a', 'store_p', 'sector_p1', 'staff');

select tests.create_task('ho', 'store_p', 'sector_p1', 'staff_p1');
select tests.create_task('ho_eq', 'store_p', 'sector_p1', null);
select tests.create_task('ho_p3', 'store_p', 'sector_p1', 'staff_p3');

-- -----------------------------------------------------------------------------
-- Reatribuição de tarefa em andamento
-- -----------------------------------------------------------------------------
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('ho'), gen_random_uuid()) is not null as iniciada;
select public.answer_item(tests.attempt_of('ho', 1), tests.fx('ho:item1'), true);

select tests.authenticate_as('manager_p');
select is(
  tests.exec_result(format($$ update public.tasks set assignee_id = %L where id = %L $$,
                           tests.fx('staff_p2'), tests.fx('ho'))),
  'ok', 'gerente reatribui a tarefa em andamento para staff_p2');

select tests.reset_role();
select results_eq(
  format($$ select abandoned_reason, abandoned_at is not null, submitted_at is null
            from public.task_attempts where id = %L $$, tests.attempt_of('ho', 1)),
  $$ values ('reassigned'::text, true, true) $$,
  'a tentativa aberta de quem deixou de ser responsável é encerrada sem envio na hora (fica no histórico)');
select results_eq(
  format($$ select actor_id, action, diff -> 'abandoned_reason' ->> 'new'
            from public.audit_log where table_name = 'task_attempts' and record_id = %L $$,
         tests.attempt_of('ho', 1)::text),
  format($$ values (%L::uuid, 'attempt_abandoned'::text, 'reassigned'::text) $$, tests.fx('manager_p')),
  'a passagem fica no audit_log (attempt_abandoned, com o autor da reatribuição)');
select tests.authenticate_as('admin_a');
select is(
  (select count(*)::int from public.audit_log where table_name = 'task_attempts'),
  0, 'admin não lê o registro (conteúdo operacional, D15)');
select tests.reset_role();
select is(
  (select private.task_person(t.id, t.assignee_id, t.assignee_at_due, t.assignee_at_due_recorded)
   from public.tasks t where t.id = tests.fx('ho')),
  tests.fx('staff_p2'),
  'nos indicadores a tarefa passa a ser do novo responsável (tentativa encerrada sem envio não conta)');

-- Quem saiu não continua a tarefa de outra pessoa (mesmo com vínculo vigente na loja)
select tests.authenticate_as('staff_p1');
select throws_ok(
  format($$ select public.answer_item(%L, %L, true) $$, tests.attempt_of('ho', 1), tests.fx('ho:item2')),
  'P0001', 'forbidden', 'quem deixou de ser responsável não responde itens');
select throws_ok(
  format($$ select public.submit_attempt(%L) $$, tests.attempt_of('ho', 1)),
  'P0001', 'forbidden', 'quem deixou de ser responsável não envia a tarefa de outra pessoa');
select throws_ok(
  $$ select tests.upload_evidence('ho', 1, 'ho_foto_antiga') $$,
  '42501', null, 'nem envia foto para a tentativa encerrada (storage)');

-- O novo responsável executa
select tests.authenticate_as('staff_p2');
select lives_ok(
  $$ select public.start_attempt(tests.fx('ho'), gen_random_uuid()) $$,
  'o novo responsável inicia a tarefa reatribuída');
select tests.reset_role();
select results_eq(
  format($$ select a.attempt_number::int, a.performed_by, t.status::text, t.attempt_count::int
            from public.task_attempts a join public.tasks t on t.id = a.task_id
            where a.task_id = %L and a.abandoned_at is null and a.submitted_at is null $$, tests.fx('ho')),
  format($$ values (2, %L::uuid, 'in_progress'::text, 2) $$, tests.fx('staff_p2')),
  'a tentativa 2 é do novo responsável e a tarefa segue em andamento');

select tests.authenticate_as('staff_p2');
select public.answer_item(tests.attempt_of('ho', 2), tests.fx('ho:item1'), true);
select public.answer_item(tests.attempt_of('ho', 2), tests.fx('ho:item2'), true);
select is(public.submit_attempt(tests.attempt_of('ho', 2))::text, 'submitted',
  'o novo responsável envia a tarefa');

-- O histórico da tentativa encerrada não muda
select tests.reset_role();
select throws_ok(
  format($$ update public.task_attempts set abandoned_at = null, abandoned_reason = null where id = %L $$,
         tests.attempt_of('ho', 1)),
  'P0001', 'immutable', 'tentativa encerrada sem envio não é reaberta (nem pelo postgres)');
select throws_ok(
  format($$ delete from public.attempt_item_answers where attempt_id = %L $$, tests.attempt_of('ho', 1)),
  'P0001', 'immutable', 'as respostas da tentativa encerrada ficam congeladas');

-- -----------------------------------------------------------------------------
-- Tarefa de equipe: quem ainda pode executar mantém a tarefa; quem perdeu o
-- vínculo não a segura
-- -----------------------------------------------------------------------------
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('ho_eq'), gen_random_uuid()) is not null as iniciada;
select tests.authenticate_as('staff_p3');
select throws_ok(
  $$ select public.start_attempt(tests.fx('ho_eq'), gen_random_uuid()) $$,
  'P0001', 'invalid_transition', 'outro colaborador do setor não toma a tarefa de quem ainda pode executá-la');

select tests.reset_role();
update public.memberships set ends_at = now() where id = tests.fx('m_staff_p1');
select tests.authenticate_as('staff_p3');
select lives_ok(
  $$ select public.start_attempt(tests.fx('ho_eq'), gen_random_uuid()) $$,
  'tarefa de equipe não fica presa a quem perdeu o vínculo com a loja');
select tests.reset_role();
select results_eq(
  format($$ select attempt_number::int, performed_by, abandoned_reason
            from public.task_attempts where task_id = %L order by attempt_number $$, tests.fx('ho_eq')),
  format($$ values (1, %L::uuid, 'access_lost'::text), (2, %L::uuid, null::text) $$,
         tests.fx('staff_p1'), tests.fx('staff_p3')),
  'a tentativa de quem saiu fica no histórico (access_lost) e a nova é de quem assumiu');

-- Passar a tarefa para a equipe do setor de quem já executa não a tira dessa pessoa
select tests.authenticate_as('staff_p3');
select public.start_attempt(tests.fx('ho_p3'), gen_random_uuid()) is not null as iniciada;
select tests.authenticate_as('manager_p');
update public.tasks set assignee_id = null where id = tests.fx('ho_p3');
select tests.reset_role();
select is(
  (select abandoned_at from public.task_attempts where id = tests.attempt_of('ho_p3', 1)),
  null::timestamptz,
  'reatribuir à equipe do setor de quem está executando mantém a tentativa aberta');

select * from finish();
rollback;
