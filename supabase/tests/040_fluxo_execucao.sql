-- =============================================================================
-- 040 · Fluxo de execução e revisão pelas funções RPC
-- Caminho feliz; foto obrigatória (item e tarefa); itens incompletos;
-- observação obrigatória; auto-aprovação; reprovação sem motivo; reprovar ->
-- tentativa 2 -> aprovar com histórico completo; auto-revisão proibida;
-- colaborador não revisa/cancela; idempotência por client_mutation_id;
-- foto repetida entre lojas; suspeitas no_exif / clock_skew / similar.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(91);

select tests.create_base_fixture();
select tests.create_task('t_happy', 'store_p', 'sector_p1', 'staff_p1', p_item_photo => true);
select tests.create_task('t_foto', 'store_p', 'sector_p1', 'staff_p1', p_requires_photo => true, p_items => 1);
select tests.create_task('t_nota', 'store_p', 'sector_p1', 'staff_p1', p_requires_note => true, p_items => 1);
select tests.create_task('t_auto', 'store_p', 'sector_p1', 'staff_p1', p_requires_approval => false, p_items => 1);
select tests.create_task('t_reprova', 'store_p', 'sector_p1', 'staff_p1');
select tests.create_task('t_cancel', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.create_task('t_cancel_aberta', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.create_task('t_dup_c', 'store_c', 'sector_c1', 'staff_c1', p_items => 1);
select tests.create_task('t_dup_p', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.create_task('t_flags', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.create_task('t_equipe', 'store_p', 'sector_p1', null, p_items => 1);
select tests.create_task('t_atrasada', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);

-- =============================================================================
-- Caminho feliz + idempotência
-- =============================================================================
select tests.authenticate_as('staff_p1');

select ok(public.start_attempt(tests.fx('t_happy'), tests.fx('cm_happy')) is not null,
  'colaborador inicia a tarefa atribuída a ele');
select is(public.start_attempt(tests.fx('t_happy'), tests.fx('cm_happy')), tests.attempt_of('t_happy', 1),
  'start com o mesmo client_mutation_id devolve a mesma tentativa');
select is(public.start_attempt(tests.fx('t_happy'), tests.fx('cm_happy_outro')), tests.attempt_of('t_happy', 1),
  'start com tentativa aberta do próprio colaborador retoma a mesma');
select results_eq(
  $$ select t.status::text, t.attempt_count, (select count(*) from public.task_attempts a where a.task_id = t.id)
     from public.tasks t where t.id = tests.fx('t_happy') $$,
  $$ values ('in_progress'::text, 1::smallint, 1::bigint) $$,
  'tarefa em andamento com exatamente 1 tentativa'
);
select throws_ok($$ select public.start_attempt(gen_random_uuid(), gen_random_uuid()) $$, 'P0001', 'forbidden',
  'tarefa inexistente: forbidden (mesmo erro de tarefa fora do alcance)');

select tests.authenticate_as('staff_p2');
select throws_ok($$ select public.start_attempt(tests.fx('t_happy'), tests.fx('cm_happy')) $$, 'P0001', 'forbidden',
  'outro usuário com o mesmo client_mutation_id do start é recusado');
select throws_ok($$ select public.answer_item(tests.attempt_of('t_happy', 1), tests.fx('t_happy:item1'), true) $$,
  'P0001', 'forbidden', 'só o executor responde os itens');

select tests.authenticate_as('staff_p1');
select lives_ok($$ select public.answer_item(tests.attempt_of('t_happy', 1), tests.fx('t_happy:item1'), true) $$,
  'executor marca o item 1');
select lives_ok($$ select public.answer_item(tests.attempt_of('t_happy', 1), tests.fx('t_happy:item2'), false) $$,
  'executor responde o item 2 desmarcado');
select throws_ok($$ select public.submit_attempt(tests.attempt_of('t_happy', 1)) $$, 'P0001', 'items_incomplete',
  'envio com item desmarcado é recusado');
select lives_ok($$ select public.answer_item(tests.attempt_of('t_happy', 1), tests.fx('t_happy:item2'), true, 'conferido') $$,
  'executor marca o item 2 (upsert da resposta)');
select is((select count(*) from public.attempt_item_answers where attempt_id = tests.attempt_of('t_happy', 1)), 2::bigint,
  'uma resposta por item (sem duplicar)');
select throws_ok($$ select public.submit_attempt(tests.attempt_of('t_happy', 1)) $$, 'P0001', 'photo_required',
  'item com foto obrigatória sem foto: envio recusado');
select throws_ok($$ select public.answer_item(tests.attempt_of('t_happy', 1), tests.fx('t_foto:item1'), true) $$,
  'P0001', 'invalid_item', 'item de outra tarefa: invalid_item');
select throws_ok(
  $$ select public.register_evidence(tests.attempt_of('t_happy', 1), tests.fx('t_foto:item1'),
       tests.evidence_path('t_happy', 1, 'f_item_errado'), now(), null, null, null, tests.sha('item errado'), null, 1000, true, null) $$,
  'P0001', 'invalid_item', 'foto de item de outra tarefa: invalid_item'
);

select ok(
  public.register_evidence(
    tests.attempt_of('t_happy', 1), tests.fx('t_happy:item1'), tests.upload_evidence('t_happy', 1, 'f_happy'),
    now(), -23.550520, -46.633308, 8.5, tests.sha('foto happy'), null, 250000, true, tests.fx('cm_ev_happy')
  ) is not null,
  'executor registra a foto do item'
);
select results_eq(
  $$ select received_at_server = now(), suspicion, latitude, storage_path = tests.evidence_path('t_happy', 1, 'f_happy')
     from public.evidences where client_mutation_id = tests.fx('cm_ev_happy') $$,
  $$ values (true, '{}'::text[], -23.550520::numeric, true) $$,
  'evidência com horário do servidor, GPS, caminho exato e sem suspeitas'
);
select is(
  public.register_evidence(
    tests.attempt_of('t_happy', 1), tests.fx('t_happy:item1'), tests.evidence_path('t_happy', 1, 'f_happy_reenvio'),
    now(), null, null, null, tests.sha('foto happy reenvio'), null, 250000, true, tests.fx('cm_ev_happy')
  ),
  (select e.id from public.evidences e where e.client_mutation_id = tests.fx('cm_ev_happy')),
  'reenvio da evidência com o mesmo client_mutation_id devolve a mesma'
);
select is((select count(*) from public.evidences where attempt_id = tests.attempt_of('t_happy', 1)), 1::bigint,
  'reenvio não duplica a evidência');

select throws_ok(
  format(
    $$ select public.register_evidence(tests.attempt_of('t_happy', 1), null, %L, now(), null, null, null, %L, null, 1000, true, null) $$,
    p.path, tests.sha('caminho ' || p.descr)
  ),
  'P0001', 'invalid_path', 'caminho inválido: ' || p.descr
)
from (
  select v.n, v.descr, v.path
  from (
    select tests.evidence_path('t_happy', 1, 'f_caminho') as ok_path,
           tests.attempt_of('t_happy', 1)::text as att
  ) as base
  cross join lateral (
    values
      (1, 'outra organização', replace(base.ok_path, tests.fx('org_a')::text, tests.fx('org_b')::text)),
      (2, 'outra loja', replace(base.ok_path, tests.fx('store_p')::text, tests.fx('store_c')::text)),
      (3, 'outra tentativa', replace(base.ok_path, base.att, gen_random_uuid()::text)),
      (4, 'segmento ..', replace(base.ok_path, '/' || tests.fx('t_happy')::text || '/', '/../')),
      (5, 'segmento a mais', replace(base.ok_path, base.att || '/', base.att || '/extra/')),
      (6, 'segmento a menos', replace(base.ok_path, tests.fx('t_happy')::text || '/', '')),
      (7, 'extensão png', replace(base.ok_path, '.jpg', '.png')),
      (8, 'arquivo sem uuid', regexp_replace(base.ok_path, '[^/]+\.jpg$', 'foto.jpg')),
      (9, 'uuid em maiúsculas', left(base.ok_path, length(base.ok_path) - 40) || upper(left(right(base.ok_path, 40), 36)) || '.jpg')
  ) as v (n, descr, path)
  order by v.n
) as p;                                                                                          -- 9

select tests.authenticate_as('staff_p2');
select throws_ok(
  $$ select public.register_evidence(tests.attempt_of('t_happy', 1), null, tests.evidence_path('t_happy', 1, 'f_outro'),
       now(), null, null, null, tests.sha('outro'), null, 1000, true, tests.fx('cm_ev_happy')) $$,
  'P0001', 'forbidden', 'outro usuário com o mesmo client_mutation_id da evidência é recusado'
);

select tests.authenticate_as('staff_p1');
select is(public.submit_attempt(tests.attempt_of('t_happy', 1), null, tests.fx('cm_sub_happy')), 'submitted'::public.task_status,
  'envio completo: aguardando aprovação');
select is(public.submit_attempt(tests.attempt_of('t_happy', 1), null, tests.fx('cm_sub_happy')), 'submitted'::public.task_status,
  'reenvio do submit devolve o status atual');
select results_eq(
  $$ select count(*), bool_and(submitted_at = now()) from public.task_attempts where task_id = tests.fx('t_happy') $$,
  $$ values (1::bigint, true) $$,
  'reenvio não cria nem altera tentativa'
);
select throws_ok($$ select public.answer_item(tests.attempt_of('t_happy', 1), tests.fx('t_happy:item1'), false) $$,
  'P0001', 'attempt_closed', 'tentativa enviada não aceita resposta');
select throws_ok(
  $$ select public.register_evidence(tests.attempt_of('t_happy', 1), null, tests.evidence_path('t_happy', 1, 'f_tarde'),
       now(), null, null, null, tests.sha('tarde'), null, 1000, true, gen_random_uuid()) $$,
  'P0001', 'attempt_closed', 'tentativa enviada não aceita foto nova'
);
select throws_ok($$ select public.start_attempt(tests.fx('t_happy'), gen_random_uuid()) $$, 'P0001', 'invalid_transition',
  'tarefa aguardando aprovação não é reiniciada');
select throws_ok($$ select public.review_attempt(tests.attempt_of('t_happy', 1), 'approved') $$, 'P0001', 'forbidden',
  'colaborador não revisa');

select tests.authenticate_as('staff_p2');
select throws_ok($$ select public.submit_attempt(tests.attempt_of('t_happy', 1), null, tests.fx('cm_sub_happy')) $$,
  'P0001', 'forbidden', 'outro usuário não reenvia a tentativa de outra pessoa');
select throws_ok($$ select public.submit_attempt(tests.attempt_of('t_happy', 1)) $$,
  'P0001', 'forbidden', 'outro usuário não envia a tentativa de outra pessoa');

select tests.authenticate_as('manager_p');
select is(public.review_attempt(tests.attempt_of('t_happy', 1), 'approved'), 'approved'::public.task_status,
  'gerente aprova');
select results_eq(
  $$ select r.decision::text, r.reviewer_id, r.is_auto, t.status::text
     from public.reviews r join public.tasks t on t.id = r.task_id
     where r.task_id = tests.fx('t_happy') $$,
  $$ values ('approved'::text, tests.fx('manager_p'), false, 'approved'::text) $$,
  'revisão manual registrada e tarefa aprovada'
);
select throws_ok($$ select public.review_attempt(tests.attempt_of('t_happy', 1), 'rejected', 'Depois') $$, 'P0001', 'task_closed',
  'tarefa aprovada não é revisada de novo');

select tests.authenticate_as('staff_p1');
select throws_ok($$ select public.start_attempt(tests.fx('t_happy'), gen_random_uuid()) $$, 'P0001', 'task_closed',
  'tarefa aprovada não é reiniciada');

-- =============================================================================
-- Foto obrigatória na tarefa
-- =============================================================================
select public.start_attempt(tests.fx('t_foto'), tests.fx('cm_foto'));
select public.answer_item(tests.attempt_of('t_foto', 1), tests.fx('t_foto:item1'), true);
select throws_ok($$ select public.submit_attempt(tests.attempt_of('t_foto', 1)) $$, 'P0001', 'photo_required',
  'tarefa com foto obrigatória sem nenhuma foto: envio recusado');
select ok(
  public.register_evidence(tests.attempt_of('t_foto', 1), null, tests.upload_evidence('t_foto', 1, 'f_geral'),
    now(), null, null, null, tests.sha('foto geral'), null, 1000, true, null) is not null,
  'foto geral da tarefa (sem item) registrada'
);
select is(public.submit_attempt(tests.attempt_of('t_foto', 1)), 'submitted'::public.task_status,
  'com a foto da tarefa o envio passa');

-- =============================================================================
-- Observação obrigatória
-- =============================================================================
select public.start_attempt(tests.fx('t_nota'), tests.fx('cm_nota'));
select public.answer_item(tests.attempt_of('t_nota', 1), tests.fx('t_nota:item1'), true);
select throws_ok($$ select public.submit_attempt(tests.attempt_of('t_nota', 1)) $$, 'P0001', 'note_required',
  'observação obrigatória ausente: envio recusado');
select throws_ok($$ select public.submit_attempt(tests.attempt_of('t_nota', 1), '   ') $$, 'P0001', 'note_required',
  'observação em branco não vale');
select is(public.submit_attempt(tests.attempt_of('t_nota', 1), '  Tudo conferido  '), 'submitted'::public.task_status,
  'com observação o envio passa');
select is((select note from public.task_attempts where id = tests.attempt_of('t_nota', 1)), 'Tudo conferido',
  'observação gravada sem espaços nas pontas');

-- =============================================================================
-- Auto-aprovação
-- =============================================================================
select public.start_attempt(tests.fx('t_auto'), tests.fx('cm_auto'));
select public.answer_item(tests.attempt_of('t_auto', 1), tests.fx('t_auto:item1'), true);
select is(public.submit_attempt(tests.attempt_of('t_auto', 1)), 'approved'::public.task_status,
  'sem exigência de aprovação: aprovada no envio');
select results_eq(
  $$ select r.decision::text, r.reviewer_id is null, r.is_auto, t.status::text
     from public.reviews r join public.tasks t on t.id = r.task_id where r.task_id = tests.fx('t_auto') $$,
  $$ values ('approved'::text, true, true, 'approved'::text) $$,
  'auto-aprovação registrada como revisão automática, sem revisor'
);

-- =============================================================================
-- Reprovar -> tentativa 2 -> aprovar
-- =============================================================================
select public.start_attempt(tests.fx('t_reprova'), tests.fx('cm_reprova_1'));
select public.answer_item(tests.attempt_of('t_reprova', 1), tests.fx('t_reprova:item1'), true);
select public.answer_item(tests.attempt_of('t_reprova', 1), tests.fx('t_reprova:item2'), true);
select is(public.submit_attempt(tests.attempt_of('t_reprova', 1)), 'submitted'::public.task_status, 'tentativa 1 enviada');

select tests.authenticate_as('manager_p');
select throws_ok($$ select public.review_attempt(tests.attempt_of('t_reprova', 1), 'rejected') $$, 'P0001', 'reason_required',
  'reprovar sem motivo é impossível');
select throws_ok($$ select public.review_attempt(tests.attempt_of('t_reprova', 1), 'rejected', '   ') $$, 'P0001', 'reason_required',
  'motivo em branco não vale');
select throws_ok(
  $$ select public.review_attempt(tests.attempt_of('t_reprova', 1), 'rejected', 'Foto escura', array[tests.fx('t_happy:item1')]) $$,
  'P0001', 'invalid_item', 'item reprovado precisa ser da tarefa'
);
select throws_ok(
  $$ select public.review_attempt(tests.attempt_of('t_reprova', 1), 'approved', null, array[tests.fx('t_reprova:item1')]) $$,
  'P0001', 'invalid_item', 'itens com problema só podem ser marcados ao reprovar'
);
select is(
  public.review_attempt(tests.attempt_of('t_reprova', 1), 'rejected', 'Gôndola desalinhada', array[tests.fx('t_reprova:item1')]),
  'rejected'::public.task_status,
  'gerente reprova com motivo e item marcado'
);
select is(
  (select count(*) from public.review_item_flags f join public.reviews r on r.id = f.review_id where r.task_id = tests.fx('t_reprova')),
  1::bigint,
  'item reprovado registrado'
);

select tests.reset_role();
select throws_ok(
  $$ insert into public.reviews (attempt_id, task_id, reviewer_id, decision, reason)
     values (tests.attempt_of('t_reprova', 1), tests.fx('t_reprova'), tests.fx('manager_p'), 'rejected', null) $$,
  '23514', null, 'CHECK em reviews: reprovação sem motivo é impossível mesmo direto no banco'
);

select tests.authenticate_as('staff_p1');
select ok(public.start_attempt(tests.fx('t_reprova'), tests.fx('cm_reprova_2')) is not null,
  'depois da reprovação, o colaborador inicia nova tentativa');
select is((select a.attempt_number from public.task_attempts a where a.client_mutation_id = tests.fx('cm_reprova_2')), 2::smallint,
  'a nova tentativa é a nº 2');
select results_eq(
  $$ select status::text, attempt_count from public.tasks where id = tests.fx('t_reprova') $$,
  $$ values ('in_progress'::text, 2::smallint) $$,
  'tarefa volta para em andamento com attempt_count = 2'
);
select public.answer_item(tests.attempt_of('t_reprova', 2), tests.fx('t_reprova:item1'), true);
select public.answer_item(tests.attempt_of('t_reprova', 2), tests.fx('t_reprova:item2'), true);
select is(public.submit_attempt(tests.attempt_of('t_reprova', 2)), 'submitted'::public.task_status, 'tentativa 2 enviada');

select tests.authenticate_as('manager_p');
select throws_ok($$ select public.review_attempt(tests.attempt_of('t_reprova', 1), 'approved') $$, 'P0001', 'invalid_transition',
  'tentativa antiga não é revisada');
select is(public.review_attempt(tests.attempt_of('t_reprova', 2), 'approved'), 'approved'::public.task_status,
  'tentativa 2 aprovada');
select results_eq(
  $$ select a.attempt_number, r.decision::text, r.reason
     from public.task_attempts a join public.reviews r on r.attempt_id = a.id
     where a.task_id = tests.fx('t_reprova') order by a.attempt_number $$,
  $$ values (1::smallint, 'rejected'::text, 'Gôndola desalinhada'::text), (2::smallint, 'approved'::text, null::text) $$,
  'as duas tentativas e as duas revisões ficam no histórico'
);

-- =============================================================================
-- Auto-revisão proibida (gerente que também executa)
-- =============================================================================
select tests.reset_role();
insert into public.memberships (profile_id, organization_id, store_id, sector_id, role, starts_at)
values (tests.fx('manager_p'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'staff', now() - interval '1 day');
-- Responsável precisa ser colaborador ativo da loja (D86): o gerente também tem vínculo de colaborador
select tests.create_task('t_self', 'store_p', 'sector_p1', 'manager_p', p_items => 1);

select tests.authenticate_as('manager_p');
select public.start_attempt(tests.fx('t_self'), null);
select public.answer_item(tests.attempt_of('t_self', 1), tests.fx('t_self:item1'), true);
select is(public.submit_attempt(tests.attempt_of('t_self', 1)), 'submitted'::public.task_status, 'gerente executa e envia a própria tarefa');
select throws_ok($$ select public.review_attempt(tests.attempt_of('t_self', 1), 'approved') $$, 'P0001', 'self_review_forbidden',
  'ninguém revisa a própria tentativa');
select tests.authenticate_as('owner_a');
select is(public.review_attempt(tests.attempt_of('t_self', 1), 'approved'), 'approved'::public.task_status,
  'proprietária revisa a tentativa do gerente');

-- =============================================================================
-- Cancelamento
-- =============================================================================
select tests.authenticate_as('staff_p1');
select throws_ok($$ select public.cancel_task(tests.fx('t_cancel'), 'Não quero') $$, 'P0001', 'forbidden',
  'colaborador não cancela tarefa');
select public.start_attempt(tests.fx('t_cancel_aberta'), tests.fx('cm_cancel_aberta'));

select tests.authenticate_as('manager_p');
select throws_ok($$ select public.cancel_task(tests.fx('t_cancel'), '  ') $$, 'P0001', 'reason_required',
  'cancelar exige motivo');
select lives_ok($$ select public.cancel_task(tests.fx('t_cancel'), 'Produto fora de linha') $$, 'gerente cancela com motivo');
select throws_ok($$ select public.cancel_task(tests.fx('t_cancel'), 'De novo') $$, 'P0001', 'task_closed',
  'tarefa cancelada não é cancelada de novo');
select lives_ok($$ select public.cancel_task(tests.fx('t_cancel_aberta'), 'Mudança de prioridade') $$,
  'gerente cancela tarefa em andamento');

select tests.authenticate_as('staff_p1');
select throws_ok($$ select public.start_attempt(tests.fx('t_cancel'), gen_random_uuid()) $$, 'P0001', 'task_closed',
  'tarefa cancelada não é iniciada');
select throws_ok($$ select public.answer_item(tests.attempt_of('t_cancel_aberta', 1), tests.fx('t_cancel_aberta:item1'), true) $$,
  'P0001', 'task_closed', 'tarefa cancelada durante a execução não aceita respostas (servidor vence)');
select throws_ok($$ select public.submit_attempt(tests.attempt_of('t_cancel_aberta', 1)) $$, 'P0001', 'task_closed',
  'tarefa cancelada durante a execução não aceita envio');

-- =============================================================================
-- Foto repetida entre lojas da mesma organização
-- =============================================================================
select tests.authenticate_as('staff_c1');
select public.start_attempt(tests.fx('t_dup_c'), tests.fx('cm_dup_c'));
select ok(
  public.register_evidence(tests.attempt_of('t_dup_c', 1), null, tests.upload_evidence('t_dup_c', 1, 'f_dup_c'),
    now(), null, null, null, tests.sha('foto repetida'), null, 1000, true, null) is not null,
  'colaborador da loja C registra uma foto'
);

select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('t_dup_p'), tests.fx('cm_dup_p'));
select throws_ok(
  $$ select public.register_evidence(tests.attempt_of('t_dup_p', 1), null, tests.upload_evidence('t_dup_p', 1, 'f_dup_p'),
       now(), null, null, null, tests.sha('foto repetida'), null, 1000, true, null) $$,
  'P0001', 'duplicate_photo', 'mesma foto (sha256) em outra loja da rede é bloqueada'
);
select throws_ok(
  $$ select public.register_evidence(tests.attempt_of('t_dup_p', 1), null, tests.upload_evidence('t_dup_p', 1, 'f_dup_p2'),
       now(), null, null, null, upper(tests.sha('foto repetida')), null, 1000, true, null) $$,
  'P0001', 'duplicate_photo', 'sha256 em maiúsculas também é reconhecido'
);

-- =============================================================================
-- Suspeitas: no_exif, clock_skew, similar
-- =============================================================================
select public.start_attempt(tests.fx('t_flags'), tests.fx('cm_flags'));
select ok(
  public.register_evidence(tests.attempt_of('t_flags', 1), null, tests.upload_evidence('t_flags', 1, 'f_flag1'),
    now() - interval '20 minutes', null, null, null, tests.sha('flag1'), x'0F0F0F0F0F0F0F0F'::bigint, 1000, false, null) is not null,
  'foto sem EXIF e com relógio do aparelho 20 min atrás é aceita'
);
select results_eq(
  $$ select suspicion, similar_to_id from public.evidences where sha256 = tests.sha('flag1') $$,
  $$ values (array['no_exif', 'clock_skew']::text[], null::uuid) $$,
  'suspeitas no_exif e clock_skew marcadas'
);
select ok(
  public.register_evidence(tests.attempt_of('t_flags', 1), null, tests.upload_evidence('t_flags', 1, 'f_flag2'),
    now() - interval '5 minutes', null, null, null, tests.sha('flag2'), x'0F0F0F0F0F0F0F08'::bigint, 1000, true, null) is not null,
  'foto parecida (3 bits de diferença) é aceita'
);
select results_eq(
  $$ select suspicion, similar_to_id = (select e.id from public.evidences e where e.sha256 = tests.sha('flag1'))
     from public.evidences where sha256 = tests.sha('flag2') $$,
  $$ values (array['similar']::text[], true) $$,
  'foto parecida marcada como similar, apontando a original (relógio dentro de 10 min não é suspeito)'
);
select ok(
  public.register_evidence(tests.attempt_of('t_flags', 1), null, tests.upload_evidence('t_flags', 1, 'f_flag3'),
    now(), null, null, null, tests.sha('flag3'), x'7FFFFFFFFFFFFFFF'::bigint, 1000, true, null) is not null,
  'foto diferente é aceita'
);
select results_eq(
  $$ select suspicion, similar_to_id from public.evidences where sha256 = tests.sha('flag3') $$,
  $$ values ('{}'::text[], null::uuid) $$,
  'foto diferente (distância > 10) não é marcada'
);

-- =============================================================================
-- Tarefa de equipe e tarefa atrasada
-- =============================================================================
select ok(public.start_attempt(tests.fx('t_equipe'), tests.fx('cm_equipe')) is not null,
  'colaborador do setor inicia tarefa de equipe');
select tests.authenticate_as('manager_p');
select throws_ok($$ select public.start_attempt(tests.fx('t_equipe'), gen_random_uuid()) $$, 'P0001', 'invalid_transition',
  'outro membro do setor não inicia tarefa de equipe já em execução');

select tests.reset_role();
select tests.walk(tests.fx('t_atrasada'), 'overdue');
select tests.authenticate_as('staff_p1');
select ok(public.start_attempt(tests.fx('t_atrasada'), tests.fx('cm_atrasada')) is not null,
  'tarefa atrasada ainda pode ser executada');
select public.answer_item(tests.attempt_of('t_atrasada', 1), tests.fx('t_atrasada:item1'), true);
select tests.reset_role();
select tests.walk(tests.fx('t_atrasada'), 'overdue');
select tests.authenticate_as('staff_p1');
select is(public.start_attempt(tests.fx('t_atrasada'), gen_random_uuid()), tests.attempt_of('t_atrasada', 1),
  'atrasada com tentativa aberta: retoma a mesma tentativa');
select is(public.submit_attempt(tests.attempt_of('t_atrasada', 1)), 'submitted'::public.task_status,
  'tentativa aberta de tarefa atrasada é enviada (overdue -> submitted)');

select * from finish();
rollback;
