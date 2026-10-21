-- =============================================================================
-- Auditoria automática por gatilho.
--
--   memberships, organizations, stores, sectors, store_settings,
--   task_templates, template_items, schedules  -> insert/update/delete
--   profiles  -> só mudança de status            (profile_status_changed)
--   tasks     -> criação por usuário logado         (insert; a geração pelo
--                sistema segue os agendamentos, já auditados)
--                quando vira cancelled            (task_cancelled)
--                e edição de título, instruções, imagem, prioridade,
--                responsável, janela ou prazo     (update)
--   evidences -> só a remoção pela retenção       (evidence_purged)
--   data_requests (pedidos do titular, LGPD) -> insert/update/delete
--
-- actor_id = auth.uid() (nulo quando é o sistema). diff guarda só as colunas
-- que mudaram: { coluna: { "old": ..., "new": ... } } (updated_at ignorada).
-- O audit_log é append-only: valor com mais de 2 KB (em texto) vai resumido
-- ({ truncated, bytes, sha256, prefix de 1024 caracteres }), para a trilha não
-- virar depósito sem limite.
--
-- TRUNCATE ignora os gatilhos por linha: nas tabelas auditadas ele é bloqueado
-- para todos os papéis (gatilho BEFORE TRUNCATE, ENABLE ALWAYS: vale também em
-- session_replication_role = replica).
-- =============================================================================

-- Valor de coluna para o diff: até 2 KB como está; acima disso, resumido
create function private.audit_value(p_value jsonb)
returns jsonb
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p_value is null or octet_length(p_value::text) <= 2048 then p_value
    else jsonb_build_object(
      'truncated', true,
      'bytes', octet_length(p_value::text),
      'sha256', encode(sha256(convert_to(p_value::text, 'UTF8')), 'hex'),
      'prefix', left(p_value::text, 1024)
    )
  end
$$;

comment on function private.audit_value(jsonb) is
  'Valor de coluna para o diff do audit_log: até 2 KB (em texto) fica como está; acima disso vira { truncated, bytes, sha256, prefix (1024 caracteres) }.';

revoke all on function private.audit_value(jsonb) from public, anon;

create function private.audit_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mode text := coalesce(tg_argv[0], 'default');
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else '{}'::jsonb end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else '{}'::jsonb end;
  v_row jsonb;
  v_action text;
  v_diff jsonb;
  v_org uuid;
  v_actor uuid;
begin
  v_row := case when tg_op = 'DELETE' then v_old else v_new end;

  if v_mode = 'task_cancel' then
    if not (tg_op = 'UPDATE' and v_new ->> 'status' = 'cancelled' and v_old ->> 'status' <> 'cancelled') then
      return null;
    end if;
    v_action := 'task_cancelled';
  elsif v_mode = 'evidence_purge' then
    if not (tg_op = 'UPDATE' and v_old ->> 'purged_at' is null and v_new ->> 'purged_at' is not null) then
      return null;
    end if;
    v_action := 'evidence_purged';
  elsif v_mode = 'insert_by_user' then
    -- Criação pela API (usuário logado); a geração pelo sistema não é registrada aqui
    if not (tg_op = 'INSERT' and auth.uid() is not null) then
      return null;
    end if;
    v_action := 'insert';
  elsif v_mode = 'profile_status' then
    if not (tg_op = 'UPDATE' and (v_old ->> 'status') is distinct from (v_new ->> 'status')) then
      return null;
    end if;
    v_action := 'profile_status_changed';
  else
    v_action := lower(tg_op);
  end if;

  select coalesce(
           jsonb_object_agg(
             k.key,
             jsonb_build_object('old', private.audit_value(v_old -> k.key), 'new', private.audit_value(v_new -> k.key))
           ),
           '{}'::jsonb
         )
    into v_diff
  from (select jsonb_object_keys(v_old || v_new) as key) k
  where k.key <> 'updated_at'
    and coalesce(v_old -> k.key, 'null'::jsonb) is distinct from coalesce(v_new -> k.key, 'null'::jsonb);

  -- UPDATE sem mudança real não gera registro
  if tg_op = 'UPDATE' and v_diff = '{}'::jsonb then
    return null;
  end if;

  v_org := case
    when tg_table_name = 'organizations' then (v_row ->> 'id')::uuid
    when v_row ? 'organization_id' then (v_row ->> 'organization_id')::uuid
    when tg_table_name = 'profiles' then (
      select m.organization_id
      from public.memberships m
      where m.profile_id = (v_row ->> 'id')::uuid
      order by m.starts_at desc, m.id
      limit 1
    )
    when v_row ->> 'store_id' is not null then (
      select s.organization_id from public.stores s where s.id = (v_row ->> 'store_id')::uuid
    )
    when v_row ->> 'template_id' is not null then (
      select t.organization_id from public.task_templates t where t.id = (v_row ->> 'template_id')::uuid
    )
  end;
  v_org := coalesce(v_org, private.current_org_id());

  v_actor := (select p.id from public.profiles p where p.id = auth.uid());

  insert into public.audit_log (occurred_at, organization_id, actor_id, action, table_name, record_id, diff)
  values (
    now(),
    v_org,
    v_actor,
    v_action,
    tg_table_name,
    coalesce(v_row ->> 'id', v_row ->> 'store_id'),
    v_diff
  );

  return null;
end;
$$;

comment on function private.audit_row() is
  'Gatilho AFTER de auditoria. Argumento: default (insert/update/delete), insert_by_user (insert só com usuário logado), task_cancel, evidence_purge ou profile_status. Grava em audit_log só as colunas alteradas (valores acima de 2 KB resumidos por private.audit_value).';

revoke all on function private.audit_row() from public, anon;

create trigger organizations_audit
  after insert or update or delete on public.organizations
  for each row execute function private.audit_row('default');

create trigger stores_audit
  after insert or update or delete on public.stores
  for each row execute function private.audit_row('default');

create trigger store_settings_audit
  after insert or update or delete on public.store_settings
  for each row execute function private.audit_row('default');

create trigger sectors_audit
  after insert or update or delete on public.sectors
  for each row execute function private.audit_row('default');

create trigger memberships_audit
  after insert or update or delete on public.memberships
  for each row execute function private.audit_row('default');

create trigger profiles_audit_status
  after update of status on public.profiles
  for each row execute function private.audit_row('profile_status');

create trigger task_templates_audit
  after insert or update or delete on public.task_templates
  for each row execute function private.audit_row('default');

create trigger template_items_audit
  after insert or update or delete on public.template_items
  for each row execute function private.audit_row('default');

create trigger schedules_audit
  after insert or update or delete on public.schedules
  for each row execute function private.audit_row('default');

-- Tarefa criada pela API (gerente/proprietária): fica registrada quem criou e com que prazo
create trigger tasks_audit_insert
  after insert on public.tasks
  for each row execute function private.audit_row('insert_by_user');

create trigger tasks_audit_cancel
  after update of status on public.tasks
  for each row execute function private.audit_row('task_cancel');

-- Edição de dados da tarefa pelo gerente/proprietária (as RPCs não mexem nessas colunas)
create trigger tasks_audit_edit
  after update of title, instructions, reference_image_path, priority, assignee_id, window_start_at, due_at
  on public.tasks
  for each row execute function private.audit_row('default');

create trigger evidences_audit_purge
  after update of purged_at on public.evidences
  for each row execute function private.audit_row('evidence_purge');

-- Pedido do titular (LGPD): abertura, tratamento e conclusão ficam registrados
create trigger data_requests_audit
  after insert or update or delete on public.data_requests
  for each row execute function private.audit_row('default');

-- -----------------------------------------------------------------------------
-- TRUNCATE bloqueado nas tabelas auditadas (sumiria sem registro)
-- -----------------------------------------------------------------------------
create trigger organizations_forbid_truncate
  before truncate on public.organizations
  for each statement execute function private.forbid_change();
create trigger stores_forbid_truncate
  before truncate on public.stores
  for each statement execute function private.forbid_change();
create trigger store_settings_forbid_truncate
  before truncate on public.store_settings
  for each statement execute function private.forbid_change();
create trigger sectors_forbid_truncate
  before truncate on public.sectors
  for each statement execute function private.forbid_change();
create trigger memberships_forbid_truncate
  before truncate on public.memberships
  for each statement execute function private.forbid_change();
create trigger profiles_forbid_truncate
  before truncate on public.profiles
  for each statement execute function private.forbid_change();
create trigger task_templates_forbid_truncate
  before truncate on public.task_templates
  for each statement execute function private.forbid_change();
create trigger template_items_forbid_truncate
  before truncate on public.template_items
  for each statement execute function private.forbid_change();
create trigger schedules_forbid_truncate
  before truncate on public.schedules
  for each statement execute function private.forbid_change();
create trigger tasks_forbid_truncate
  before truncate on public.tasks
  for each statement execute function private.forbid_change();
create trigger task_items_forbid_truncate
  before truncate on public.task_items
  for each statement execute function private.forbid_change();
create trigger data_requests_forbid_truncate
  before truncate on public.data_requests
  for each statement execute function private.forbid_change();

-- ENABLE ALWAYS: valem também com session_replication_role = replica
alter table public.organizations enable always trigger organizations_forbid_truncate;
alter table public.stores enable always trigger stores_forbid_truncate;
alter table public.store_settings enable always trigger store_settings_forbid_truncate;
alter table public.sectors enable always trigger sectors_forbid_truncate;
alter table public.memberships enable always trigger memberships_forbid_truncate;
alter table public.profiles enable always trigger profiles_forbid_truncate;
alter table public.task_templates enable always trigger task_templates_forbid_truncate;
alter table public.template_items enable always trigger template_items_forbid_truncate;
alter table public.schedules enable always trigger schedules_forbid_truncate;
alter table public.tasks enable always trigger tasks_forbid_truncate;
alter table public.task_items enable always trigger task_items_forbid_truncate;
alter table public.data_requests enable always trigger data_requests_forbid_truncate;
