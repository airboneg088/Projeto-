-- =============================================================================
-- Máquina de estados da tarefa (docs/modelo-de-dados.md §2).
--
--   pending     -> in_progress | overdue | cancelled
--   in_progress -> submitted   | overdue | cancelled
--   submitted   -> approved    | rejected | cancelled
--   rejected    -> in_progress | cancelled
--   overdue     -> in_progress | submitted | cancelled
--   approved, cancelled: terminais
--
-- O gatilho vale para qualquer papel (inclusive postgres e service_role) e
-- também em session_replication_role = replica (ENABLE ALWAYS):
-- INSERT só com status pending; mudança de status fora do grafo levanta
-- 'invalid_transition' (errcode P0001).
-- Terminal é terminal: tarefa approved ou cancelled não muda mais nenhuma
-- coluna ('task_closed'). Prazo e janela não reescrevem o passado
-- ('deadline_locked'):
--   - tarefa criada pela API (usuário logado) não nasce com prazo vencido;
--   - o prazo só muda com a tarefa pending, in_progress ou rejected, antes de
--     vencer e nunca para o passado;
--   - o início da janela só muda com a tarefa pending, sem tentativas, antes do
--     prazo e nunca para o passado.
-- Reatribuir depois do prazo continua permitido, mas o responsável no prazo
-- fica gravado (assignee_at_due) para a falha não mudar de pessoa.
-- Em modo réplica (restauração de dados) o INSERT de linhas históricas passa
-- sem as regras de criação; UPDATE segue todas as regras.
-- =============================================================================

create function private.task_status_transition_allowed(
  p_old public.task_status,
  p_new public.task_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    case p_old
      when 'pending' then p_new in ('in_progress', 'overdue', 'cancelled')
      when 'in_progress' then p_new in ('submitted', 'overdue', 'cancelled')
      when 'submitted' then p_new in ('approved', 'rejected', 'cancelled')
      when 'rejected' then p_new in ('in_progress', 'cancelled')
      when 'overdue' then p_new in ('in_progress', 'submitted', 'cancelled')
      else false
    end,
    false
  )
$$;

comment on function private.task_status_transition_allowed(public.task_status, public.task_status) is
  'Verdadeiro se a transição de status da tarefa está no grafo. Permanecer no mesmo status não é transição (falso).';

revoke all on function private.task_status_transition_allowed(public.task_status, public.task_status) from public, anon;

create function private.enforce_task_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    -- Restauração de dados (modo réplica): a linha histórica entra como está
    if current_setting('session_replication_role') = 'replica' then
      return new;
    end if;
    if new.status is distinct from 'pending' then
      raise exception 'invalid_transition'
        using errcode = 'P0001',
              detail = format('Tarefa nova precisa começar como pending (recebido: %s).', new.status);
    end if;
    -- Pela API, tarefa não nasce vencida (não infla um período já fechado)
    if auth.uid() is not null and new.due_at <= now() then
      raise exception 'deadline_locked'
        using errcode = 'P0001',
              detail = 'O prazo de uma tarefa nova precisa estar no futuro.';
    end if;
    new.assignee_at_due := null;
    new.assignee_at_due_recorded := false;
    return new;
  end if;

  -- Colunas do sistema: não são gravadas direto
  new.assignee_at_due := old.assignee_at_due;
  new.assignee_at_due_recorded := old.assignee_at_due_recorded;

  if new.status is distinct from old.status then
    if not private.task_status_transition_allowed(old.status, new.status) then
      raise exception 'invalid_transition'
        using errcode = 'P0001',
              detail = format('Transição %s -> %s não é permitida.', old.status, new.status);
    end if;
  elsif old.status in ('approved', 'cancelled')
        and (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    raise exception 'task_closed'
      using errcode = 'P0001',
            detail = 'Tarefa aprovada ou cancelada não pode ser alterada.';
  end if;

  if new.due_at is distinct from old.due_at
     and (old.status not in ('pending', 'in_progress', 'rejected')
          or old.due_at <= now()
          or new.due_at <= now()) then
    raise exception 'deadline_locked'
      using errcode = 'P0001',
            detail = 'O prazo só muda antes de vencer, com a tarefa pendente, em andamento ou com correção solicitada, e nunca para o passado.';
  end if;

  -- Início da janela: muda só antes de qualquer execução e nunca para o passado (nulo =
  -- aberta desde a criação, que já passou). Assim "atribuição -> envio" não é encurtado
  -- e nenhuma tentativa fica com início antes da janela.
  if new.window_start_at is distinct from old.window_start_at
     and (old.status <> 'pending'
          or old.attempt_count > 0
          or old.due_at <= now()
          or coalesce(new.window_start_at, new.created_at) < now()) then
    raise exception 'deadline_locked'
      using errcode = 'P0001',
            detail = 'O início da janela só muda com a tarefa pendente e sem tentativas, antes do prazo, e nunca para o passado.';
  end if;

  -- Reatribuição depois do prazo: guarda quem era o responsável quando o prazo venceu
  if new.assignee_id is distinct from old.assignee_id
     and old.due_at <= now()
     and not old.assignee_at_due_recorded then
    new.assignee_at_due := old.assignee_id;
    new.assignee_at_due_recorded := true;
  end if;

  if new.status is distinct from old.status and new.status = 'cancelled' then
    new.cancelled_at := coalesce(new.cancelled_at, now());
    new.cancelled_by := coalesce(
      new.cancelled_by,
      (select p.id from public.profiles p where p.id = auth.uid())
    );
  end if;

  return new;
end;
$$;

comment on function private.enforce_task_status() is
  'Gatilho BEFORE INSERT/UPDATE em tasks: INSERT só como pending e, pela API, com prazo no futuro; mudança de status só dentro do grafo; tarefa approved/cancelled não muda mais (task_closed); prazo só muda antes de vencer, em pending/in_progress/rejected e nunca para o passado; início da janela só com a tarefa pending sem tentativas e nunca para o passado (deadline_locked); reatribuição depois do prazo grava o responsável no prazo (assignee_at_due); cancelamento registra quem e quando. Em modo réplica, INSERT passa como está.';

revoke all on function private.enforce_task_status() from public, anon;

create trigger tasks_enforce_status
  before insert or update on public.tasks
  for each row execute function private.enforce_task_status();

-- Vale também em session_replication_role = replica (importação de dados não
-- pula a máquina de estados nem reescreve tarefa fechada)
alter table public.tasks enable always trigger tasks_enforce_status;
