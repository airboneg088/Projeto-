-- =============================================================================
-- Funções RPC de execução (colaborador). Únicas portas de escrita em
-- task_attempts, attempt_item_answers e evidences.
--
-- Todas: SECURITY DEFINER, search_path vazio, conferem auth.uid(), papel e
-- loja e levantam erros com errcode P0001 e mensagem estável (chave para a
-- interface traduzir):
--   forbidden, invalid_transition, items_incomplete, photo_required,
--   note_required, duplicate_photo, attempt_closed, task_closed, invalid_path,
--   invalid_item, file_missing, window_not_open, photo_before_start.
--
-- Ordem fixa em todas (inclusive nas de revisão):
--   1. acesso, sem trava: id inexistente e id fora do alcance de quem chama
--      dão o mesmo 'forbidden' (não revela o que existe em outra loja ou
--      organização e não trava linha alheia);
--   2. reenvio idempotente (client_mutation_id), só depois do acesso: quem
--      perdeu o vínculo não acompanha mais a tarefa;
--   3. travas: tarefa ANTES da tentativa (SELECT ... FOR UPDATE), sempre na
--      mesma ordem, para não haver deadlock entre envio, foto e resposta;
--   4. regras de estado E o acesso que depende de coluna editável da tarefa
--      (responsável, setor), conferidos de novo depois das travas; o reenvio
--      (client_mutation_id) também é conferido de novo: dois pedidos iguais ao
--      mesmo tempo recebem o mesmo registro.
-- As assinaturas são contrato para as próximas fases.
--
-- Passagem da tarefa (tarefa não fica presa a quem saiu): a tentativa aberta de
-- quem deixou de poder executar a tarefa (reatribuída, saiu da equipe do setor
-- ou perdeu o vínculo com a loja) é encerrada sem envio (abandoned_at, motivo,
-- auditado) e fica no histórico; quem pode executar inicia a tentativa seguinte.
-- Acontece na hora da reatribuição (gatilho em tasks), na hora em que a pessoa muda
-- de setor, tem o vínculo encerrado ou o perfil desativado (gatilhos em memberships
-- e profiles) e, para vínculo com fim agendado, quando outra pessoa inicia a tarefa
-- (start_attempt).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- release_stale_attempt: encerra sem envio a tentativa aberta de quem perdeu a
-- tarefa. Quem chama já travou a tarefa (ordem tarefa -> tentativa).
-- -----------------------------------------------------------------------------
create function private.release_stale_attempt(p_task_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_open public.task_attempts%rowtype;
  v_reason text;
begin
  select * into v_open
  from public.task_attempts a
  where a.task_id = p_task_id
    and a.submitted_at is null
    and a.abandoned_at is null
  order by a.attempt_number desc
  limit 1
  for update;
  if not found then
    return null;
  end if;

  v_reason := private.stale_attempt_reason(p_task_id, v_open.performed_by);
  if v_reason is null then
    return null;
  end if;

  -- Relógio real (clock_timestamp), não o início da transação (now()): uma reatribuição
  -- que começou antes de a tentativa ser iniciada (PATCH em lote que esperou trava, Server
  -- Action com vários comandos) encerra a tentativa em vez de falhar no CHECK
  -- task_attempts_abandoned_after_start (D81). O gatilho de guarda grava o mesmo relógio.
  update public.task_attempts
     set abandoned_at = clock_timestamp(),
         abandoned_reason = v_reason
   where id = v_open.id;
  return v_open.id;
end;
$$;

comment on function private.release_stale_attempt(uuid) is
  'Se a tentativa aberta da tarefa é de quem não pode mais executá-la (private.stale_attempt_reason), encerra-a sem envio (abandoned_at com o relógio real do servidor, abandoned_reason; auditado como attempt_abandoned) e devolve o id dela; senão, nulo. A tentativa fica no histórico. Quem chama precisa ter travado a tarefa.';

revoke all on function private.release_stale_attempt(uuid) from public, anon;

create function private.release_attempt_on_reassign()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.release_stale_attempt(new.id);
  return null;
end;
$$;

comment on function private.release_attempt_on_reassign() is
  'Gatilho AFTER UPDATE do responsável (ou setor) em tasks: a tentativa aberta de quem deixou de ser responsável é encerrada sem envio na hora, para o novo responsável poder executar e a pessoa da tarefa nos indicadores seguir a reatribuição.';

revoke all on function private.release_attempt_on_reassign() from public, anon;

create trigger tasks_release_attempt_on_reassign
  after update of assignee_id, sector_id on public.tasks
  for each row
  when (old.assignee_id is distinct from new.assignee_id or old.sector_id is distinct from new.sector_id)
  execute function private.release_attempt_on_reassign();

-- Mudanças imediatas na pessoa (troca de setor, vínculo encerrado agora ou apagado,
-- perfil desativado): as tentativas abertas que ela não pode mais executar são
-- encerradas na hora (D82), como na reatribuição. Vínculo com fim agendado (ends_at no
-- futuro) não muda nada agora: release_stale_attempt só encerra o que já está "velho".
create function private.release_attempts_of_person()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_task_id uuid;
begin
  -- Ramos separados: o plpgsql só resolve o campo da linha no ramo que executa
  if tg_table_name = 'profiles' then
    v_profile_id := new.id;
  elsif tg_op = 'DELETE' then
    v_profile_id := old.profile_id;
  else
    v_profile_id := new.profile_id;
  end if;

  for v_task_id in
    select distinct a.task_id
    from public.task_attempts a
    where a.performed_by = v_profile_id
      and a.submitted_at is null
      and a.abandoned_at is null
    order by a.task_id
  loop
    -- Mesma ordem de travas das RPCs: tarefa, depois tentativa
    perform 1 from public.tasks t where t.id = v_task_id for update;
    perform private.release_stale_attempt(v_task_id);
  end loop;
  return null;
end;
$$;

comment on function private.release_attempts_of_person() is
  'Gatilho AFTER em memberships (setor, período, remoção) e profiles (desativação): encerra sem envio as tentativas abertas da pessoa em tarefas que ela não pode mais executar (private.release_stale_attempt), na hora da mudança.';

revoke all on function private.release_attempts_of_person() from public, anon;

create trigger memberships_release_attempts
  after update of sector_id, starts_at, ends_at or delete on public.memberships
  for each row execute function private.release_attempts_of_person();

create trigger profiles_release_attempts
  after update of status on public.profiles
  for each row
  when (new.status = 'inactive' and old.status is distinct from new.status)
  execute function private.release_attempts_of_person();

-- -----------------------------------------------------------------------------
-- start_attempt: inicia (ou retoma) a execução de uma tarefa
-- -----------------------------------------------------------------------------
create function public.start_attempt(
  p_task_id uuid,
  p_client_mutation_id uuid,
  p_started_at_device timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_task public.tasks%rowtype;
  v_existing public.task_attempts%rowtype;
  v_open public.task_attempts%rowtype;
  v_number smallint;
  v_attempt_id uuid;
  v_device_start timestamptz;
begin
  if v_uid is null then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- 1. Acesso (sem trava): colaborador vigente na loja da tarefa
  if not exists (
    select 1 from public.tasks t
    where t.id = p_task_id
      and t.store_id = any (private.current_store_ids('{staff}'::public.membership_role[]))
  ) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- 2. Reenvio (offline): o mesmo client_mutation_id devolve a mesma tentativa
  if p_client_mutation_id is not null then
    select * into v_existing from public.task_attempts where client_mutation_id = p_client_mutation_id;
    if found then
      if v_existing.performed_by <> v_uid or v_existing.task_id <> p_task_id then
        raise exception 'forbidden' using errcode = 'P0001',
          detail = 'Este identificador de envio pertence a outra pessoa ou tarefa.';
      end if;
      return v_existing.id;
    end if;
  end if;

  -- Tarefa dele ou da equipe do seu setor
  if not private.can_execute_task(p_task_id) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- 3. Trava
  select * into v_task from public.tasks where id = p_task_id for update;

  -- 4. Acesso de novo: a tarefa pode ter sido reatribuída enquanto este pedido esperava
  --    a trava (quem deixou de ser o responsável não inicia)
  if not private.can_execute_task(p_task_id) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- Reenvio de novo, depois da trava (dois pedidos iguais ao mesmo tempo)
  if p_client_mutation_id is not null then
    select * into v_existing from public.task_attempts where client_mutation_id = p_client_mutation_id;
    if found then
      if v_existing.performed_by <> v_uid or v_existing.task_id <> p_task_id then
        raise exception 'forbidden' using errcode = 'P0001',
          detail = 'Este identificador de envio pertence a outra pessoa ou tarefa.';
      end if;
      return v_existing.id;
    end if;
  end if;

  -- Estado
  if v_task.status in ('approved', 'cancelled') then
    raise exception 'task_closed' using errcode = 'P0001';
  end if;
  if v_task.status = 'submitted' then
    raise exception 'invalid_transition' using errcode = 'P0001',
      detail = 'A tarefa está aguardando aprovação.';
  end if;

  -- Tentativa aberta de quem perdeu a tarefa (reatribuída, saiu da equipe ou da loja):
  -- encerrada sem envio (fica no histórico), e a tarefa fica livre para quem chama
  perform private.release_stale_attempt(p_task_id);

  -- Tentativa aberta (em andamento, ou atrasada com tentativa já iniciada)
  select * into v_open
  from public.task_attempts
  where task_id = p_task_id
    and submitted_at is null
    and abandoned_at is null
  order by attempt_number desc
  limit 1;

  if found then
    if v_open.performed_by = v_uid then
      return v_open.id;
    end if;
    raise exception 'invalid_transition' using errcode = 'P0001',
      detail = 'Outra pessoa já está executando esta tarefa.';
  end if;

  -- Janela = intervalo permitido de execução: antes do início não começa
  if v_task.window_start_at is not null and now() < v_task.window_start_at then
    raise exception 'window_not_open' using errcode = 'P0001',
      detail = 'A janela desta tarefa ainda não abriu.';
  end if;

  select coalesce(max(a.attempt_number), 0) + 1
    into v_number
  from public.task_attempts a
  where a.task_id = p_task_id;

  -- Início pelo aparelho (fila offline, D72): a pessoa abriu a tarefa sem internet e a fila
  -- chegou depois. Limitado pelo servidor: nunca antes da janela (ou da criação da tarefa),
  -- nem antes do fim da tentativa anterior (envio, revisão ou encerramento), nem depois de
  -- agora. Só serve para conferir a foto anterior ao início; started_at continua sendo a
  -- hora do servidor.
  if p_started_at_device is not null then
    v_device_start := least(
      now(),
      greatest(
        p_started_at_device,
        coalesce(v_task.window_start_at, v_task.created_at),
        (select max(greatest(a.submitted_at, a.abandoned_at, r.reviewed_at))
         from public.task_attempts a
         left join public.reviews r on r.attempt_id = a.id
         where a.task_id = p_task_id)
      )
    );
  end if;

  insert into public.task_attempts (
    task_id, store_id, attempt_number, performed_by, client_mutation_id, started_at_device
  )
  values (p_task_id, v_task.store_id, v_number, v_uid, p_client_mutation_id, v_device_start)
  returning id into v_attempt_id;

  update public.tasks
     set status = 'in_progress',
         attempt_count = v_number
   where id = p_task_id;

  return v_attempt_id;
end;
$$;

comment on function public.start_attempt(uuid, uuid, timestamptz) is
  'Colaborador inicia a tarefa (dele ou da equipe do seu setor, conferido de novo depois da trava), só depois de aberta a janela: cria a tentativa N+1 e leva a tarefa a in_progress. Idempotente por client_mutation_id; se já houver tentativa aberta dele, devolve a mesma. Tentativa aberta de quem perdeu a tarefa (reatribuída, fora da equipe ou sem vínculo na loja) é encerrada sem envio antes (fica no histórico); de outra pessoa que ainda pode executá-la, invalid_transition. p_started_at_device: horário do aparelho em que a pessoa abriu a tarefa (fila offline); gravado em started_at_device, limitado entre o início da janela (ou a criação, ou o fim da tentativa anterior) e agora.';

-- -----------------------------------------------------------------------------
-- answer_item: marca/desmarca um item do checklist (upsert)
--   Offline: o aparelho envia client_mutation_id e o horário da resposta
--   (p_answered_at_device). Reenvio do mesmo id não muda nada; resposta mais
--   antiga que a gravada (fila reordenada, reenvio atrasado) é ignorada e não
--   desfaz uma resposta mais nova. Devolve true se a resposta vale (gravada ou
--   já gravada) e false se foi ignorada por ser mais antiga.
-- -----------------------------------------------------------------------------
create function public.answer_item(
  p_attempt_id uuid,
  p_task_item_id uuid,
  p_checked boolean,
  p_note text default null,
  p_client_mutation_id uuid default null,
  p_answered_at_device timestamptz default null
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_task_id uuid;
  v_task public.tasks%rowtype;
  v_attempt public.task_attempts%rowtype;
  v_existing public.attempt_item_answers%rowtype;
  -- Relógio do aparelho, nunca depois do servidor (um relógio adiantado não "congela" o item)
  v_device_at timestamptz := case when p_answered_at_device is null then null
                                  else least(p_answered_at_device, now()) end;
  v_constraint text;
begin
  if v_uid is null then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- 1. Acesso (sem trava): tentativa do próprio colaborador, com vínculo vigente na loja
  select a.task_id into v_task_id
  from public.task_attempts a
  where a.id = p_attempt_id
    and a.performed_by = v_uid
    and a.store_id = any (private.current_store_ids('{staff}'::public.membership_role[]));
  if not found then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- 2. Reenvio (offline): o mesmo client_mutation_id não muda nada
  if p_client_mutation_id is not null then
    select * into v_existing from public.attempt_item_answers where client_mutation_id = p_client_mutation_id;
    if found then
      if v_existing.attempt_id <> p_attempt_id or v_existing.task_item_id is distinct from p_task_item_id then
        raise exception 'forbidden' using errcode = 'P0001',
          detail = 'Este identificador de envio pertence a outra tentativa ou item.';
      end if;
      return true;
    end if;
  end if;

  -- 3. Travas: tarefa, depois tentativa
  select * into v_task from public.tasks where id = v_task_id for update;
  select * into v_attempt from public.task_attempts where id = p_attempt_id for update;

  -- Reenvio de novo, depois das travas (o mesmo pedido chegando duas vezes ao mesmo tempo)
  if p_client_mutation_id is not null then
    select * into v_existing from public.attempt_item_answers where client_mutation_id = p_client_mutation_id;
    if found then
      if v_existing.attempt_id <> p_attempt_id or v_existing.task_item_id is distinct from p_task_item_id then
        raise exception 'forbidden' using errcode = 'P0001',
          detail = 'Este identificador de envio pertence a outra tentativa ou item.';
      end if;
      return true;
    end if;
  end if;

  -- 4. Acesso de novo: quem deixou de ser o responsável (tarefa reatribuída, fora da
  --    equipe do setor) não responde a tarefa de outra pessoa
  if not private.can_execute_task(v_task.id) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- Resposta mais nova já gravada: um reenvio mais antigo não a desfaz (sem horário do
  -- aparelho, vale a ordem de chegada). Vem antes da conferência de estado: o reenvio
  -- atrasado de uma resposta que já valeu e foi corrigida não muda nada, então devolve
  -- false também com a tentativa já enviada, em vez de virar erro (D88)
  select * into v_existing
  from public.attempt_item_answers
  where attempt_id = p_attempt_id and task_item_id = p_task_item_id;
  if found
     and coalesce(v_device_at, now()) < coalesce(v_existing.answered_at_device, v_existing.answered_at) then
    return false;
  end if;

  -- Estado
  if v_attempt.submitted_at is not null or v_attempt.abandoned_at is not null then
    raise exception 'attempt_closed' using errcode = 'P0001';
  end if;
  if v_task.status in ('approved', 'cancelled') then
    raise exception 'task_closed' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.task_items ti where ti.id = p_task_item_id and ti.task_id = v_task.id
  ) then
    raise exception 'invalid_item' using errcode = 'P0001';
  end if;

  begin
    insert into public.attempt_item_answers (
      attempt_id, task_id, task_item_id, checked, note, answered_at, answered_at_device, client_mutation_id
    )
    values (
      p_attempt_id, v_task.id, p_task_item_id, coalesce(p_checked, false), private.clean_text(p_note), now(),
      v_device_at, p_client_mutation_id
    )
    on conflict (attempt_id, task_item_id) do update
      set checked = excluded.checked,
          note = excluded.note,
          answered_at = excluded.answered_at,
          answered_at_device = excluded.answered_at_device,
          client_mutation_id = excluded.client_mutation_id;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint = 'attempt_item_answers_client_mutation_id_key' then
        raise exception 'forbidden' using errcode = 'P0001',
          detail = 'Este identificador de envio pertence a outra tentativa ou item.';
      end if;
      raise;
  end;

  return true;
end;
$$;

comment on function public.answer_item(uuid, uuid, boolean, text, uuid, timestamptz) is
  'Executor responde um item do checklist na tentativa aberta (grava ou substitui a resposta): marcado = feito; desmarcado com observação = não conforme; desmarcado sem observação = ainda não respondido. Idempotente por client_mutation_id; resposta com horário do aparelho anterior ao da resposta gravada é ignorada (reenvio offline atrasado não desfaz a mais nova). Devolve true se a resposta vale e false se foi ignorada (também depois do envio: o reenvio mais antigo não vira erro). Quem deixou de ser o responsável recebe forbidden.';

-- -----------------------------------------------------------------------------
-- register_evidence: registra a foto já enviada ao bucket evidences
-- -----------------------------------------------------------------------------
create function public.register_evidence(
  p_attempt_id uuid,
  p_task_item_id uuid,
  p_storage_path text,
  p_captured_at_device timestamptz,
  p_latitude numeric,
  p_longitude numeric,
  p_accuracy_m numeric,
  p_sha256 text,
  p_phash bigint,
  p_size_bytes integer,
  p_exif_present boolean,
  p_client_mutation_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_task_id uuid;
  v_attempt public.task_attempts%rowtype;
  v_task public.tasks%rowtype;
  v_existing public.evidences%rowtype;
  v_object_size text;
  v_size integer := p_size_bytes;
  v_prefix text;
  v_sha256 text := lower(btrim(p_sha256));
  v_flags text[] := '{}';
  v_similar_id uuid;
  v_evidence_id uuid;
  v_constraint text;
begin
  if v_uid is null then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- 1. Acesso (sem trava): tentativa do próprio colaborador, com vínculo vigente na loja
  select a.task_id into v_task_id
  from public.task_attempts a
  where a.id = p_attempt_id
    and a.performed_by = v_uid
    and a.store_id = any (private.current_store_ids('{staff}'::public.membership_role[]));
  if not found then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- 2. Reenvio (offline): o mesmo client_mutation_id devolve a mesma evidência
  if p_client_mutation_id is not null then
    select * into v_existing from public.evidences where client_mutation_id = p_client_mutation_id;
    if found then
      if v_existing.attempt_id <> p_attempt_id then
        raise exception 'forbidden' using errcode = 'P0001',
          detail = 'Este identificador de envio pertence a outra pessoa ou tentativa.';
      end if;
      return v_existing.id;
    end if;
  end if;

  -- 3. Travas: tarefa, depois tentativa (mesma ordem de submit_attempt/review_attempt)
  select * into v_task from public.tasks where id = v_task_id for update;
  select * into v_attempt from public.task_attempts where id = p_attempt_id for update;

  -- Reenvio de novo, depois das travas: o mesmo registro chegando duas vezes ao mesmo
  -- tempo (fila offline) devolve a mesma evidência, não 'duplicate_photo'
  if p_client_mutation_id is not null then
    select * into v_existing from public.evidences where client_mutation_id = p_client_mutation_id;
    if found then
      if v_existing.attempt_id <> p_attempt_id then
        raise exception 'forbidden' using errcode = 'P0001',
          detail = 'Este identificador de envio pertence a outra pessoa ou tentativa.';
      end if;
      return v_existing.id;
    end if;
  end if;

  -- 4. Acesso de novo: quem deixou de ser o responsável (tarefa reatribuída, fora da
  --    equipe do setor) não registra foto na tarefa de outra pessoa
  if not private.can_execute_task(v_task.id) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- Estado
  if v_attempt.submitted_at is not null or v_attempt.abandoned_at is not null then
    raise exception 'attempt_closed' using errcode = 'P0001';
  end if;
  if v_task.status in ('approved', 'cancelled') then
    raise exception 'task_closed' using errcode = 'P0001';
  end if;

  -- Foto com EXIF tirada antes do início da tentativa não vale (10 min de tolerância para
  -- o relógio do aparelho, o mesmo limite de clock_skew). O início é o do aparelho quando a
  -- tentativa veio da fila offline (D72: started_at_device, limitado pelo servidor); senão,
  -- o do servidor. Sem EXIF, o horário informado não é confiável: a foto entra com a
  -- suspeita no_exif e o gerente avalia (PDF: "não bloquear sem confirmar comigo").
  if coalesce(p_exif_present, false)
     and p_captured_at_device is not null
     and p_captured_at_device < coalesce(v_attempt.started_at_device, v_attempt.started_at) - interval '10 minutes' then
    raise exception 'photo_before_start' using errcode = 'P0001',
      detail = 'A foto foi tirada antes do início da tarefa. Tire uma foto nova (se continuar, confira a data e a hora do celular).';
  end if;

  if p_task_item_id is not null and not exists (
    select 1 from public.task_items ti where ti.id = p_task_item_id and ti.task_id = v_task.id
  ) then
    raise exception 'invalid_item' using errcode = 'P0001';
  end if;

  -- Caminho exato: {organization_id}/{store_id}/{task_id}/{attempt_id}/{uuid}.jpg
  v_prefix := format('%s/%s/%s/%s/', v_task.organization_id, v_task.store_id, v_task.id, v_attempt.id);
  if p_storage_path is null
     or left(p_storage_path, length(v_prefix)) <> v_prefix
     or substr(p_storage_path, length(v_prefix) + 1)
        !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$' then
    raise exception 'invalid_path' using errcode = 'P0001';
  end if;

  -- O arquivo precisa existir no bucket (enviado pela própria pessoa ou pelo servidor):
  -- "foto obrigatória" só se cumpre com foto de verdade
  select o.metadata ->> 'size' into v_object_size
  from storage.objects o
  where o.bucket_id = 'evidences'
    and o.name = p_storage_path
    and (o.owner_id is null or o.owner_id = v_uid::text);
  if not found then
    raise exception 'file_missing' using errcode = 'P0001',
      detail = 'Envie a foto ao storage antes de registrá-la.';
  end if;
  -- Tamanho informado pelo storage vale mais que o do aparelho
  if v_object_size ~ '^[0-9]{1,9}$' then
    v_size := v_object_size::integer;
  end if;

  -- Foto repetida (mesmo sha256 em qualquer loja da organização) é bloqueada
  if exists (
    select 1 from public.evidences e
    where e.organization_id = v_task.organization_id
      and e.sha256 = v_sha256
  ) then
    raise exception 'duplicate_photo' using errcode = 'P0001';
  end if;

  -- Sinais de suspeita (não bloqueiam; o gerente avalia). Sem horário de captura também
  -- conta como sem EXIF (não há como conferir quando a foto foi tirada).
  if not coalesce(p_exif_present, false) or p_captured_at_device is null then
    v_flags := v_flags || 'no_exif'::text;
  end if;

  if p_captured_at_device is not null
     and abs(extract(epoch from (p_captured_at_device - now()))) > 600 then
    v_flags := v_flags || 'clock_skew'::text;
  end if;

  if p_phash is not null then
    -- Distância de Hamming entre hashes de 64 bits (bit_count existe no PG14+).
    -- Só fotos da mesma loja: o gerente que revisa consegue abrir a foto parecida.
    select e.id into v_similar_id
    from public.evidences e
    where e.store_id = v_task.store_id
      and e.phash is not null
      and e.received_at_server >= now() - interval '90 days'
      and bit_count((e.phash # p_phash)::bit(64)) <= 10
    order by bit_count((e.phash # p_phash)::bit(64)), e.received_at_server desc, e.id
    limit 1;

    if v_similar_id is not null then
      v_flags := v_flags || 'similar'::text;
    end if;
  end if;

  begin
    insert into public.evidences (
      organization_id, store_id, task_id, attempt_id, task_item_id, storage_path,
      captured_at_device, received_at_server, latitude, longitude, accuracy_m,
      sha256, phash, size_bytes, suspicion, similar_to_id, client_mutation_id
    )
    values (
      v_task.organization_id, v_task.store_id, v_task.id, v_attempt.id, p_task_item_id, p_storage_path,
      p_captured_at_device, now(), p_latitude, p_longitude, p_accuracy_m,
      v_sha256, p_phash, v_size, v_flags, v_similar_id, p_client_mutation_id
    )
    returning id into v_evidence_id;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      -- O mesmo registro (client_mutation_id) gravado por outro pedido: devolve o existente
      if v_constraint = 'evidences_client_mutation_id_key' then
        select * into v_existing from public.evidences where client_mutation_id = p_client_mutation_id;
        if found and v_existing.attempt_id = p_attempt_id then
          return v_existing.id;
        end if;
        raise exception 'forbidden' using errcode = 'P0001',
          detail = 'Este identificador de envio pertence a outra pessoa ou tentativa.';
      end if;
      -- Corrida com outro envio da mesma foto
      if exists (
        select 1 from public.evidences e
        where e.organization_id = v_task.organization_id and e.sha256 = v_sha256
      ) then
        raise exception 'duplicate_photo' using errcode = 'P0001';
      end if;
      raise;
  end;

  return v_evidence_id;
end;
$$;

comment on function public.register_evidence(uuid, uuid, text, timestamptz, numeric, numeric, numeric, text, bigint, integer, boolean, uuid) is
  'Executor registra uma foto da tentativa aberta. Exige o arquivo no bucket evidences no caminho exato da tentativa (file_missing), recusa foto com EXIF tirada antes do início da tentativa (photo_before_start, 10 min de tolerância), bloqueia sha256 repetido na organização e marca suspeitas (no_exif, clock_skew, similar na mesma loja). received_at_server = horário do servidor. Idempotente por client_mutation_id, inclusive com o mesmo pedido chegando duas vezes ao mesmo tempo.';

-- -----------------------------------------------------------------------------
-- submit_attempt: envia a tentativa
-- -----------------------------------------------------------------------------
create function public.submit_attempt(
  p_attempt_id uuid,
  p_note text default null,
  p_client_mutation_id uuid default null
)
returns public.task_status
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_task_id uuid;
  v_task public.tasks%rowtype;
  v_attempt public.task_attempts%rowtype;
  v_other public.task_attempts%rowtype;
  v_note text;
  v_status public.task_status;
  v_nonconforming boolean;
begin
  if v_uid is null then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- 1. Acesso (sem trava): tentativa do próprio colaborador, com vínculo vigente na loja.
  --    Vem antes do reenvio: quem perdeu o vínculo não acompanha mais a tarefa.
  select a.task_id into v_task_id
  from public.task_attempts a
  where a.id = p_attempt_id
    and a.performed_by = v_uid
    and a.store_id = any (private.current_store_ids('{staff}'::public.membership_role[]));
  if not found then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  if p_client_mutation_id is not null then
    select * into v_other from public.task_attempts where submit_client_mutation_id = p_client_mutation_id;
    if found and v_other.id <> p_attempt_id then
      raise exception 'forbidden' using errcode = 'P0001',
        detail = 'Este identificador de envio pertence a outra pessoa ou tentativa.';
    end if;
  end if;

  -- 3. Travas: tarefa, depois tentativa
  select * into v_task from public.tasks where id = v_task_id for update;
  select * into v_attempt from public.task_attempts where id = p_attempt_id for update;

  -- 2. Reenvio: tentativa já enviada não muda nada. Quem ainda executa a tarefa recebe o
  --    status atual (a fila offline fica idempotente); quem não executa mais (tarefa
  --    reatribuída, mudou de setor) só fica sabendo do resultado da PRÓPRIA tentativa, não do
  --    que aconteceu depois com uma tarefa que já não lê (D83)
  if v_attempt.submitted_at is not null then
    if private.can_execute_task(v_task.id) then
      return v_task.status;
    end if;
    return coalesce(
      (select case r.decision when 'approved' then 'approved'::public.task_status
                              else 'rejected'::public.task_status end
       from public.reviews r
       where r.attempt_id = v_attempt.id),
      'submitted'::public.task_status
    );
  end if;

  -- 4. Acesso de novo: quem deixou de ser o responsável (tarefa reatribuída, fora da
  --    equipe do setor) não envia a tarefa de outra pessoa
  if not private.can_execute_task(v_task.id) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- Estado
  if v_attempt.abandoned_at is not null then
    raise exception 'attempt_closed' using errcode = 'P0001';
  end if;
  if v_task.status in ('approved', 'cancelled') then
    raise exception 'task_closed' using errcode = 'P0001';
  end if;
  if v_task.status not in ('in_progress', 'overdue') then
    raise exception 'invalid_transition' using errcode = 'P0001';
  end if;

  -- Todos os itens respondidos: feito (marcado) ou não conforme (desmarcado com observação)
  if exists (
    select 1
    from public.task_items ti
    where ti.task_id = v_task.id
      and not exists (
        select 1 from public.attempt_item_answers ans
        where ans.attempt_id = v_attempt.id
          and ans.task_item_id = ti.id
          and (ans.checked or not private.is_blank(ans.note))
      )
  ) then
    raise exception 'items_incomplete' using errcode = 'P0001';
  end if;

  v_nonconforming := exists (
    select 1 from public.attempt_item_answers ans
    where ans.attempt_id = v_attempt.id and not ans.checked
  );

  -- Fotos: de cada item que exige e, se a tarefa exige, ao menos uma foto geral da
  -- tarefa (sem item) além das fotos de itens
  if exists (
       select 1
       from public.task_items ti
       where ti.task_id = v_task.id
         and ti.requires_photo
         and not exists (
           select 1 from public.evidences e
           where e.attempt_id = v_attempt.id and e.task_item_id = ti.id
         )
     )
     or (v_task.requires_photo
         and not exists (
           select 1 from public.evidences e
           where e.attempt_id = v_attempt.id and e.task_item_id is null
         )) then
    raise exception 'photo_required' using errcode = 'P0001';
  end if;

  -- Observação de verdade (só espaços, quebras de linha ou espaço não separável não valem)
  v_note := coalesce(private.clean_text(p_note), private.clean_text(v_attempt.note));
  if v_task.requires_note and v_note is null then
    raise exception 'note_required' using errcode = 'P0001';
  end if;

  update public.task_attempts
     set submitted_at = now(),
         note = v_note,
         submit_client_mutation_id = coalesce(p_client_mutation_id, submit_client_mutation_id)
   where id = v_attempt.id;

  update public.tasks set status = 'submitted' where id = v_task.id;
  v_status := 'submitted';

  -- Sem exigência de aprovação e sem item não conforme: auto-aprovada na mesma transação.
  -- Com item não conforme, o gerente decide (a tarefa não cumpriu tudo sozinha).
  if not v_task.requires_approval and not v_nonconforming then
    insert into public.reviews (attempt_id, task_id, reviewer_id, decision, reason, is_auto)
    values (v_attempt.id, v_task.id, null, 'approved', null, true);
    update public.tasks set status = 'approved' where id = v_task.id;
    v_status := 'approved';
  end if;

  return v_status;
end;
$$;

comment on function public.submit_attempt(uuid, text, uuid) is
  'Executor envia a tentativa: exige todos os itens respondidos (feito, ou não conforme com observação), fotos exigidas (de cada item que exige e, se a tarefa exige, ao menos uma foto geral da tarefa, sem item) e observação quando requerida. Vai para submitted; sem exigência de aprovação e sem item não conforme, é auto-aprovada (revisão is_auto). Reenvio devolve o status atual para quem ainda executa a tarefa; para quem não executa mais (reatribuída, mudou de setor), só o resultado da própria tentativa (approved, rejected ou submitted). Quem deixou de ser o responsável recebe forbidden num envio novo; tentativa encerrada sem envio, attempt_closed.';

-- -----------------------------------------------------------------------------
-- Privilégios: só usuários logados
-- -----------------------------------------------------------------------------
revoke execute on function public.start_attempt(uuid, uuid, timestamptz) from public, anon;
revoke execute on function public.answer_item(uuid, uuid, boolean, text, uuid, timestamptz) from public, anon;
revoke execute on function public.register_evidence(uuid, uuid, text, timestamptz, numeric, numeric, numeric, text, bigint, integer, boolean, uuid) from public, anon;
revoke execute on function public.submit_attempt(uuid, text, uuid) from public, anon;

grant execute on function public.start_attempt(uuid, uuid, timestamptz) to authenticated;
grant execute on function public.answer_item(uuid, uuid, boolean, text, uuid, timestamptz) to authenticated;
grant execute on function public.register_evidence(uuid, uuid, text, timestamptz, numeric, numeric, numeric, text, bigint, integer, boolean, uuid) to authenticated;
grant execute on function public.submit_attempt(uuid, text, uuid) to authenticated;
