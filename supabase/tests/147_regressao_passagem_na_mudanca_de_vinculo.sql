-- =============================================================================
-- 147 · Regressão R3-ISOLAMENTO-03 (D82):
--   (a) o upload no bucket evidences usa a mesma regra das RPCs: além de ser o
--       executor da tentativa aberta, a tarefa ainda precisa ser dele ou da
--       equipe do setor dele (private.can_execute_task);
--   (b) mudanças imediatas na pessoa encerram na hora as tentativas abertas que
--       ela não pode mais executar: troca de setor (reassigned), vínculo
--       encerrado agora ou apagado e perfil desativado (access_lost). Fim
--       agendado (ends_at no futuro) não muda nada agora.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(10);

select tests.create_base_fixture();
select tests.create_user('staff_p3', '[TESTE] Colaborador P3', 'org_a');
select tests.create_user('staff_p4', '[TESTE] Colaborador P4', 'org_a');
select tests.create_user('staff_p5', '[TESTE] Colaborador P5', 'org_a');
select tests.create_membership('staff_p3', 'org_a', 'store_p', 'sector_p1', 'staff');
select tests.create_membership('staff_p4', 'org_a', 'store_p', 'sector_p1', 'staff');
select tests.create_membership('staff_p5', 'org_a', 'store_p', 'sector_p1', 'staff');
select tests.create_task('eq1', 'store_p', 'sector_p1', null);
select tests.create_task('eq3', 'store_p', 'sector_p1', null);
select tests.create_task('eq4', 'store_p', 'sector_p1', null);
select tests.create_task('eq5', 'store_p', 'sector_p1', null);
select tests.create_task('dele', 'store_p', 'sector_p1', 'staff_p1');

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('eq1'), gen_random_uuid());
select public.start_attempt(tests.fx('dele'), gen_random_uuid());
select tests.authenticate_as('staff_p3');
select public.start_attempt(tests.fx('eq3'), gen_random_uuid());
select tests.authenticate_as('staff_p4');
select public.start_attempt(tests.fx('eq4'), gen_random_uuid());
select tests.authenticate_as('staff_p5');
select public.start_attempt(tests.fx('eq5'), gen_random_uuid());

-- (b) A proprietária move P1 para o setor P2 (mesma loja)
select tests.authenticate_as('owner_a');
select tests.affected_rows(format($$ update public.memberships set sector_id = %L where id = %L $$,
  tests.fx('sector_p2'), tests.fx('m_staff_p1')));
select tests.reset_role();
select is((select abandoned_reason from public.task_attempts where id = tests.attempt_of('eq1', 1)), 'reassigned',
  'troca de setor encerra na hora a tentativa aberta da tarefa de equipe do setor antigo');
select is((select abandoned_at from public.task_attempts where id = tests.attempt_of('dele', 1)), null,
  'a tarefa atribuída a ele mesmo continua com ele (ainda pode executar)');
select ok(
  (select private.task_person(t.id, t.assignee_id, t.assignee_at_due, t.assignee_at_due_recorded)
   from public.tasks t where t.id = tests.fx('eq1')) is null,
  'a tarefa de equipe deixa de contar para quem saiu do setor');
select is(
  (select count(*)::int from public.audit_log where action = 'attempt_abandoned' and record_id = tests.attempt_of('eq1', 1)::text
     and actor_id = tests.fx('owner_a')),
  1, 'o encerramento fica no audit_log, com quem mudou o vínculo');

-- (b) Admin desativa P3; proprietária encerra o vínculo de P4 agora e agenda o fim do de P5
select tests.authenticate_as('admin_a');
select public.set_profile_status(tests.fx('staff_p3'), 'inactive');
select tests.authenticate_as('owner_a');
select tests.affected_rows(format($$ update public.memberships set ends_at = now() where id = %L $$, tests.fx('m_staff_p4')));
select tests.affected_rows(format($$ update public.memberships set ends_at = now() + interval '7 days' where id = %L $$, tests.fx('m_staff_p5')));
select tests.reset_role();
select is((select abandoned_reason from public.task_attempts where id = tests.attempt_of('eq3', 1)), 'access_lost',
  'desativar a pessoa encerra na hora a tentativa aberta dela');
select is((select abandoned_reason from public.task_attempts where id = tests.attempt_of('eq4', 1)), 'access_lost',
  'encerrar o vínculo agora encerra na hora a tentativa aberta');
select is((select abandoned_at from public.task_attempts where id = tests.attempt_of('eq5', 1)), null,
  'fim de vínculo agendado para o futuro não encerra nada agora');

-- (a) Upload: a policy do bucket confere can_execute_task. Simula o caso em que a
-- tentativa ainda está aberta mas a tarefa já não é da pessoa (gatilho desligado
-- só neste teste, dentro da transação)
alter table public.memberships disable trigger memberships_release_attempts;
update public.memberships set sector_id = tests.fx('sector_p2') where id = tests.fx('m_staff_p5');
alter table public.memberships enable trigger memberships_release_attempts;
select tests.authenticate_as('staff_p5');
select is(
  tests.exec_result($$ select tests.upload_evidence('eq5', 1, 'eq5_depois_de_mudar_de_setor') $$) like '42501%',
  true, 'quem saiu do setor não grava foto no storage da tarefa que já não é dele');
select tests.authenticate_as('staff_p1');
select is(
  tests.exec_result($$ select tests.upload_evidence('dele', 1, 'dele_foto') $$),
  'ok', 'controle: na tarefa dele, o upload continua permitido');

-- Vínculo apagado (só a proprietária apaga) também encerra
select tests.reset_role();
select tests.create_task('eq6', 'store_p', 'sector_p1', null);
select tests.create_user('staff_p6', '[TESTE] Colaborador P6', 'org_a');
select tests.create_membership('staff_p6', 'org_a', 'store_p', 'sector_p1', 'staff');
select tests.authenticate_as('staff_p6');
select public.start_attempt(tests.fx('eq6'), gen_random_uuid());
select tests.reset_role();
delete from public.memberships where id = tests.fx('m_staff_p6');
select is((select abandoned_reason from public.task_attempts where id = tests.attempt_of('eq6', 1)), 'access_lost',
  'apagar o vínculo encerra a tentativa aberta');

select * from finish();
rollback;
