-- =============================================================================
-- 145 · Regressão R3-ISOLAMENTO-01: foto de evidência (e imagem de referência)
-- não é lida direto do storage com o token do próprio usuário (D77). Com SELECT
-- em storage.objects, o storage-api assina a URL com o prazo que o CLIENTE
-- escolhe (createSignedUrl(path, expiresIn)), e o link vale depois de o vínculo
-- acabar. Agora:
--   - nenhuma policy de SELECT em storage.objects (só INSERT);
--   - o servidor confere public.can_read_evidence / can_read_reference como o
--     usuário e cria a signed URL de até 5 min com a chave secreta
--     (src/lib/storage/signed-url.server.ts);
--   - quem perde o vínculo deixa de passar na conferência na hora;
--   - register_evidence (SECURITY DEFINER) continua achando o arquivo.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(9);

select tests.create_base_fixture();
select tests.create_store_activity('p');

select is(
  (select count(*)::int from pg_policies
   where schemaname = 'storage' and tablename = 'objects' and cmd <> 'INSERT'),
  0, 'storage.objects só tem policies de INSERT (nenhum SELECT direto, nem UPDATE/DELETE)');

create temporary table caminho as
select format('%s/%s/%s/%s/%s.jpg', tests.fx('org_a'), tests.fx('store_p'), tests.fx('task_p'), tests.fx('att_p'),
              tests.fx('evfile_p')) as foto,
       format('%s/%s/%s/%s.jpg', tests.fx('org_a'), tests.fx('store_p'), tests.fx('tpl_p'), tests.fx('reffile_p')) as ref;
grant select on caminho to public;

select tests.authenticate_as('manager_p');
select is((select count(*)::int from storage.objects), 0,
  'gerente não lê storage.objects direto (pré-condição para assinar URL com qualquer prazo)');
select ok(public.can_read_evidence((select foto from caminho)) and public.can_read_reference((select ref from caminho)),
  'gerente vigente passa na conferência do servidor (signed URL de até 5 min)');

select tests.authenticate_as('staff_p1');
select is((select count(*)::int from storage.objects), 0, 'executor não lê storage.objects direto');
select ok(public.can_read_evidence((select foto from caminho)), 'executor passa na conferência da própria foto');

-- Vínculo encerrado: a conferência nega na hora (e nenhuma URL longa foi emitida antes)
select tests.reset_role();
update public.memberships set ends_at = now() where id = tests.fx('m_manager_p');
select tests.authenticate_as('manager_p');
select ok(not public.can_read_evidence((select foto from caminho)) and not public.can_read_reference((select ref from caminho)),
  'gerente com vínculo encerrado não passa mais na conferência');

-- Perfil desativado: idem
select tests.reset_role();
update public.profiles set status = 'inactive' where id = tests.fx('staff_p1');
select tests.authenticate_as('staff_p1');
select ok(not public.can_read_evidence((select foto from caminho)), 'executor desativado não passa mais na conferência');

-- O upload continua funcionando só com INSERT e register_evidence continua achando o arquivo
select tests.reset_role();
update public.profiles set status = 'active' where id = tests.fx('staff_p1');
select tests.create_task('up', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('up'), null);
select lives_ok(
  format($$ insert into storage.objects (bucket_id, name, owner_id) values ('evidences', %L, auth.uid()::text) $$,
         tests.evidence_path('up', 1, 'up_foto')),
  'o executor envia a foto (só INSERT, sem upsert)');
select ok(
  public.register_evidence(tests.attempt_of('up', 1), null, tests.evidence_path('up', 1, 'up_foto'), now(),
                           null, null, null, tests.sha('up-foto'), null, 1000, true, null) is not null,
  'register_evidence confere o arquivo como definer, sem SELECT do usuário');

select * from finish();
rollback;
