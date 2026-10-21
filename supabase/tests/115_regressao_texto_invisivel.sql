-- =============================================================================
-- 115 · Regressão R2-FUNC-02 (correção incompleta de R1-REGRAS-04): motivo de
-- reprovação/cancelamento e observação obrigatória não aceitam texto feito só
-- de caracteres invisíveis que uma lista de bloqueio não conhece (U+200E/U+200F,
-- U+00AD, U+034F, U+061C, U+115F, U+1160, U+17B4, U+202A-U+202E,
-- U+2061-U+2064, U+206A, U+2800, U+3164, U+FFA0, U+FFFC, U+1D173, U+E0020).
-- private.is_blank virou lista de PERMISSÃO: precisa de uma letra (latina, com
-- acentos) ou um número.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(15);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('c');
select tests.create_task('t_cancel', 'store_p', 'sector_p1', 'staff_p1');
select tests.create_task('t_note', 'store_p', 'sector_p1', 'staff_p1', p_requires_note => true, p_items => 1);

-- private.is_blank direto: todos os invisíveis da revisão, um a um e juntos
select is(
  (select count(*) from unnest(array[
     '200E', '200F', '00AD', '034F', '061C', '115F', '1160', '17B4', '202A', '202B', '202C',
     '202D', '202E', '2061', '2062', '2063', '2064', '206A', '2800', '3164', 'FFA0', 'FFFC',
     '1D173', 'E0020']) as c (hex)
   where not private.is_blank(chr(('x' || lpad(c.hex, 8, '0'))::bit(32)::int))),
  0::bigint, 'is_blank: cada caractere invisível sozinho é em branco');
select ok(private.is_blank(chr(x'3164'::int) || chr(x'3164'::int)), 'is_blank: U+3164 (preenchimento hangul) repetido é em branco');
select ok(private.is_blank(chr(x'2800'::int) || ' ' || chr(x'00AD'::int)), 'is_blank: U+2800 + espaço + U+00AD é em branco');
select ok(private.is_blank('... !!! ---'), 'is_blank: só pontuação é em branco');
select ok(not private.is_blank(chr(x'200E'::int) || 'Foto escura'), 'is_blank: texto de verdade com invisível na frente vale');
select ok(not private.is_blank('Ação'), 'is_blank: palavra acentuada vale');
select ok(not private.is_blank('3'), 'is_blank: número vale');
select is(private.clean_text(chr(x'200E'::int) || chr(x'2800'::int) || ' Foto escura ' || chr(x'E0020'::int)),
  'Foto escura', 'clean_text tira invisíveis e espaços das pontas');

-- Reprovação pelo gerente
select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ select public.review_attempt(%L, 'rejected', %L) $$, tests.fx('att_p_sub'), chr(x'200E'::int)),
  'P0001', 'reason_required', 'reprovação com motivo = U+200E (invisível) é recusada');
select tests.authenticate_as('manager_c');
select throws_ok(
  format($$ select public.review_attempt(%L, 'rejected', %L) $$, tests.fx('att_c_sub'), repeat(chr(x'3164'::int), 3)),
  'P0001', 'reason_required', 'reprovação com motivo = U+3164 x3 (invisível) é recusada');

-- Cancelamento pelo gerente
select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ select public.cancel_task(%L, %L) $$, tests.fx('t_cancel'), chr(x'2800'::int) || chr(x'200F'::int)),
  'P0001', 'reason_required', 'cancelamento com motivo = U+2800 + U+200F (invisível) é recusado');

-- Observação obrigatória do colaborador
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('t_note'), null);
select public.answer_item(tests.attempt_of('t_note', 1), tests.fx('t_note:item1'), true);
select throws_ok(
  format($$ select public.submit_attempt(%L, %L) $$, tests.attempt_of('t_note', 1), chr(x'00AD'::int) || chr(x'2061'::int)),
  'P0001', 'note_required', 'observação obrigatória = U+00AD + U+2061 (invisível) é recusada');

-- CHECK da tabela (vale até para a chave secreta e o postgres)
select tests.reset_role();
select throws_ok(
  format($$ update public.tasks set status = 'cancelled', cancel_reason = %L where id = %L $$,
         chr(x'115F'::int) || chr(x'FFA0'::int), tests.fx('task_p')),
  '23514', null, 'CHECK tasks_cancel_reason_required recusa motivo U+115F + U+FFA0');
select throws_ok(
  format($$ insert into public.reviews (attempt_id, task_id, reviewer_id, decision, reason)
            values (%L, %L, %L, 'rejected', %L) $$,
         tests.fx('att_p_sub'), tests.fx('task_p_sub'), tests.fx('manager_p'), chr(x'E0020'::int)),
  '23514', null, 'CHECK reviews_reason_required recusa motivo U+E0020');
select is(
  (select count(*) from public.reviews r where r.decision = 'rejected' and r.reason !~ '[0-9A-Za-zÀ-ÖØ-öø-ÿ]'),
  0::bigint, 'nenhuma reprovação gravada sem uma letra ou número no motivo');

select * from finish();
rollback;
