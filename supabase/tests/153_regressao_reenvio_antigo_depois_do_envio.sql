-- =============================================================================
-- 153 · Regressão R3-REGRAS-06: o reenvio atrasado de uma resposta que já valeu
-- e depois foi corrigida devolve false (ignorado) também depois do envio, em vez
-- de virar erro attempt_closed (D88). Resposta nova (não mais antiga) numa
-- tentativa já enviada continua recusada.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(4);

select tests.create_base_fixture();
select tests.create_task('rp', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('rp'), tests.fx('rp:start'));
select public.answer_item(tests.attempt_of('rp', 1), tests.fx('rp:item1'), false, 'Etiqueta faltando',
                          tests.fx('rp:a1'), now() - interval '10 minutes');
select public.answer_item(tests.attempt_of('rp', 1), tests.fx('rp:item1'), true, null,
                          tests.fx('rp:a2'), now() - interval '5 minutes');
select public.submit_attempt(tests.attempt_of('rp', 1), null, tests.fx('rp:submit'));

select is(
  public.answer_item(tests.attempt_of('rp', 1), tests.fx('rp:item1'), false, 'Etiqueta faltando',
                     tests.fx('rp:a1'), now() - interval '10 minutes'),
  false, 'depois do envio: reenvio mais antigo devolve false, sem erro');
select is(
  public.answer_item(tests.attempt_of('rp', 1), tests.fx('rp:item1'), true, null, tests.fx('rp:a2'),
                     now() - interval '5 minutes'),
  true, 'depois do envio: reenvio idêntico (mesmo client_mutation_id) devolve true');
select throws_ok(
  format($$ select public.answer_item(%L, %L, false, 'Mudei de ideia', %L, now()) $$,
         tests.attempt_of('rp', 1), tests.fx('rp:item1'), tests.fx('rp:a3')),
  'P0001', 'attempt_closed', 'resposta nova numa tentativa enviada continua recusada');

select tests.reset_role();
select results_eq(
  format($$ select checked, note from public.attempt_item_answers where attempt_id = %L $$, tests.attempt_of('rp', 1)),
  $$ values (true, null::text) $$,
  'a resposta enviada é a mais nova');

select * from finish();
rollback;
