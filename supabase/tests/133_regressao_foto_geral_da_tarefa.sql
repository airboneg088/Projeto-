-- =============================================================================
-- 133 · Regressão R2-REGRAS-S0 (R1-REGRAS-08): tasks.requires_photo exige ao
-- menos uma foto GERAL da tarefa (evidences.task_item_id nulo), além das fotos
-- exigidas por item. A foto de um item não cumpre a foto da tarefa (ex.: rotina
-- Limpeza do seed: "foto do salão limpo" além da foto do piso).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(4);

select tests.create_base_fixture();
-- A tarefa exige foto E o item 1 exige foto
select tests.create_task('fg', 'store_p', 'sector_p1', 'staff_p1', p_requires_photo => true, p_item_photo => true);

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('fg'), gen_random_uuid()) is not null as iniciada;
select public.answer_item(tests.attempt_of('fg', 1), tests.fx('fg:item1'), true);
select public.answer_item(tests.attempt_of('fg', 1), tests.fx('fg:item2'), true);
-- Foto do item 1 e uma foto extra do item 2 (que não exige): nenhuma é foto geral
select public.register_evidence(tests.attempt_of('fg', 1), tests.fx('fg:item1'),
  tests.upload_evidence('fg', 1, 'fg_item1'), now(), null, null, null, tests.sha('fg item 1'), null, 1000, true,
  gen_random_uuid()) is not null as foto_item1;
select public.register_evidence(tests.attempt_of('fg', 1), tests.fx('fg:item2'),
  tests.upload_evidence('fg', 1, 'fg_item2'), now(), null, null, null, tests.sha('fg item 2'), null, 1000, true,
  gen_random_uuid()) is not null as foto_item2;

select throws_ok(
  format($$ select public.submit_attempt(%L) $$, tests.attempt_of('fg', 1)),
  'P0001', 'photo_required', 'fotos de itens não cumprem a foto exigida da tarefa (foto geral, sem item)');
select is((select status::text from public.tasks where id = tests.fx('fg')), 'in_progress',
  'a tarefa não foi enviada');

select public.register_evidence(tests.attempt_of('fg', 1), null,
  tests.upload_evidence('fg', 1, 'fg_geral'), now(), null, null, null, tests.sha('fg geral'), null, 1000, true,
  gen_random_uuid()) is not null as foto_geral;
select is(public.submit_attempt(tests.attempt_of('fg', 1))::text, 'submitted',
  'com a foto geral da tarefa (e a do item) o envio passa');

select tests.reset_role();
select results_eq(
  format($$ select count(*) filter (where task_item_id is null)::int, count(*)::int
            from public.evidences where attempt_id = %L $$, tests.attempt_of('fg', 1)),
  $$ values (1, 3) $$,
  'a tentativa enviada tem a foto geral e as dos itens');

select * from finish();
rollback;
