-- =============================================================================
-- 094 · Regressão R1-ISO-05: quem teve o vínculo encerrado (ou o perfil
-- desativado) perde acesso na hora, também por notificações e pelos reenvios
-- idempotentes das RPCs (docs §6.4).
--   - notifications: só com perfil ativo e vínculo vigente (na loja da
--     notificação, quando ela é de uma loja);
--   - start_attempt, register_evidence e submit_attempt conferem o vínculo
--     ANTES de devolver o resultado de um reenvio.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(14);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_task('t_rep', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);

-- Notificação sem loja (ex.: resumo) para o colaborador P1
insert into public.notifications (id, recipient_id, store_id, task_id, type, channel, dedupe_key)
values (tests.fx('notif_rede'), tests.fx('staff_p1'), null, null, 'daily_summary', 'in_app', 'teste:rede');

-- Colaborador com vínculo vigente: inicia, registra foto (com client_mutation_id)
select tests.authenticate_as('staff_p1');
select is(tests.count_rows($$ select count(*) from public.notifications $$), 2::bigint,
  'controle: com vínculo vigente lê as próprias notificações (da loja e sem loja)');
select ok(public.start_attempt(tests.fx('t_rep'), tests.fx('cm_rep')) is not null, 'controle: inicia a tarefa');
select ok(
  public.register_evidence(tests.attempt_of('t_rep', 1), null, tests.upload_evidence('t_rep', 1, 'f_rep'),
    now(), null, null, null, tests.sha('foto rep'), null, 1000, true, tests.fx('cm_ev_rep')) is not null,
  'controle: registra a foto');

-- Vínculo encerrado exatamente agora (fim exclusivo) ---------------------------
select tests.reset_role();
update public.memberships set ends_at = now() where id = tests.fx('m_staff_p1');
select tests.authenticate_as('staff_p1');

select is(tests.count_rows($$ select count(*) from public.tasks $$), 0::bigint,
  'pré-condição: vínculo encerrado não vê tarefas');
select is(tests.count_rows($$ select count(*) from public.notifications where task_id = tests.fx('task_p') $$), 0::bigint,
  'vínculo encerrado NÃO lê notificação da tarefa da loja');
select is(tests.count_rows($$ select count(*) from public.notifications $$), 0::bigint,
  'vínculo encerrado NÃO lê nem notificação sem loja');
select is(tests.affected_rows($$ update public.notifications set read_at = now() $$), 0,
  'vínculo encerrado NÃO marca notificação como lida');
select throws_ok($$ select public.submit_attempt(tests.fx('att_p_sub')) $$, 'P0001', 'forbidden',
  'vínculo encerrado NÃO descobre o status da tarefa reenviando a tentativa');
select throws_ok($$ select public.start_attempt(tests.fx('t_rep'), tests.fx('cm_rep')) $$, 'P0001', 'forbidden',
  'vínculo encerrado NÃO recebe a tentativa pelo reenvio do início');
select throws_ok(
  $$ select public.register_evidence(tests.attempt_of('t_rep', 1), null, tests.evidence_path('t_rep', 1, 'f_rep'),
       now(), null, null, null, tests.sha('foto rep'), null, 1000, true, tests.fx('cm_ev_rep')) $$,
  'P0001', 'forbidden', 'vínculo encerrado NÃO recebe a evidência pelo reenvio da foto');
select throws_ok($$ select public.answer_item(tests.attempt_of('t_rep', 1), tests.fx('t_rep:item1'), true) $$,
  'P0001', 'forbidden', 'vínculo encerrado NÃO responde itens');

-- Perfil inativo com vínculo vigente ---------------------------------------------
select tests.reset_role();
update public.memberships set ends_at = null where id = tests.fx('m_staff_p1');
update public.profiles set status = 'inactive' where id = tests.fx('staff_p1');
select tests.authenticate_as('staff_p1');
select is(tests.count_rows($$ select count(*) from public.notifications $$), 0::bigint,
  'perfil inativo NÃO lê notificações');
select throws_ok($$ select public.submit_attempt(tests.fx('att_p')) $$, 'P0001', 'forbidden',
  'perfil inativo NÃO descobre o status da tarefa reenviando a tentativa');

-- Reativado: volta a ler
select tests.reset_role();
update public.profiles set status = 'active' where id = tests.fx('staff_p1');
select tests.authenticate_as('staff_p1');
select is(tests.count_rows($$ select count(*) from public.notifications $$), 2::bigint,
  'reativado: volta a ler as próprias notificações');

select * from finish();
rollback;
