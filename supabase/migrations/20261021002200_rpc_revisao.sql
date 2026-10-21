-- =============================================================================
-- Funções RPC de revisão e cancelamento (gerente da loja ou proprietária).
-- Únicas portas de escrita em reviews e review_item_flags (além da
-- auto-aprovação em submit_attempt). Mesmas regras de erro e a mesma ordem
-- (acesso sem trava -> travas tarefa/tentativa -> estado) das RPCs de execução,
-- mais: reason_required, self_review_forbidden, owner_only.
-- Motivo "em branco" (só espaços, quebras de linha, espaço não separável) não vale.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- review_attempt: aprova ou reprova a última tentativa enviada
-- -----------------------------------------------------------------------------
create function public.review_attempt(
  p_attempt_id uuid,
  p_decision public.review_decision,
  p_reason text default null,
  p_failed_task_item_ids uuid[] default '{}'
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
  v_reason text := private.clean_text(p_reason);
  v_items uuid[] := coalesce(p_failed_task_item_ids, '{}'::uuid[]);
  v_review_id uuid;
  v_status public.task_status;
begin
  if v_uid is null then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- Acesso (sem trava): tentativa de loja em que quem chama é gerente ou proprietária.
  -- Id inexistente e id de outra loja dão o mesmo erro.
  select a.task_id into v_task_id
  from public.task_attempts a
  where a.id = p_attempt_id
    and a.store_id = any (private.current_store_ids('{manager,owner}'::public.membership_role[]));
  if not found then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- Travas: tarefa, depois tentativa
  select * into v_task from public.tasks where id = v_task_id for update;
  select * into v_attempt from public.task_attempts where id = p_attempt_id for update;

  if v_attempt.performed_by = v_uid then
    raise exception 'self_review_forbidden' using errcode = 'P0001';
  end if;

  if v_task.status in ('approved', 'cancelled') then
    raise exception 'task_closed' using errcode = 'P0001';
  end if;

  if p_decision is null
     or v_task.status <> 'submitted'
     or v_attempt.submitted_at is null
     or v_attempt.attempt_number <> (
       select max(a.attempt_number) from public.task_attempts a where a.task_id = v_task.id
     )
     or exists (select 1 from public.reviews r where r.attempt_id = v_attempt.id) then
    raise exception 'invalid_transition' using errcode = 'P0001';
  end if;

  if p_decision = 'rejected' and v_reason is null then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;

  if cardinality(v_items) > 0 then
    -- Itens com problema só fazem sentido numa reprovação
    if p_decision = 'approved' then
      raise exception 'invalid_item' using errcode = 'P0001',
        detail = 'Itens reprovados só podem ser marcados ao reprovar.';
    end if;
    if exists (
      select 1
      from unnest(v_items) as i (item_id)
      where i.item_id is null
         or not exists (
           select 1 from public.task_items ti where ti.id = i.item_id and ti.task_id = v_task.id
         )
    ) then
      raise exception 'invalid_item' using errcode = 'P0001';
    end if;
  end if;

  -- reviewed_at pelo relógio real: a revisão nunca fica antes do envio, mesmo quando a
  -- transação começou antes de o envio ser gravado (D81)
  insert into public.reviews (attempt_id, task_id, reviewer_id, decision, reason, is_auto, reviewed_at)
  values (v_attempt.id, v_task.id, v_uid, p_decision, v_reason, false, clock_timestamp())
  returning id into v_review_id;

  insert into public.review_item_flags (review_id, task_id, task_item_id)
  select distinct v_review_id, v_task.id, i.item_id
  from unnest(v_items) as i (item_id);

  v_status := case p_decision when 'approved' then 'approved'::public.task_status
                              else 'rejected'::public.task_status end;

  update public.tasks set status = v_status where id = v_task.id;

  return v_status;
end;
$$;

comment on function public.review_attempt(uuid, public.review_decision, text, uuid[]) is
  'Gerente da loja (ou proprietária) aprova ou reprova a última tentativa enviada. Reprovação exige motivo e pode marcar itens com problema. Ninguém revisa a própria tentativa.';

-- -----------------------------------------------------------------------------
-- cancel_task: cancela uma tarefa não terminal, com motivo
--   gerente: só tarefa pendente ou em andamento, cujo prazo ainda não venceu e
--            que NUNCA teve tentativa enviada (nem a reiniciada depois de uma
--            reprovação)
--   proprietária: qualquer tarefa não terminal
-- Assim o gerente avaliado não apaga dos indicadores uma falha já registrada
-- (atraso, envio, reprovação) cancelando a tarefa depois.
-- -----------------------------------------------------------------------------
create function public.cancel_task(p_task_id uuid, p_reason text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_task public.tasks%rowtype;
  v_reason text := private.clean_text(p_reason);
begin
  if v_uid is null then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- Acesso (sem trava): id inexistente e id de outra loja dão o mesmo erro
  if not exists (
    select 1 from public.tasks t
    where t.id = p_task_id
      and t.store_id = any (private.current_store_ids('{manager,owner}'::public.membership_role[]))
  ) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  if v_reason is null then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;

  select * into v_task from public.tasks where id = p_task_id for update;

  if v_task.status in ('approved', 'cancelled') then
    raise exception 'task_closed' using errcode = 'P0001';
  end if;

  if not (v_task.store_id = any (private.current_store_ids('{owner}'::public.membership_role[])))
     and (v_task.status not in ('pending', 'in_progress')
          or v_task.due_at <= now()
          or exists (
            select 1 from public.task_attempts a
            where a.task_id = v_task.id and a.submitted_at is not null
          )) then
    raise exception 'owner_only' using errcode = 'P0001',
      detail = 'Tarefa vencida ou que já teve envio (inclusive reprovada e reiniciada) só é cancelada pela proprietária.';
  end if;

  update public.tasks
     set status = 'cancelled',
         cancel_reason = v_reason,
         cancelled_by = v_uid,
         cancelled_at = now()
   where id = p_task_id;
end;
$$;

comment on function public.cancel_task(uuid, text) is
  'Cancela uma tarefa não terminal, com motivo obrigatório: gerente da loja só antes do prazo, com a tarefa pendente ou em andamento e sem nenhuma tentativa enviada; proprietária em qualquer caso (owner_only). Registrado no audit_log (task_cancelled).';

revoke execute on function public.review_attempt(uuid, public.review_decision, text, uuid[]) from public, anon;
revoke execute on function public.cancel_task(uuid, text) from public, anon;
grant execute on function public.review_attempt(uuid, public.review_decision, text, uuid[]) to authenticated;
grant execute on function public.cancel_task(uuid, text) to authenticated;
