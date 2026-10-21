-- =============================================================================
-- Imutabilidade do histórico (docs/modelo-de-dados.md §5).
-- Gatilhos valem para todos os papéis, inclusive postgres e service_role, e
-- também em session_replication_role = replica (ENABLE ALWAYS: o modo usado em
-- importações não desliga a proteção). Violação levanta 'immutable' (P0001).
--
--   audit_log                    : sem UPDATE/DELETE
--   evidences                    : sem DELETE; UPDATE só purged_at nulo -> agora,
--                                  depois do prazo de retenção da organização
--   reviews, review_item_flags   : sem UPDATE/DELETE
--   task_attempts                : sem DELETE; sem UPDATE depois de enviada ou
--                                  encerrada sem envio (abandoned_at)
--   attempt_item_answers         : congeladas quando a tentativa é enviada ou
--                                  encerrada sem envio
--   tasks                        : sem DELETE (cancela-se com motivo)
--   task_items                   : só mudam com a tarefa pendente e sem
--                                  tentativas ('task_closed')
-- TRUNCATE também é bloqueado nessas tabelas (ignoraria os gatilhos de linha).
-- Em modo réplica (restauração de dados), INSERT de linhas históricas passa.
-- =============================================================================

create function private.forbid_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'immutable'
    using errcode = 'P0001',
          detail = format('%s em %s não é permitido: o histórico é imutável.', tg_op, tg_table_name);
end;
$$;

comment on function private.forbid_change() is
  'Gatilho que sempre levanta ''immutable''. Usado em tabelas de histórico (UPDATE, DELETE e TRUNCATE).';

revoke all on function private.forbid_change() from public, anon;

-- -----------------------------------------------------------------------------
-- evidences: só a retenção pode preencher purged_at (uma vez), depois do prazo
-- -----------------------------------------------------------------------------
create function private.guard_evidence_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_retention_days integer;
begin
  if tg_op = 'DELETE' then
    raise exception 'immutable'
      using errcode = 'P0001', detail = 'Evidências nunca são apagadas.';
  end if;

  if old.purged_at is not null
     or new.purged_at is null
     or (to_jsonb(new) - 'purged_at') is distinct from (to_jsonb(old) - 'purged_at') then
    raise exception 'immutable'
      using errcode = 'P0001',
            detail = 'Evidência só pode receber purged_at (uma vez), pela rotina de retenção.';
  end if;

  -- Só depois do prazo de retenção da organização (nem a chave secreta remove antes)
  select o.photo_retention_days into v_retention_days
  from public.organizations o
  where o.id = old.organization_id;
  if old.received_at_server > now() - make_interval(days => v_retention_days) then
    raise exception 'retention_not_reached'
      using errcode = 'P0001',
            detail = format('A foto só é removida depois de %s dias do recebimento.', v_retention_days);
  end if;

  -- A data da remoção é a do servidor, não a informada
  new.purged_at := now();
  return new;
end;
$$;

comment on function private.guard_evidence_change() is
  'Gatilho em evidences: bloqueia DELETE e qualquer UPDATE que não seja preencher purged_at pela primeira vez; purged_at só depois do prazo de retenção da organização (retention_not_reached) e sempre com o horário do servidor.';

revoke all on function private.guard_evidence_change() from public, anon;

-- -----------------------------------------------------------------------------
-- task_attempts: aberta aceita só envio (submitted_at, note) ou encerramento sem
-- envio (abandoned_at, abandoned_reason); enviada ou encerrada congela
-- -----------------------------------------------------------------------------
create function private.guard_attempt_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'immutable'
      using errcode = 'P0001', detail = 'Tentativas nunca são apagadas.';
  end if;

  if old.submitted_at is not null then
    raise exception 'immutable'
      using errcode = 'P0001', detail = 'Tentativa enviada não pode ser alterada.';
  end if;

  if old.abandoned_at is not null then
    raise exception 'immutable'
      using errcode = 'P0001', detail = 'Tentativa encerrada sem envio não pode ser alterada.';
  end if;

  if (to_jsonb(new) - array['note', 'submitted_at', 'submit_client_mutation_id', 'abandoned_at', 'abandoned_reason'])
     is distinct from
     (to_jsonb(old) - array['note', 'submitted_at', 'submit_client_mutation_id', 'abandoned_at', 'abandoned_reason']) then
    raise exception 'immutable'
      using errcode = 'P0001',
            detail = 'Na tentativa aberta só mudam observação, dados do envio e o encerramento sem envio.';
  end if;

  -- O encerramento sem envio é registrado com o relógio real do servidor (clock_timestamp,
  -- não o início da transação: a tentativa pode ter sido iniciada depois de a transação que
  -- a encerra começar; D81)
  if new.abandoned_at is not null then
    new.abandoned_at := clock_timestamp();
  end if;

  return new;
end;
$$;

comment on function private.guard_attempt_change() is
  'Gatilho em task_attempts: bloqueia DELETE; depois do envio ou do encerramento sem envio bloqueia qualquer UPDATE; antes, só note/submitted_at/submit_client_mutation_id e abandoned_at/abandoned_reason (com o horário do servidor) mudam.';

revoke all on function private.guard_attempt_change() from public, anon;

-- -----------------------------------------------------------------------------
-- attempt_item_answers: congeladas quando a tentativa é enviada
-- -----------------------------------------------------------------------------
create function private.guard_answer_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt_ids uuid[] := '{}';
begin
  -- Restauração de dados (modo réplica): a resposta histórica entra como está
  if tg_op = 'INSERT' and current_setting('session_replication_role') = 'replica' then
    return new;
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    v_attempt_ids := v_attempt_ids || old.attempt_id;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_attempt_ids := v_attempt_ids || new.attempt_id;
  end if;

  if exists (
    select 1
    from public.task_attempts a
    where a.id = any (v_attempt_ids)
      and (a.submitted_at is not null or a.abandoned_at is not null)
  ) then
    raise exception 'immutable'
      using errcode = 'P0001', detail = 'Respostas de tentativa enviada ou encerrada sem envio não podem mudar.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

comment on function private.guard_answer_change() is
  'Gatilho em attempt_item_answers: bloqueia INSERT/UPDATE/DELETE quando a tentativa já foi enviada ou encerrada sem envio.';

revoke all on function private.guard_answer_change() from public, anon;

-- -----------------------------------------------------------------------------
-- task_items: o snapshot dos itens só muda antes de qualquer execução
-- -----------------------------------------------------------------------------
create function private.guard_task_item_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Restauração de dados (modo réplica): o item histórico entra como está
  if tg_op = 'INSERT' and current_setting('session_replication_role') = 'replica' then
    return new;
  end if;

  -- Pela API, quem não pode alterar a tarefa recebe o erro da RLS antes (este gatilho
  -- roda antes do WITH CHECK e não pode revelar a situação de tarefa alheia)
  if tg_op = 'INSERT' and auth.uid() is not null and not private.can_manage_pending_task(new.task_id) then
    perform private.raise_rls_violation('task_items');
  end if;

  if exists (
    select 1
    from public.tasks t
    where t.id in (
            select (case when tg_op = 'DELETE' then null else new.task_id end)
            union
            select (case when tg_op = 'INSERT' then null else old.task_id end)
          )
      and (t.status <> 'pending' or t.attempt_count > 0)
  ) then
    raise exception 'task_closed'
      using errcode = 'P0001',
            detail = 'Os itens da tarefa só mudam com ela pendente e sem tentativas.';
  end if;

  -- Item que veio da rotina não sai da tarefa (snapshot fiel, D75): tirar o item crítico do
  -- fechamento de hoje apagaria a falha dos indicadores. Outro checklist = editar a rotina
  -- (auditado, sobe a versão) ou criar tarefa avulsa.
  if tg_op = 'DELETE' and old.template_item_id is not null then
    raise exception 'invalid_snapshot'
      using errcode = '23514',
            detail = 'Item que veio da rotina não sai da tarefa: edite a rotina ou crie uma tarefa avulsa.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

comment on function private.guard_task_item_change() is
  'Gatilho em task_items: incluir, alterar ou remover item só com a tarefa pending e sem tentativas (task_closed), para qualquer papel: o snapshot de tarefa executada, aprovada ou cancelada não muda. Item com linhagem da rotina (template_item_id) nunca é removido (invalid_snapshot).';

revoke all on function private.guard_task_item_change() from public, anon;

-- -----------------------------------------------------------------------------
-- Gatilhos
-- -----------------------------------------------------------------------------
create trigger audit_log_forbid_change
  before update or delete on public.audit_log
  for each row execute function private.forbid_change();
create trigger audit_log_forbid_truncate
  before truncate on public.audit_log
  for each statement execute function private.forbid_change();

create trigger evidences_guard_change
  before update or delete on public.evidences
  for each row execute function private.guard_evidence_change();
create trigger evidences_forbid_truncate
  before truncate on public.evidences
  for each statement execute function private.forbid_change();

create trigger reviews_forbid_change
  before update or delete on public.reviews
  for each row execute function private.forbid_change();
create trigger reviews_forbid_truncate
  before truncate on public.reviews
  for each statement execute function private.forbid_change();

create trigger review_item_flags_forbid_change
  before update or delete on public.review_item_flags
  for each row execute function private.forbid_change();
create trigger review_item_flags_forbid_truncate
  before truncate on public.review_item_flags
  for each statement execute function private.forbid_change();

create trigger task_attempts_guard_change
  before update or delete on public.task_attempts
  for each row execute function private.guard_attempt_change();
create trigger task_attempts_forbid_truncate
  before truncate on public.task_attempts
  for each statement execute function private.forbid_change();

create trigger attempt_item_answers_guard_change
  before insert or update or delete on public.attempt_item_answers
  for each row execute function private.guard_answer_change();
create trigger attempt_item_answers_forbid_truncate
  before truncate on public.attempt_item_answers
  for each statement execute function private.forbid_change();

create trigger tasks_forbid_delete
  before delete on public.tasks
  for each row execute function private.forbid_change();

create trigger task_items_guard_change
  before insert or update or delete on public.task_items
  for each row execute function private.guard_task_item_change();

-- ENABLE ALWAYS: valem também com session_replication_role = replica
alter table public.audit_log enable always trigger audit_log_forbid_change;
alter table public.audit_log enable always trigger audit_log_forbid_truncate;
alter table public.evidences enable always trigger evidences_guard_change;
alter table public.evidences enable always trigger evidences_forbid_truncate;
alter table public.reviews enable always trigger reviews_forbid_change;
alter table public.reviews enable always trigger reviews_forbid_truncate;
alter table public.review_item_flags enable always trigger review_item_flags_forbid_change;
alter table public.review_item_flags enable always trigger review_item_flags_forbid_truncate;
alter table public.task_attempts enable always trigger task_attempts_guard_change;
alter table public.task_attempts enable always trigger task_attempts_forbid_truncate;
alter table public.attempt_item_answers enable always trigger attempt_item_answers_guard_change;
alter table public.attempt_item_answers enable always trigger attempt_item_answers_forbid_truncate;
alter table public.tasks enable always trigger tasks_forbid_delete;
alter table public.task_items enable always trigger task_items_guard_change;
