-- =============================================================================
-- Geração de tarefa a partir de uma rotina (snapshot).
-- Usada pelo seed, pelo job diário de agendamentos (Fase 4, pg_cron) e por
-- futuras funções RPC de criação de tarefa. Não é exposta pela API.
--
-- Contrato (não mudar a assinatura sem migration nova):
--   private.instantiate_task(p_template_id, p_store_id, p_sector_id, p_assignee_id,
--     p_window_start_at, p_due_at, p_schedule_id default null,
--     p_scheduled_date default null, p_created_by default null,
--     p_priority default null) returns uuid
-- Para tarefas de agendamento é idempotente: a mesma (schedule_id, scheduled_date)
-- devolve sempre a mesma tarefa, sem duplicar.
-- Responsável sem vínculo na loja (transferido, desligado) não derruba a geração:
-- a tarefa vai para a equipe do setor (assignee nulo), com aviso no log.
-- p_created_by é ignorado: o autor é sempre o usuário logado (nulo = sistema).
-- =============================================================================

create function private.instantiate_task(
  p_template_id uuid,
  p_store_id uuid,
  p_sector_id uuid,
  p_assignee_id uuid,
  p_window_start_at timestamptz,
  p_due_at timestamptz,
  p_schedule_id uuid default null,
  p_scheduled_date date default null,
  p_created_by uuid default null,
  p_priority public.task_priority default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_template public.task_templates%rowtype;
  v_store public.stores%rowtype;
  v_task_id uuid;
  v_assignee_id uuid := p_assignee_id;
begin
  -- FOR SHARE: a versão copiada não muda até o fim da transação
  select * into v_template from public.task_templates where id = p_template_id for share;
  if not found then
    raise exception 'not_found' using errcode = 'P0001', detail = 'Rotina não encontrada.';
  end if;

  select * into v_store from public.stores where id = p_store_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0001', detail = 'Loja não encontrada.';
  end if;

  if v_template.organization_id <> v_store.organization_id
     or (v_template.store_id is not null and v_template.store_id <> p_store_id) then
    raise exception 'forbidden'
      using errcode = 'P0001', detail = 'A rotina não pertence a esta loja nem à rede da loja.';
  end if;

  if (p_schedule_id is null) <> (p_scheduled_date is null) then
    raise exception 'invalid_schedule'
      using errcode = '22023', detail = 'schedule_id e scheduled_date andam juntos.';
  end if;

  if p_schedule_id is not null and not exists (
    select 1
    from public.schedules s
    where s.id = p_schedule_id
      and s.store_id = p_store_id
      and s.template_id = p_template_id
  ) then
    raise exception 'invalid_schedule'
      using errcode = '22023', detail = 'O agendamento não corresponde à loja e à rotina informadas.';
  end if;

  -- Responsável fixo que saiu da loja: a tarefa do dia vai para a equipe do setor
  if v_assignee_id is not null
     and not private.is_member_of(v_assignee_id, v_store.organization_id, p_store_id) then
    raise warning 'instantiate_task: responsável % sem vínculo na loja %; tarefa gerada para a equipe do setor',
      v_assignee_id, p_store_id;
    v_assignee_id := null;
  end if;

  insert into public.tasks (
    organization_id, store_id, sector_id, schedule_id, scheduled_date,
    template_id, template_version, title, instructions, reference_image_path,
    priority, requires_photo, requires_note, requires_approval, weight,
    assignee_id, window_start_at, due_at, status
  )
  values (
    v_store.organization_id, p_store_id, p_sector_id, p_schedule_id, p_scheduled_date,
    v_template.id, v_template.version, v_template.title, v_template.instructions,
    v_template.reference_image_path,
    coalesce(p_priority, v_template.default_priority), v_template.requires_photo,
    v_template.requires_note, v_template.requires_approval, v_template.weight,
    v_assignee_id, p_window_start_at, p_due_at, 'pending'
  )
  on conflict (schedule_id, scheduled_date) do nothing
  returning id into v_task_id;

  if v_task_id is null then
    -- Já gerada para este agendamento e dia: devolve a existente, sem tocar nos itens
    select t.id into v_task_id
    from public.tasks t
    where t.schedule_id = p_schedule_id
      and t.scheduled_date = p_scheduled_date;
    return v_task_id;
  end if;

  -- Só itens ativos, numerados em sequência (1, 2, 3...) na ordem da rotina
  insert into public.task_items (task_id, template_item_id, position, text, is_critical, requires_photo, weight)
  select v_task_id, ti.id, (row_number() over (order by ti.position))::smallint, ti.text, ti.is_critical,
         ti.requires_photo, ti.weight
  from public.template_items ti
  where ti.template_id = p_template_id
    and ti.is_active
  order by ti.position;

  return v_task_id;
end;
$$;

comment on function private.instantiate_task(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid, date, uuid, public.task_priority) is
  'Cria uma tarefa com snapshot da versão atual da rotina (título, instruções, imagem, exigências, peso, versão, prioridade padrão) e copia os itens ativos para task_items. Com agendamento, ON CONFLICT (schedule_id, scheduled_date) devolve a tarefa existente. Responsável sem vínculo na loja vira equipe do setor (aviso no log). p_created_by é ignorado (autor = usuário logado ou sistema).';

revoke all on function private.instantiate_task(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid, date, uuid, public.task_priority) from public, anon, authenticated;
