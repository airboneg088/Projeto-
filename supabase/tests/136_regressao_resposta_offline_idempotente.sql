-- =============================================================================
-- 136 · Regressão R2-REGRAS-S3 (R1-REGRAS-11, parte): resposta de item com
-- client_mutation_id e horário do aparelho (answered_at_device).
--   - reenvio do mesmo client_mutation_id não muda nada;
--   - reenvio offline atrasado (resposta mais antiga que a gravada) é ignorado e
--     não desfaz a resposta mais nova (answer_item devolve false);
--   - relógio do aparelho adiantado não "congela" o item (vale no máximo o
--     horário do servidor);
--   - o mesmo client_mutation_id em outro item é recusado.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(10);

select tests.create_base_fixture();
select tests.create_task('off', 'store_p', 'sector_p1', 'staff_p1');

select has_column('public', 'attempt_item_answers', 'client_mutation_id', 'respostas têm client_mutation_id');
select has_function('public', 'answer_item',
  array['uuid', 'uuid', 'boolean', 'text', 'uuid', 'timestamp with time zone'],
  'answer_item recebe client_mutation_id e o horário do aparelho');

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('off'), gen_random_uuid()) is not null as iniciada;

-- Aparelho: 10 min atrás desmarcou (cm_old); 5 min atrás marcou (cm_new).
-- A fila entrega a mais nova primeiro e depois reenvia a antiga.
select is(
  public.answer_item(tests.attempt_of('off', 1), tests.fx('off:item1'), true, null,
                     tests.fx('cm_new'), now() - interval '5 minutes'),
  true, 'a resposta mais nova é gravada');
select is(
  public.answer_item(tests.attempt_of('off', 1), tests.fx('off:item1'), false, 'Faltou etiqueta',
                     tests.fx('cm_old'), now() - interval '10 minutes'),
  false, 'o reenvio atrasado (mais antigo) é ignorado');
select results_eq(
  format($$ select checked, note, client_mutation_id from public.attempt_item_answers
            where attempt_id = %L and task_item_id = %L $$, tests.attempt_of('off', 1), tests.fx('off:item1')),
  format($$ values (true, null::text, %L::uuid) $$, tests.fx('cm_new')),
  'a resposta mais nova continua valendo');

-- Reenvio do mesmo pedido: nada muda (nem o horário gravado)
create temporary table antes as
  select answered_at, answered_at_device from public.attempt_item_answers
  where client_mutation_id = tests.fx('cm_new');
select is(
  public.answer_item(tests.attempt_of('off', 1), tests.fx('off:item1'), false, 'Outra coisa',
                     tests.fx('cm_new'), now()),
  true, 'reenvio do mesmo client_mutation_id é aceito sem mudar nada');
select results_eq(
  $$ select a.checked, a.answered_at_device = b.answered_at_device
     from public.attempt_item_answers a, antes b where a.client_mutation_id = tests.fx('cm_new') $$,
  $$ values (true, true) $$,
  'a resposta gravada é a mesma');

select throws_ok(
  format($$ select public.answer_item(%L, %L, true, null, %L, now()) $$,
         tests.attempt_of('off', 1), tests.fx('off:item2'), tests.fx('cm_new')),
  'P0001', 'forbidden', 'o mesmo client_mutation_id em outro item é recusado');

-- Relógio adiantado (amanhã) vale como "agora": a próxima resposta real não é ignorada
select public.answer_item(tests.attempt_of('off', 1), tests.fx('off:item2'), false, 'Prateleira vazia',
                          gen_random_uuid(), now() + interval '1 day');
select ok(
  (select answered_at_device <= now() from public.attempt_item_answers
   where attempt_id = tests.attempt_of('off', 1) and task_item_id = tests.fx('off:item2')),
  'horário do aparelho no futuro é gravado como o horário do servidor');
select is(
  public.answer_item(tests.attempt_of('off', 1), tests.fx('off:item2'), true),
  true, 'resposta online (sem horário do aparelho) vale pela ordem de chegada');

select * from finish();
rollback;
