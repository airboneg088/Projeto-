-- =============================================================================
-- 099 · Regressão R1-FI-02: register_evidence só aceita foto que existe no
-- bucket evidences, no caminho exato da tentativa, enviada pela própria
-- pessoa (ou pelo servidor, sem dono). "Foto obrigatória" não se cumpre com
-- caminho inventado. O tamanho vem do storage quando ele informa.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(9);

select tests.create_base_fixture();
-- Foto exigida no item (a foto geral da tarefa é outro teste: 133)
select tests.create_task('t_sem_foto', 'store_p', 'sector_p1', 'staff_p1',
                         p_items => 1, p_item_photo => true);

select tests.authenticate_as('staff_p1');
select ok(public.start_attempt(tests.fx('t_sem_foto'), null) is not null, 'colaborador inicia a tarefa');
select public.answer_item(tests.attempt_of('t_sem_foto', 1), tests.fx('t_sem_foto:item1'), true);

select is(
  (select count(*) from storage.objects
    where bucket_id = 'evidences' and name = tests.evidence_path('t_sem_foto', 1, 'arquivo_inexistente')),
  0::bigint,
  'pré-condição: não existe arquivo no storage para o caminho'
);
select throws_ok(
  $$ select public.register_evidence(
       tests.attempt_of('t_sem_foto', 1), tests.fx('t_sem_foto:item1'),
       tests.evidence_path('t_sem_foto', 1, 'arquivo_inexistente'),
       now(), null, null, null, md5(random()::text) || md5(random()::text), null, 1, true, null) $$,
  'P0001', 'file_missing',
  'registrar evidência sem arquivo no storage é recusado'
);
select throws_ok(
  $$ select public.submit_attempt(tests.attempt_of('t_sem_foto', 1)) $$,
  'P0001', 'photo_required',
  'sem foto de verdade, o envio continua exigindo foto'
);

-- Arquivo no caminho certo, mas enviado por outra pessoa (gravado pelo sistema)
select tests.reset_role();
insert into storage.objects (bucket_id, name, owner_id)
values ('evidences', tests.evidence_path('t_sem_foto', 1, 'de_outra_pessoa'), tests.fx('staff_p2')::text);
select tests.authenticate_as('staff_p1');
select throws_ok(
  $$ select public.register_evidence(
       tests.attempt_of('t_sem_foto', 1), tests.fx('t_sem_foto:item1'),
       tests.evidence_path('t_sem_foto', 1, 'de_outra_pessoa'),
       now(), null, null, null, tests.sha('de outra pessoa'), null, 1, true, null) $$,
  'P0001', 'file_missing',
  'arquivo enviado por outra pessoa não vale'
);

-- Arquivo enviado pelo servidor (sem dono), com tamanho informado pelo storage
select tests.reset_role();
insert into storage.objects (bucket_id, name, metadata)
values ('evidences', tests.evidence_path('t_sem_foto', 1, 'do_servidor'), '{"size": 4321, "mimetype": "image/jpeg"}');
select tests.authenticate_as('staff_p1');
select lives_ok(
  $$ select public.register_evidence(
       tests.attempt_of('t_sem_foto', 1), tests.fx('t_sem_foto:item1'),
       tests.evidence_path('t_sem_foto', 1, 'do_servidor'),
       now(), null, null, null, tests.sha('do servidor'), null, 1, true, null) $$,
  'arquivo enviado pelo servidor (sem dono) é aceito'
);
select is(
  (select size_bytes from public.evidences where sha256 = tests.sha('do servidor')),
  4321,
  'tamanho gravado é o do storage, não o informado pelo aparelho'
);
select is(public.submit_attempt(tests.attempt_of('t_sem_foto', 1)), 'submitted'::public.task_status,
  'com a foto de verdade o envio passa');

select tests.reset_role();
select is(
  (select count(*) from public.evidences where attempt_id = tests.attempt_of('t_sem_foto', 1)),
  1::bigint,
  'só a evidência com arquivo foi registrada'
);

select * from finish();
rollback;
