-- =============================================================================
-- 140 · Regressão R3-REGRAS-01: o fluxo offline não perde a foto por causa do
-- horário da sincronização. start_attempt recebe o horário do aparelho em que a
-- pessoa abriu a tarefa (p_started_at_device, D72); register_evidence compara o
-- EXIF com esse início (10 min de tolerância), não com a hora em que a fila
-- chegou ao servidor. O início do aparelho é limitado pelo servidor: nunca antes
-- da janela (nem da criação, nem do fim da tentativa anterior) nem depois de
-- agora, então não serve para "liberar" foto antiga.
-- Cena: 07:35 abre a tarefa no estoque sem internet; 07:40 tira a foto; 08:05 a
-- fila sincroniza (no teste, now() = sincronização; a foto tem EXIF now() - 25 min).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(12);

select tests.create_base_fixture();
-- Janela aberta há 1 h (tests.create_task); foto geral obrigatória
select tests.create_task('off', 'store_p', 'sector_p1', 'staff_p1', p_requires_photo => true, p_items => 1);
select tests.create_task('off_janela', 'store_p', 'sector_p1', 'staff_p1', p_requires_photo => true, p_items => 1);
select tests.create_task('off_online', 'store_p', 'sector_p1', 'staff_p1', p_requires_photo => true, p_items => 1);

select tests.authenticate_as('staff_p1');

-- Fila offline: o início leva o horário do aparelho (30 min atrás)
select ok(public.start_attempt(tests.fx('off'), tests.fx('off:start'), now() - interval '30 minutes') is not null,
  'início offline sincronizado com o horário do aparelho');
select tests.upload_evidence('off', 1, 'off_foto');
select lives_ok(
  format($$ select public.register_evidence(%L, null, %L, now() - interval '25 minutes',
                                             -23.55, -46.63, 8, %L, null, 250000, true, %L) $$,
         tests.attempt_of('off', 1), tests.evidence_path('off', 1, 'off_foto'), tests.sha('off-foto'), tests.fx('off:foto')),
  'foto tirada offline 25 min antes da sincronização (depois de abrir a tarefa) é aceita');
select public.answer_item(tests.attempt_of('off', 1), tests.fx('off:item1'), true, null, tests.fx('off:ans'),
                          now() - interval '20 minutes');
select is(public.submit_attempt(tests.attempt_of('off', 1), null, tests.fx('off:submit')), 'submitted'::public.task_status,
  'o envio feito offline sincroniza (sem photo_required)');

-- Reenvio do mesmo início não muda nada
select is(public.start_attempt(tests.fx('off'), tests.fx('off:start'), now() - interval '2 hours'),
          tests.attempt_of('off', 1), 'reenvio do início devolve a mesma tentativa');

select tests.reset_role();
select results_eq(
  format($$ select started_at_device = now() - interval '30 minutes', started_at = now()
            from public.task_attempts where id = %L $$, tests.attempt_of('off', 1)),
  $$ values (true, true) $$,
  'grava o início do aparelho; started_at continua sendo a hora do servidor');

-- O aparelho não volta antes da janela: foto de antes da janela continua recusada
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('off_janela'), null, now() - interval '3 days');
select tests.reset_role();
select is(
  (select a.started_at_device = t.window_start_at
   from public.task_attempts a join public.tasks t on t.id = a.task_id
   where a.id = tests.attempt_of('off_janela', 1)),
  true, 'início do aparelho antes da janela é limitado ao início da janela');
select tests.authenticate_as('staff_p1');
select tests.upload_evidence('off_janela', 1, 'off_janela_foto');
select throws_ok(
  format($$ select public.register_evidence(%L, null, %L, now() - interval '2 days',
                                             null, null, null, %L, null, 250000, true, null) $$,
         tests.attempt_of('off_janela', 1), tests.evidence_path('off_janela', 1, 'off_janela_foto'), tests.sha('foto-velha')),
  'P0001', 'photo_before_start', 'foto antiga (antes da janela) continua recusada mesmo com início "voltado" no aparelho');

-- Relógio do aparelho adiantado: o início nunca passa da hora do servidor
select tests.reset_role();
select tests.create_task('off_futuro', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('off_futuro'), null, now() + interval '1 day');
select tests.reset_role();
select is((select started_at_device from public.task_attempts where id = tests.attempt_of('off_futuro', 1)), now(),
  'início do aparelho no futuro é limitado à hora do servidor');

-- Online (sem horário do aparelho): a regra de antes vale
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('off_online'), null);
select tests.upload_evidence('off_online', 1, 'off_online_foto');
select throws_ok(
  format($$ select public.register_evidence(%L, null, %L, now() - interval '25 minutes',
                                             null, null, null, %L, null, 250000, true, null) $$,
         tests.attempt_of('off_online', 1), tests.evidence_path('off_online', 1, 'off_online_foto'), tests.sha('foto-online')),
  'P0001', 'photo_before_start', 'online, foto com EXIF mais de 10 min antes do início continua recusada');
select tests.reset_role();
select is((select started_at_device from public.task_attempts where id = tests.attempt_of('off_online', 1)), null,
  'online, started_at_device fica nulo');

-- Tentativa seguinte: o aparelho não volta para antes da reprovação da anterior
select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('off', 1), 'rejected', 'Foto escura');
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('off'), null, now() - interval '30 minutes');
select tests.reset_role();
select ok(
  -- (no teste tudo roda numa transação: a revisão usa o relógio real e o início fica
  -- limitado a now(), o horário da transação)
  (select a2.started_at_device >= least(r.reviewed_at, now())
   from public.task_attempts a2
   join public.reviews r on r.attempt_id = tests.attempt_of('off', 1)
   where a2.id = tests.attempt_of('off', 2)),
  'na tentativa 2, o início do aparelho não fica antes da reprovação da tentativa 1');
select ok(
  not exists (select 1 from public.task_attempts where started_at_device > started_at),
  'CHECK: o início do aparelho nunca passa do início no servidor');

select * from finish();
rollback;
