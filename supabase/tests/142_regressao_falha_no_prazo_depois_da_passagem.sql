-- =============================================================================
-- 142 · Regressão R3-REGRAS-08: depois do prazo, reatribuir a tarefa (que
-- encerra a tentativa aberta, D52) não tira a falha de quem estava com ela no
-- prazo nem a joga em quem só socorreu (D46, D74). Para tarefa vencida e não
-- aprovada, a pessoa da tarefa é quem a executava no prazo (tentativa iniciada
-- até o prazo e não encerrada antes dele); sem ela, o responsável no prazo.
--   (a) tarefa de equipe iniciada a tempo por P1 e passada a P2 depois do prazo
--   (b) tarefa de P1 passada, vencida, a P3, que a inicia
--   (c) aprovada depois do prazo por quem recebeu: a aprovação é de quem executou
--   (d) antes do prazo, a pessoa segue a reatribuição (D52)
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(8);

select tests.create_base_fixture();
select tests.create_user('staff_p3', '[TESTE] Colaborador P3', 'org_a');
select tests.create_membership('staff_p3', 'org_a', 'store_p', 'sector_p1', 'staff');

-- Tarefas que venceram há 30 min, com a tentativa de staff_p1 aberta desde 1 h antes do prazo
create function tests.vencida(p_name text, p_assignee text) returns void language plpgsql as $$
begin
  insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at, created_at)
  values (tests.fx(p_name), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Abertura ' || p_name,
          case when p_assignee is null then null else tests.fx(p_assignee) end,
          now() - interval '2 hours', now() - interval '30 minutes', now() - interval '3 hours');
  insert into public.task_items (id, task_id, position, text) values (tests.fx(p_name || ':item1'), tests.fx(p_name), 1, 'Item 1');
  perform tests.walk(tests.fx(p_name), 'in_progress');
  insert into public.task_attempts (task_id, store_id, attempt_number, performed_by, started_at)
  values (tests.fx(p_name), tests.fx('store_p'), 1, tests.fx('staff_p1'), now() - interval '90 minutes');
  update public.tasks set attempt_count = 1 where id = tests.fx(p_name);
end $$;
select tests.vencida('vt_eq', null);
select tests.vencida('vt_at', 'staff_p1');
select tests.vencida('vt_ap', 'staff_p1');

create function tests.person_of(p_name text) returns text language sql security definer set search_path = '' as $$
  select coalesce(pr.full_name, 'Sem responsável')
  from public.tasks t
  left join public.profiles pr
    on pr.id = private.task_person(t.id, t.assignee_id, t.assignee_at_due, t.assignee_at_due_recorded)
  where t.id = tests.fx(p_name)
$$;

-- (a) equipe: passada a staff_p2 depois do prazo
select tests.authenticate_as('manager_p');
update public.tasks set assignee_id = tests.fx('staff_p2') where id = tests.fx('vt_eq');
select tests.reset_role();
select is((select abandoned_reason from public.task_attempts where task_id = tests.fx('vt_eq')), 'reassigned',
  'sanidade: a passagem encerrou a tentativa de staff_p1');
select is(tests.person_of('vt_eq'), '[TESTE] Colaborador P1',
  '(a) equipe: reatribuir depois do prazo não tira a atrasada de quem a executava no prazo');

-- (b) atribuída: passada a staff_p3, que inicia já vencida
select tests.authenticate_as('manager_p');
update public.tasks set assignee_id = tests.fx('staff_p3') where id = tests.fx('vt_at');
select tests.authenticate_as('staff_p3');
select public.start_attempt(tests.fx('vt_at'), gen_random_uuid()) is not null as p3_iniciou;
select tests.reset_role();
select is(tests.person_of('vt_at'), '[TESTE] Colaborador P1',
  '(b) atribuída: quem recebeu a tarefa já vencida e a iniciou não herda a atrasada');

select tests.authenticate_as('owner_a');
select is(
  (select atrasadas from public.kpi_summary(current_date - 2, current_date + 2, null, null, array[tests.fx('staff_p1')])),
  3, 'filtro de pessoa: staff_p1 continua com as 3 atrasadas');
select is(
  (select count(*)::int from public.weighted_scores(current_date - 2, current_date + 2, 'person')
   where group_id in (tests.fx('staff_p2'), tests.fx('staff_p3'))),
  0, 'nota por pessoa: quem socorreu não herda a falha');

-- (c) vt_ap passada a staff_p3, que executa e é aprovado: a aprovação é de quem executou
select tests.authenticate_as('manager_p');
update public.tasks set assignee_id = tests.fx('staff_p3') where id = tests.fx('vt_ap');
select tests.authenticate_as('staff_p3');
select public.start_attempt(tests.fx('vt_ap'), gen_random_uuid());
select public.answer_item(tests.attempt_of('vt_ap', 2), tests.fx('vt_ap:item1'), true);
select public.submit_attempt(tests.attempt_of('vt_ap', 2));
select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('vt_ap', 2), 'approved');
select tests.reset_role();
select is(tests.person_of('vt_ap'), '[TESTE] Colaborador P3',
  '(c) aprovada: a aprovação conta para quem executou a tentativa aprovada');

-- (d) antes do prazo, a pessoa segue a reatribuição
select tests.create_task('no_prazo', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('no_prazo'), gen_random_uuid());
select tests.authenticate_as('manager_p');
update public.tasks set assignee_id = tests.fx('staff_p2') where id = tests.fx('no_prazo');
select tests.reset_role();
select is(tests.person_of('no_prazo'), '[TESTE] Colaborador P2',
  '(d) antes do prazo: a tarefa passa a ser de quem a recebeu (D52)');

-- Tentativa encerrada ANTES do prazo (passagem a tempo) não prende a falha a quem passou
insert into public.tasks (id, organization_id, store_id, sector_id, title, assignee_id, window_start_at, due_at, created_at)
values (tests.fx('vt_cedo'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Passada a tempo',
        tests.fx('staff_p2'), now() - interval '2 hours', now() - interval '30 minutes', now() - interval '3 hours');
select tests.walk(tests.fx('vt_cedo'), 'in_progress');
insert into public.task_attempts (task_id, store_id, attempt_number, performed_by, started_at, abandoned_at, abandoned_reason)
values (tests.fx('vt_cedo'), tests.fx('store_p'), 1, tests.fx('staff_p1'), now() - interval '90 minutes',
        now() - interval '60 minutes', 'reassigned');
select is(tests.person_of('vt_cedo'), '[TESTE] Colaborador P2',
  'tentativa encerrada antes do prazo: a falha é de quem recebeu a tarefa a tempo');

select * from finish();
rollback;
