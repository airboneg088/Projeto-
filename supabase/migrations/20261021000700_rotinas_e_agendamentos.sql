-- =============================================================================
-- Rotinas (modelos de tarefa), itens do checklist e agendamentos.
-- Editar uma rotina incrementa "version" e nunca altera tarefas já geradas
-- (as tarefas guardam um snapshot; ver migration de tarefas).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- task_templates
-- -----------------------------------------------------------------------------
create table public.task_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  store_id uuid references public.stores (id) on delete restrict,
  title text not null,
  instructions text,
  reference_image_path text,
  default_priority public.task_priority not null default 'normal',
  requires_photo boolean not null default false,
  requires_note boolean not null default false,
  requires_approval boolean not null default true,
  weight smallint not null default 1,
  version integer not null default 1,
  is_active boolean not null default true,
  created_by uuid references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint task_templates_title_not_blank check (btrim(title) <> ''),
  -- Tamanhos limitados: título e instruções vão para o diff do audit_log (append-only)
  constraint task_templates_title_length check (char_length(title) <= 200),
  constraint task_templates_instructions_length check (instructions is null or char_length(instructions) <= 4000),
  constraint task_templates_weight_range check (weight between 1 and 5),
  constraint task_templates_version_positive check (version >= 1),
  constraint task_templates_store_organization_fkey foreign key (store_id, organization_id)
    references public.stores (id, organization_id) on delete restrict
);

alter table public.task_templates enable row level security;

comment on table public.task_templates is
  'Rotina (modelo de tarefa). store_id nulo = rotina da rede, usada por todas as lojas.';
comment on column public.task_templates.store_id is 'Loja dona da rotina. Nulo = rotina da rede.';
comment on column public.task_templates.reference_image_path is
  'Caminho da imagem "como deve ficar" no bucket references: {organization_id}/{store_id ou rede}/{id desta rotina}/{uuid}.{jpg|png|webp} (validado por gatilho; rotina da rede só usa a pasta rede).';
comment on column public.task_templates.requires_photo is 'Exige ao menos uma foto na tentativa (além das fotos exigidas por item).';
comment on column public.task_templates.requires_note is 'Exige observação não vazia no envio.';
comment on column public.task_templates.requires_approval is
  'Exige aprovação do gerente. Falso = auto-aprovada no envio (registrada como revisão automática).';
comment on column public.task_templates.weight is 'Peso/complexidade de 1 a 5, usado na nota ponderada.';
comment on column public.task_templates.version is
  'Versão do modelo. Sobe a cada edição do conteúdo ou dos itens; tarefas guardam a versão do snapshot.';

create trigger task_templates_set_updated_at
  before update on public.task_templates
  for each row execute function private.set_updated_at();

create function private.bump_template_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A versão nunca é gravada direto (nem pela chave secreta): só este gatilho e o
  -- gatilho dos itens (que roda aninhado, pg_trigger_depth() > 1) a incrementam.
  if pg_trigger_depth() > 1 and new.version = old.version + 1 then
    return new;
  end if;

  new.version := old.version;
  if (new.title, new.instructions, new.reference_image_path, new.default_priority,
      new.requires_photo, new.requires_note, new.requires_approval, new.weight)
     is distinct from
     (old.title, old.instructions, old.reference_image_path, old.default_priority,
      old.requires_photo, old.requires_note, old.requires_approval, old.weight)
  then
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;

comment on function private.bump_template_version() is
  'Gatilho BEFORE UPDATE em task_templates: incrementa version quando o conteúdo da rotina muda. A versão não pode ser gravada direto (só sobe de 1 em 1, aqui ou pelo gatilho dos itens).';

revoke all on function private.bump_template_version() from public, anon;

create trigger task_templates_bump_version
  before update on public.task_templates
  for each row execute function private.bump_template_version();

-- -----------------------------------------------------------------------------
-- template_items
-- -----------------------------------------------------------------------------
create table public.template_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.task_templates (id) on delete cascade,
  position smallint not null,
  text text not null,
  is_critical boolean not null default false,
  requires_photo boolean not null default false,
  weight smallint not null default 1,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint template_items_text_not_blank check (btrim(text) <> ''),
  constraint template_items_text_length check (char_length(text) <= 500),
  constraint template_items_position_positive check (position >= 1),
  constraint template_items_weight_range check (weight between 1 and 5),
  -- Deferível para permitir reordenar itens numa única transação
  constraint template_items_template_position_key unique (template_id, position)
    deferrable initially deferred
);

alter table public.template_items enable row level security;

comment on table public.template_items is 'Item do checklist de uma rotina.';
comment on column public.template_items.position is 'Ordem do item no checklist (1, 2, 3...).';
comment on column public.template_items.is_critical is
  'Item crítico (segurança, dinheiro). Reprovação é destacada nos indicadores e alimenta o escalonamento.';
comment on column public.template_items.requires_photo is 'Exige foto específica deste item no envio.';
comment on column public.template_items.weight is 'Peso do item de 1 a 5.';
comment on column public.template_items.is_active is
  'Item ativo entra nas próximas tarefas. Item já usado em tarefa não pode ser apagado (preserva a linhagem das falhas recorrentes): desative.';

create trigger template_items_set_updated_at
  before update on public.template_items
  for each row execute function private.set_updated_at();

create function private.bump_template_version_from_items()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Itens gravados na mesma transação que criou a rotina não contam como edição
  update public.task_templates t
     set version = t.version + 1
   where t.id in (
           select (case when tg_op = 'DELETE' then null else new.template_id end)
           union
           select (case when tg_op = 'INSERT' then null else old.template_id end)
         )
     and t.created_at < now();
  return null;
end;
$$;

comment on function private.bump_template_version_from_items() is
  'Gatilho AFTER em template_items: incluir, alterar ou remover item incrementa a versão da rotina (exceto na transação que criou a rotina).';

revoke all on function private.bump_template_version_from_items() from public, anon;

create trigger template_items_bump_template_version
  after insert or update or delete on public.template_items
  for each row execute function private.bump_template_version_from_items();

-- -----------------------------------------------------------------------------
-- schedules
-- -----------------------------------------------------------------------------
create table public.schedules (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete restrict,
  template_id uuid not null references public.task_templates (id) on delete restrict,
  sector_id uuid not null references public.sectors (id) on delete restrict,
  assignee_id uuid references public.profiles (id) on delete restrict,
  frequency public.schedule_frequency not null default 'daily',
  rule jsonb not null default '{}'::jsonb,
  window_start time not null,
  window_end time not null,
  starts_on date not null default current_date,
  ends_on date,
  is_active boolean not null default true,
  created_by uuid references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedules_window_valid check (window_end > window_start),
  constraint schedules_period_valid check (ends_on is null or ends_on >= starts_on),
  constraint schedules_rule_object check (jsonb_typeof(rule) = 'object'),
  -- Só as chaves da recorrência e tamanho limitado (a regra vai para o diff do audit_log)
  constraint schedules_rule_keys check ((rule - array['weekdays', 'monthdays', 'dates']) = '{}'::jsonb),
  constraint schedules_rule_size check (octet_length(rule::text) <= 4096),
  -- coalesce: CHECK que resulta em NULL passaria; aqui ausência da chave reprova
  constraint schedules_rule_matches_frequency check (
    coalesce(
      case frequency
        when 'daily' then true
        when 'weekly' then jsonb_typeof(rule -> 'weekdays') = 'array' and jsonb_array_length(rule -> 'weekdays') > 0
        when 'monthly' then jsonb_typeof(rule -> 'monthdays') = 'array' and jsonb_array_length(rule -> 'monthdays') > 0
        when 'specific_days' then jsonb_typeof(rule -> 'dates') = 'array' and jsonb_array_length(rule -> 'dates') > 0
      end,
      false
    )
  ),
  constraint schedules_sector_store_fkey foreign key (sector_id, store_id)
    references public.sectors (id, store_id) on delete restrict
);

alter table public.schedules enable row level security;

comment on table public.schedules is
  'Agendamento: gera uma tarefa por dia local da loja a partir de uma rotina, com janela de execução.';
comment on column public.schedules.assignee_id is
  'Responsável fixo (precisa ter vínculo não encerrado na loja do agendamento). Nulo = equipe do setor (qualquer colaborador vigente no setor).';
comment on column public.schedules.rule is
  'Regra da recorrência: {} (diária), {"weekdays":[1..7]} (semanal, ISO 1 = segunda), {"monthdays":[1..31]} (mensal), {"dates":["AAAA-MM-DD"]} (datas específicas).';
comment on column public.schedules.window_start is 'Início da janela, em hora local da loja.';
comment on column public.schedules.window_end is 'Fim da janela em hora local da loja; vira o prazo (due_at) da tarefa.';
comment on column public.schedules.starts_on is 'Primeiro dia local em que o agendamento gera tarefas.';
comment on column public.schedules.ends_on is 'Último dia local (inclusive). Nulo = sem fim.';

create trigger schedules_set_updated_at
  before update on public.schedules
  for each row execute function private.set_updated_at();

create function private.validate_schedule()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_template public.task_templates%rowtype;
  v_store_org uuid;
begin
  -- Pela API, só gerente da loja ou proprietária gravam agendamentos: os demais recebem o
  -- erro da RLS antes de qualquer consulta (não descobrem a loja de uma rotina alheia).
  -- (current_store_ids e raise_rls_violation são criadas em migrations seguintes; o
  -- PL/pgSQL só as resolve na execução.)
  if auth.uid() is not null
     and not (new.store_id = any (private.current_store_ids('{manager,owner}'::public.membership_role[]))) then
    perform private.raise_rls_violation('schedules');
  end if;

  select * into v_template from public.task_templates where id = new.template_id;
  select s.organization_id into v_store_org from public.stores s where s.id = new.store_id;
  if v_template.organization_id is distinct from v_store_org
     or (v_template.store_id is not null and v_template.store_id <> new.store_id) then
    raise exception 'invalid_template'
      using errcode = '23514',
            detail = 'A rotina do agendamento precisa ser da rede ou da mesma loja.';
  end if;
  return new;
end;
$$;

comment on function private.validate_schedule() is
  'Gatilho BEFORE INSERT/UPDATE em schedules: pela API só gerente da loja ou proprietária passam (os demais recebem o erro da RLS antes de qualquer consulta); a rotina precisa ser da mesma organização e ser da rede ou da mesma loja.';

revoke all on function private.validate_schedule() from public, anon;

create trigger schedules_validate
  before insert or update of store_id, template_id on public.schedules
  for each row execute function private.validate_schedule();
