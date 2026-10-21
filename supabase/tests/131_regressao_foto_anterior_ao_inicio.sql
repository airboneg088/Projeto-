-- =============================================================================
-- 131 · Regressão R2-REGRAS-08: foto com EXIF tirada ANTES do início da
-- tentativa é recusada (photo_before_start) e não cumpre "foto obrigatória"
-- (PDF <evidencia_confiavel>). Tolerância de 10 min para o relógio do aparelho
-- (o mesmo limite de clock_skew). Sem EXIF, a foto entra com a suspeita
-- no_exif ("não bloquear sem confirmar comigo").
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(5);
select tests.create_base_fixture();
select tests.create_task('r2old', 'store_p', 'sector_p1', 'staff_p1', p_requires_photo => true, p_items => 1);

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('r2old'), gen_random_uuid()) is not null as iniciada;
select public.answer_item(tests.attempt_of('r2old', 1), tests.fx('r2old:item1'), true);

select throws_ok(
  format($$ select public.register_evidence(%L, null, %L, now() - interval '2 days', -23.5, -46.6, 10,
                                            %L, null, 1000, true, gen_random_uuid()) $$,
         tests.attempt_of('r2old', 1), tests.upload_evidence('r2old', 1, 'foto-velha'), tests.sha('foto-velha')),
  'P0001', 'photo_before_start',
  'foto com EXIF de 2 dias antes do início da tentativa é recusada');
select throws_ok(
  format($$ select public.submit_attempt(%L) $$, tests.attempt_of('r2old', 1)),
  'P0001', 'photo_required',
  'a foto antiga não cumpre a foto obrigatória');

-- Relógio do aparelho até 10 min atrasado: aceita
select ok(
  public.register_evidence(tests.attempt_of('r2old', 1), null, tests.upload_evidence('r2old', 1, 'foto-relogio'),
    now() - interval '8 minutes', null, null, null, tests.sha('foto-relogio'), null, 1000, true, gen_random_uuid()) is not null,
  'foto com relógio do aparelho 8 min atrasado é aceita');
-- Sem horário de captura: aceita, marcada como sem EXIF
select ok(
  public.register_evidence(tests.attempt_of('r2old', 1), null, tests.upload_evidence('r2old', 1, 'foto-sem-hora'),
    null, null, null, null, tests.sha('foto-sem-hora'), null, 1000, true, gen_random_uuid()) is not null,
  'foto sem horário de captura é aceita');
select is(
  (select suspicion from public.evidences where sha256 = tests.sha('foto-sem-hora')),
  array['no_exif']::text[], 'foto sem horário de captura fica com a suspeita no_exif');

select * from finish();
rollback;
