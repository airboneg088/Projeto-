-- =============================================================================
-- 098 · Regressão R1-ISO-09 e R1-FI-12: as RPCs não revelam se um id existe em
-- outra loja/organização. Id inexistente e id fora do alcance dão o mesmo erro
-- ('forbidden'), conferido antes de qualquer trava (SELECT ... FOR UPDATE).
-- Foto "parecida" (phash) só aponta para foto da mesma loja (que o gerente que
-- revisa consegue abrir; o colaborador não recebe id de outra loja).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(10);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('b');

select tests.authenticate_as('manager_p');
select is(
  tests.exec_result(format($$ select public.cancel_task(%L, 'x') $$, tests.fx('task_b'))),
  tests.exec_result(format($$ select public.cancel_task(%L, 'x') $$, gen_random_uuid())),
  'cancel_task: tarefa de outra org e id inexistente dão o mesmo erro');
select is(
  tests.exec_result(format($$ select public.review_attempt(%L, 'approved') $$, tests.fx('att_b_sub'))),
  tests.exec_result(format($$ select public.review_attempt(%L, 'approved') $$, gen_random_uuid())),
  'review_attempt: tentativa de outra org e id inexistente dão o mesmo erro');

select tests.authenticate_as('staff_p1');
select is(
  tests.exec_result(format($$ select public.start_attempt(%L, null) $$, tests.fx('task_b'))),
  tests.exec_result(format($$ select public.start_attempt(%L, null) $$, gen_random_uuid())),
  'start_attempt: tarefa de outra org e id inexistente dão o mesmo erro');
select is(
  tests.exec_result(format($$ select public.answer_item(%L, %L, true) $$, tests.fx('att_b'), tests.fx('task_b:item1'))),
  tests.exec_result(format($$ select public.answer_item(%L, %L, true) $$, gen_random_uuid(), gen_random_uuid())),
  'answer_item: tentativa de outra org e id inexistente dão o mesmo erro');
select is(
  tests.exec_result(format($$ select public.submit_attempt(%L) $$, tests.fx('att_b_sub'))),
  tests.exec_result(format($$ select public.submit_attempt(%L) $$, gen_random_uuid())),
  'submit_attempt: tentativa de outra org e id inexistente dão o mesmo erro');
select is(
  tests.exec_result(format(
    $$ select public.register_evidence(%L, null, 'x', now(), null, null, null, %L, null, 1, true, null) $$,
    tests.fx('att_b'), tests.sha('x'))),
  tests.exec_result(format(
    $$ select public.register_evidence(%L, null, 'x', now(), null, null, null, %L, null, 1, true, null) $$,
    gen_random_uuid(), tests.sha('x'))),
  'register_evidence: tentativa de outra org e id inexistente dão o mesmo erro');
select is(
  tests.exec_result(format($$ select public.start_attempt(%L, null) $$, tests.fx('task_b'))),
  'P0001:forbidden',
  'o erro comum é forbidden');

-- Foto parecida: só da mesma loja ----------------------------------------------------
select tests.reset_role();
select tests.create_task('t_ph_c', 'store_c', 'sector_c1', 'staff_c1', p_items => 1);
select tests.create_task('t_ph_p', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);

select tests.authenticate_as('staff_c1');
select public.start_attempt(tests.fx('t_ph_c'), null);
select public.register_evidence(tests.attempt_of('t_ph_c', 1), null, tests.upload_evidence('t_ph_c', 1, 'f_c'),
  now(), null, null, null, tests.sha('foto c'), x'0F0F0F0F0F0F0F0F'::bigint, 1000, true, null);

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('t_ph_p'), null);
select public.register_evidence(tests.attempt_of('t_ph_p', 1), null, tests.upload_evidence('t_ph_p', 1, 'f_p1'),
  now(), null, null, null, tests.sha('foto p1'), x'0F0F0F0F0F0F0F0E'::bigint, 1000, true, null);
select public.register_evidence(tests.attempt_of('t_ph_p', 1), null, tests.upload_evidence('t_ph_p', 1, 'f_p2'),
  now(), null, null, null, tests.sha('foto p2'), x'0F0F0F0F0F0F0F0C'::bigint, 1000, true, null);

select tests.reset_role();
select results_eq(
  $$ select suspicion, similar_to_id from public.evidences where sha256 = tests.sha('foto p1') $$,
  $$ values ('{}'::text[], null::uuid) $$,
  'foto parecida com a de OUTRA loja não aponta para ela'
);
select results_eq(
  $$ select suspicion, similar_to_id = (select e.id from public.evidences e where e.sha256 = tests.sha('foto p1'))
     from public.evidences where sha256 = tests.sha('foto p2') $$,
  $$ values (array['similar']::text[], true) $$,
  'foto parecida com outra da mesma loja é marcada e aponta para ela'
);
select is(
  (select count(*) from public.evidences e
   join public.evidences s on s.id = e.similar_to_id
   where s.store_id <> e.store_id),
  0::bigint,
  'nenhuma evidência aponta para foto de outra loja'
);

select * from finish();
rollback;
