-- =============================================================================
-- Storage: buckets privados e policies em storage.objects
-- (docs/modelo-de-dados.md §6 "Storage").
--
--   evidences  {organization_id}/{store_id}/{task_id}/{attempt_id}/{uuid}.jpg
--     INSERT: só o executor de uma tentativa ABERTA de tarefa que ele ainda pode
--             executar, com o caminho exato dela
--     leitura: executor, gerente da loja, proprietária (public.can_read_evidence)
--   references {organization_id}/{store_id ou "rede"}/{template_id}/{uuid}.{jpg|png|webp}
--     INSERT: gerente (sua loja), proprietária ("rede": só proprietária)
--     leitura: proprietária, gerente e colaborador com vínculo vigente na
--             organização ("rede") ou na loja do caminho (public.can_read_reference)
--     Admin não envia nem lê: a imagem e o caminho (id da rotina) são conteúdo
--     de rotina, que o admin só lê por funções auditadas (D15). Ele também não
--     cria nem edita rotinas, então não teria onde usar a imagem.
--   Sem policies de SELECT, UPDATE e DELETE para authenticated (D77): leitura só
--   por signed URL de até 5 min criada NO SERVIDOR com a chave secreta, depois de
--   conferir a regra como o usuário (can_read_evidence / can_read_reference). Com
--   SELECT direto, o próprio usuário assinaria URLs com o prazo que quisesse
--   (storage-js createSignedUrl), válidas depois de o vínculo acabar. Upload sem
--   upsert só precisa de INSERT; a retenção usa a chave secreta.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('evidences', 'evidences', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('references', 'references', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- -----------------------------------------------------------------------------
-- Funções que validam o caminho (todos os segmentos, sem "..", sem sobras)
-- -----------------------------------------------------------------------------
create function private.can_insert_evidence_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
begin
  if p_name is null
     or cardinality(v_parts) <> 5
     or v_parts[1] !~ v_uuid
     or v_parts[2] !~ v_uuid
     or v_parts[3] !~ v_uuid
     or v_parts[4] !~ v_uuid
     or v_parts[5] !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$' then
    return false;
  end if;

  return exists (
    select 1
    from public.task_attempts a
    join public.tasks t on t.id = a.task_id
    where a.id = v_parts[4]::uuid
      and t.id = v_parts[3]::uuid
      and t.store_id = v_parts[2]::uuid
      and t.organization_id = v_parts[1]::uuid
      and a.performed_by = auth.uid()
      and a.submitted_at is null
      and a.abandoned_at is null
      and t.status in ('in_progress', 'overdue')
      and t.store_id = any (private.current_store_ids('{staff}'::public.membership_role[]))
      -- A mesma regra das RPCs: a tarefa ainda é dele ou da equipe do setor dele (quem mudou
      -- de setor ou teve a tarefa reatribuída não envia mais arquivos para ela)
      and private.can_execute_task(t.id)
  );
end;
$$;

comment on function private.can_insert_evidence_object(text) is
  'Verdadeiro se o caminho é exatamente {org}/{loja}/{tarefa}/{tentativa}/{uuid}.jpg de uma tentativa aberta (nem enviada nem encerrada sem envio) do usuário logado, com vínculo vigente na loja e numa tarefa que ele ainda pode executar (private.can_execute_task, a mesma regra das RPCs).';

create function private.can_read_evidence_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
begin
  if p_name is null
     or cardinality(v_parts) <> 5
     or v_parts[1] !~ v_uuid
     or v_parts[2] !~ v_uuid
     or v_parts[3] !~ v_uuid
     or v_parts[4] !~ v_uuid then
    return false;
  end if;

  return exists (
    select 1
    from public.task_attempts a
    join public.tasks t on t.id = a.task_id
    where a.id = v_parts[4]::uuid
      and t.id = v_parts[3]::uuid
      and t.store_id = v_parts[2]::uuid
      and t.organization_id = v_parts[1]::uuid
      and (
        t.store_id = any (private.current_store_ids('{manager,owner}'::public.membership_role[]))
        or (
          a.performed_by = auth.uid()
          and t.store_id = any (private.current_store_ids('{staff}'::public.membership_role[]))
        )
      )
  );
end;
$$;

comment on function private.can_read_evidence_object(text) is
  'Verdadeiro se o usuário logado pode ler a foto: executor da tentativa (com vínculo vigente), gerente da loja ou proprietária.';

create function private.can_insert_reference_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_org uuid := private.current_org_id();
begin
  if p_name is null
     or v_org is null
     or cardinality(v_parts) <> 4
     or v_parts[1] !~ v_uuid
     or v_parts[3] !~ v_uuid
     or v_parts[4] !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
     or v_parts[1]::uuid <> v_org then
    return false;
  end if;

  if v_parts[2] = 'rede' then
    return private.is_owner();
  end if;

  if v_parts[2] !~ v_uuid then
    return false;
  end if;

  return exists (
    select 1
    from public.stores s
    where s.id = v_parts[2]::uuid
      and s.organization_id = v_org
      and s.id = any (private.current_store_ids('{owner,manager}'::public.membership_role[]))
  );
end;
$$;

comment on function private.can_insert_reference_object(text) is
  'Verdadeiro se o usuário logado pode enviar imagem de referência: gerente na sua loja e proprietária (pasta "rede": só proprietária). Admin não envia (D15).';

create function private.can_read_reference_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_org uuid := private.current_org_id();
begin
  if p_name is null
     or v_org is null
     or cardinality(v_parts) <> 4
     or v_parts[1] !~ v_uuid
     or v_parts[1]::uuid <> v_org then
    return false;
  end if;

  if v_parts[2] = 'rede' then
    return private.has_role('{owner,manager,staff}'::public.membership_role[]);
  end if;

  if v_parts[2] !~ v_uuid then
    return false;
  end if;

  return v_parts[2]::uuid = any (
    private.current_store_ids('{owner,manager,staff}'::public.membership_role[])
  );
end;
$$;

comment on function private.can_read_reference_object(text) is
  'Verdadeiro se o usuário logado é proprietária, gerente ou colaborador com vínculo vigente na organização (pasta "rede") ou na loja do caminho. Admin não lê (D15: conteúdo de rotina só por função auditada).';

-- -----------------------------------------------------------------------------
-- Conferência de leitura para o servidor (D77): o servidor chama com o cliente do
-- usuário logado e, se der verdadeiro, cria a signed URL de até 5 min com a chave
-- secreta (src/lib/storage/signed-url.server.ts). O usuário não lê storage.objects.
-- -----------------------------------------------------------------------------
create function public.can_read_evidence(p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and private.can_read_evidence_object(p_path)
$$;

comment on function public.can_read_evidence(text) is
  'Verdadeiro se o usuário logado pode ver a foto de evidência desse caminho (executor da tentativa com vínculo vigente, gerente da loja ou proprietária). O servidor confere antes de criar a signed URL (até 5 min) com a chave secreta; não há leitura direta do bucket.';

create function public.can_read_reference(p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and private.can_read_reference_object(p_path)
$$;

comment on function public.can_read_reference(text) is
  'Verdadeiro se o usuário logado pode ver a imagem de referência desse caminho (proprietária, gerente e colaborador com vínculo vigente na organização ou na loja; admin não). O servidor confere antes de criar a signed URL (até 5 min) com a chave secreta.';

revoke all on function public.can_read_evidence(text) from public, anon;
revoke all on function public.can_read_reference(text) from public, anon;
grant execute on function public.can_read_evidence(text) to authenticated, service_role;
grant execute on function public.can_read_reference(text) to authenticated, service_role;

revoke all on function private.can_insert_evidence_object(text) from public, anon;
revoke all on function private.can_read_evidence_object(text) from public, anon;
revoke all on function private.can_insert_reference_object(text) from public, anon;
revoke all on function private.can_read_reference_object(text) from public, anon;
grant execute on function private.can_insert_evidence_object(text) to authenticated;
grant execute on function private.can_read_evidence_object(text) to authenticated;
grant execute on function private.can_insert_reference_object(text) to authenticated;
grant execute on function private.can_read_reference_object(text) to authenticated;

-- -----------------------------------------------------------------------------
-- Policies em storage.objects
-- -----------------------------------------------------------------------------
create policy evidences_insert_performer on storage.objects
  for insert to authenticated
  with check (bucket_id = 'evidences' and (select private.can_insert_evidence_object(name)));

create policy references_insert_manager on storage.objects
  for insert to authenticated
  with check (bucket_id = 'references' and (select private.can_insert_reference_object(name)));

comment on policy evidences_insert_performer on storage.objects is
  'Foto de evidência: só o executor de uma tentativa aberta envia, no caminho exato dela.';
comment on policy references_insert_manager on storage.objects is
  'Imagem de referência: gerente (sua loja) e proprietária enviam; pasta "rede" só a proprietária.';
