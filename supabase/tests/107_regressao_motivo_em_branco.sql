-- =============================================================================
-- 107 · Regressão R1-REGRAS-04: "reprovação sem motivo é impossível" também
-- para motivo feito só de quebra de linha, tabulação, espaço não separável
-- (U+00A0) ou espaço invisível (U+200B). Vale para os CHECKs do banco e para as
-- RPCs (motivo de reprovação e de cancelamento, observação obrigatória).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(11);

select tests.create_base_fixture();

select tests.create_task('rj', 'store_p', 'sector_p1', 'staff_p1');
select tests.create_task('rj2', 'store_p', 'sector_p1', 'staff_p1');
select tests.create_task('rj3', 'store_p', 'sector_p1', 'staff_p1');
select tests.create_task('cx', 'store_p', 'sector_p1', 'staff_p1');
select tests.create_task('nt', 'store_p', 'sector_p1', 'staff_p1', p_requires_note => true);

create function tests.enviar(p text, p_note text default null) returns public.task_status language plpgsql as $$
declare a uuid;
begin
  a := public.start_attempt(tests.fx(p), gen_random_uuid());
  perform public.answer_item(a, tests.fx(p || ':item1'), true);
  perform public.answer_item(a, tests.fx(p || ':item2'), true);
  return public.submit_attempt(a, p_note);
end $$;
grant execute on function tests.enviar(text, text) to public;

select tests.authenticate_as('staff_p1');
select tests.enviar('rj');
select tests.enviar('rj2');
select tests.enviar('rj3');

select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ select public.review_attempt(%L, 'rejected', E'\n\t\n') $$, tests.attempt_of('rj', 1)),
  'P0001', 'reason_required', 'reprovação com motivo só de quebra de linha/tab falha');
select throws_ok(
  format($$ select public.review_attempt(%L, 'rejected', U&'\00A0\00A0') $$, tests.attempt_of('rj', 1)),
  'P0001', 'reason_required', 'reprovação com motivo só de espaço não separável falha');
select throws_ok(
  format($$ select public.review_attempt(%L, 'rejected', U&'\200B \3000') $$, tests.attempt_of('rj', 1)),
  'P0001', 'reason_required', 'reprovação com motivo só de espaços invisíveis do Unicode falha');
select throws_ok(
  format($$ select public.cancel_task(%L, E'\r\n') $$, tests.fx('cx')),
  'P0001', 'reason_required', 'cancelamento com motivo só de CRLF falha');
select is(
  public.review_attempt(tests.attempt_of('rj2', 1), 'rejected', U&'\00A0 Foto escura\000A\00A0'),
  'rejected'::public.task_status, 'motivo de verdade com espaços nas pontas é aceito');

select tests.authenticate_as('staff_p1');
select throws_ok(
  $$ select tests.enviar('nt', E'\n\n') $$,
  'P0001', 'note_required', 'observação obrigatória só com quebras de linha falha');
select is(tests.enviar('nt', U&'\00A0 Tudo conferido \00A0'), 'submitted'::public.task_status,
  'observação de verdade é aceita');

-- CHECKs valem mesmo direto no banco ---------------------------------------------
select tests.reset_role();
select is(
  (select reason from public.reviews where attempt_id = tests.attempt_of('rj2', 1)),
  'Foto escura', 'motivo gravado sem os espaços (inclusive U+00A0) das pontas');
select is(
  (select note from public.task_attempts where id = tests.attempt_of('nt', 1)),
  'Tudo conferido', 'observação gravada sem os espaços das pontas');
select throws_ok(
  format($$ insert into public.reviews (attempt_id, task_id, reviewer_id, decision, reason)
            values (%L, %L, %L, 'rejected', U&'\00A0\0009') $$,
         tests.attempt_of('rj3', 1), tests.fx('rj3'), tests.fx('manager_p')),
  '23514', null, 'CHECK em reviews: motivo só de espaços não separáveis/tab é recusado');
select throws_ok(
  format($$ update public.tasks set status = 'cancelled', cancel_reason = E'\t\n' where id = %L $$, tests.fx('cx')),
  '23514', null, 'CHECK em tasks: cancelamento com motivo em branco é recusado');

select * from finish();
rollback;
