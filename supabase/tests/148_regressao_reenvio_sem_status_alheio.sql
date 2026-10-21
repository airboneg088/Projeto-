-- =============================================================================
-- 148 · Regressão R3-ISOLAMENTO-04: o reenvio de submit_attempt não conta a quem
-- já não executa a tarefa o que aconteceu com ela depois (D83). Quem ainda
-- executa recebe o status atual (a fila offline fica idempotente); quem não
-- executa mais (tarefa reatribuída, mudou de setor) recebe só o resultado da
-- PRÓPRIA tentativa: a decisão da revisão dela ou 'submitted'.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(6);

select tests.create_base_fixture();
select tests.create_task('rp', 'store_p', 'sector_p1', 'staff_p1');

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('rp'), gen_random_uuid());
select public.answer_item(tests.attempt_of('rp', 1), tests.fx('rp:item1'), true);
select public.answer_item(tests.attempt_of('rp', 1), tests.fx('rp:item2'), true);
select public.submit_attempt(tests.attempt_of('rp', 1));
select is(public.submit_attempt(tests.attempt_of('rp', 1)), 'submitted'::public.task_status,
  'quem ainda executa a tarefa recebe o status atual no reenvio');

-- Gerente reprova e reatribui; staff_p2 refaz e é aprovado
select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('rp', 1), 'rejected', 'Refazer');
select tests.authenticate_as('staff_p1');
select is(public.submit_attempt(tests.attempt_of('rp', 1)), 'rejected'::public.task_status,
  'reenvio depois da reprovação: status atual (ainda é dele)');
select tests.authenticate_as('manager_p');
update public.tasks set assignee_id = tests.fx('staff_p2') where id = tests.fx('rp');
select tests.authenticate_as('staff_p2');
select public.start_attempt(tests.fx('rp'), gen_random_uuid());
select public.answer_item(tests.attempt_of('rp', 2), tests.fx('rp:item1'), true);
select public.answer_item(tests.attempt_of('rp', 2), tests.fx('rp:item2'), true);
select public.submit_attempt(tests.attempt_of('rp', 2));

select tests.authenticate_as('staff_p1');
select is(public.submit_attempt(tests.attempt_of('rp', 1)), 'rejected'::public.task_status,
  'quem não executa mais recebe o resultado da própria tentativa (rejected), não o status atual (submitted)');

select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('rp', 2), 'approved');
select tests.authenticate_as('staff_p1');
select is((select count(*)::int from public.tasks where id = tests.fx('rp')), 0,
  'controle: staff_p1 já não lê a tarefa');
select isnt(public.submit_attempt(tests.attempt_of('rp', 1)), 'approved'::public.task_status,
  'o reenvio não revela que outra pessoa teve a tarefa aprovada depois');

-- Tentativa enviada e ainda sem revisão, de quem mudou de setor (tarefa de equipe)
select tests.reset_role();
select tests.create_task('eq', 'store_p', 'sector_p1', null, p_items => 1);
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('eq'), gen_random_uuid());
select public.answer_item(tests.attempt_of('eq', 1), tests.fx('eq:item1'), true);
select public.submit_attempt(tests.attempt_of('eq', 1));
select tests.reset_role();
update public.memberships set sector_id = tests.fx('sector_p2') where id = tests.fx('m_staff_p1');
select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('eq', 1), 'approved');
select tests.authenticate_as('staff_p1');
select is(public.submit_attempt(tests.attempt_of('eq', 1)), 'approved'::public.task_status,
  'quem saiu do setor ainda sabe o resultado da própria tentativa (approved)');

select * from finish();
rollback;
