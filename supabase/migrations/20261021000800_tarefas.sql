-- =============================================================================
-- Tarefas (instância concreta, avulsa ou gerada por agendamento) e o snapshot
-- dos itens do checklist. Alterar a rotina depois não altera tarefas criadas.
-- Tarefas não são apagadas: são canceladas com motivo.
-- =============================================================================

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  store_id uuid not null references public.stores (id) on delete restrict,
  sector_id uuid not null references public.sectors (id) on delete restrict,
  schedule_id uuid references public.schedules (id) on delete restrict,
  scheduled_date date,
  template_id uuid references public.task_templates (id) on delete restrict,
  template_version integer,
  title text not null,
  instructions text,
  reference_image_path text,
  priority public.task_priority not null default 'normal',
  requires_photo boolean not null default false,
  requires_note boolean not null default false,
  requires_approval boolean not null default true,
  weight smallint not null default 1,
  assignee_id uuid references public.profiles (id) on delete restrict,
  -- Responsável no prazo: gravado pelo gatilho na 1ª reatribuição depois do prazo
  assignee_at_due uuid references public.profiles (id) on delete restrict,
  assignee_at_due_recorded boolean not null default false,
  window_start_at timestamptz,
  due_at timestamptz not null,
  status public.task_status not null default 'pending',
  attempt_count smallint not null default 0,
  cancel_reason text,
  cancelled_by uuid references public.profiles (id) on delete restrict,
  cancelled_at timestamptz,
  created_by uuid default auth.uid() references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tasks_title_not_blank check (btrim(title) <> ''),
  -- Tamanhos limitados: título, instruções e motivo vão para o diff do audit_log
  constraint tasks_title_length check (char_length(title) <= 200),
  constraint tasks_instructions_length check (instructions is null or char_length(instructions) <= 4000),
  constraint tasks_cancel_reason_length check (cancel_reason is null or char_length(cancel_reason) <= 1000),
  constraint tasks_assignee_at_due_recorded check (assignee_at_due_recorded or assignee_at_due is null),
  constraint tasks_weight_range check (weight between 1 and 5),
  constraint tasks_attempt_count_non_negative check (attempt_count >= 0),
  constraint tasks_window_valid check (window_start_at is null or window_start_at < due_at),
  constraint tasks_schedule_has_date check (schedule_id is null or scheduled_date is not null),
  constraint tasks_template_version_with_template check (template_version is null or template_id is not null),
  -- Motivo de verdade: só espaços, quebras de linha ou espaço não separável não valem
  constraint tasks_cancel_reason_required check (
    status <> 'cancelled' or not private.is_blank(cancel_reason)
  ),
  -- Geração diária idempotente: no máximo uma tarefa por agendamento e dia local
  constraint tasks_schedule_date_key unique (schedule_id, scheduled_date),
  constraint tasks_store_organization_fkey foreign key (store_id, organization_id)
    references public.stores (id, organization_id) on delete restrict,
  constraint tasks_sector_store_fkey foreign key (sector_id, store_id)
    references public.sectors (id, store_id) on delete restrict,
  -- Alvo de FKs compostas (tentativas e evidências da mesma loja)
  constraint tasks_id_store_key unique (id, store_id)
);

alter table public.tasks enable row level security;

comment on table public.tasks is
  'Tarefa concreta com snapshot da rotina (título, instruções, imagem, exigências, peso e itens). Avulsa (schedule_id nulo) ou gerada por agendamento.';
comment on column public.tasks.schedule_id is 'Agendamento que gerou a tarefa. Nulo = tarefa avulsa.';
comment on column public.tasks.scheduled_date is 'Dia local da loja para o qual o agendamento gerou a tarefa (chave de idempotência com schedule_id).';
comment on column public.tasks.template_id is
  'Rotina de origem do snapshot (nulo em tarefa avulsa sem rotina). Precisa ser da mesma organização e da rede ou da mesma loja.';
comment on column public.tasks.template_version is 'Versão da rotina no momento do snapshot.';
comment on column public.tasks.title is 'Snapshot do título da rotina.';
comment on column public.tasks.instructions is 'Snapshot das instruções.';
comment on column public.tasks.reference_image_path is
  'Snapshot do caminho da imagem de referência (bucket references): {organization_id da tarefa}/{loja da tarefa ou rede}/{rotina ou tarefa}/{uuid}.{jpg|png|webp}.';
comment on column public.tasks.requires_photo is 'Snapshot: exige ao menos uma foto na tentativa.';
comment on column public.tasks.requires_note is 'Snapshot: exige observação no envio.';
comment on column public.tasks.requires_approval is 'Snapshot: exige aprovação do gerente (falso = auto-aprovada no envio).';
comment on column public.tasks.weight is 'Snapshot do peso (1 a 5) usado na nota ponderada.';
comment on column public.tasks.assignee_id is
  'Responsável (precisa ter vínculo não encerrado na loja da tarefa). Nulo = equipe do setor (qualquer colaborador vigente no setor pode iniciar).';
comment on column public.tasks.assignee_at_due is
  'Quem era o responsável quando o prazo venceu (nulo = equipe do setor). Gravado pelo sistema na primeira reatribuição feita depois do prazo, para a falha não mudar de pessoa nos indicadores. Só vale quando assignee_at_due_recorded.';
comment on column public.tasks.assignee_at_due_recorded is
  'Verdadeiro quando a tarefa foi reatribuída depois do prazo e assignee_at_due guarda o responsável no prazo. Falso = o responsável no prazo é o atual.';
comment on column public.tasks.window_start_at is
  'Início da janela de execução (antes dele a tarefa não pode ser iniciada). Nulo = janela aberta desde a criação. Só muda com a tarefa pendente e sem tentativas, e nunca para o passado (deadline_locked).';
comment on column public.tasks.due_at is
  'Prazo (fim da janela). Tarefa nova criada pela API não nasce com prazo vencido; o prazo só muda antes de vencer, com a tarefa pendente, em andamento ou com correção solicitada, e nunca para o passado (deadline_locked, auditado).';
comment on column public.tasks.status is
  'Estado na máquina de estados (validada por gatilho). Muda só pelas funções RPC e pelos jobs. Tarefa approved ou cancelled não muda mais nada.';
comment on column public.tasks.attempt_count is 'Quantidade de tentativas iniciadas.';
comment on column public.tasks.cancel_reason is 'Motivo do cancelamento (obrigatório quando cancelled).';
comment on column public.tasks.cancelled_by is 'Quem cancelou.';
comment on column public.tasks.cancelled_at is 'Quando foi cancelada.';
comment on column public.tasks.created_by is 'Quem criou a tarefa. Nulo = gerada pelo sistema.';

create trigger tasks_set_updated_at
  before update on public.tasks
  for each row execute function private.set_updated_at();

-- -----------------------------------------------------------------------------
-- task_items (snapshot dos itens)
-- -----------------------------------------------------------------------------
create table public.task_items (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks (id) on delete restrict,
  -- RESTRICT: item de rotina já usado em tarefa não é apagado (desativa-se), para a
  -- linhagem das falhas recorrentes nunca se perder
  template_item_id uuid references public.template_items (id) on delete restrict,
  position smallint not null,
  text text not null,
  is_critical boolean not null default false,
  requires_photo boolean not null default false,
  weight smallint not null default 1,
  created_at timestamptz not null default now(),
  constraint task_items_text_not_blank check (btrim(text) <> ''),
  constraint task_items_text_length check (char_length(text) <= 500),
  constraint task_items_position_positive check (position >= 1),
  constraint task_items_weight_range check (weight between 1 and 5),
  constraint task_items_task_position_key unique (task_id, position),
  -- Alvo de FKs compostas (evidência do item pertence à mesma tarefa)
  constraint task_items_id_task_key unique (id, task_id)
);

alter table public.task_items enable row level security;

comment on table public.task_items is 'Snapshot de um item do checklist na tarefa (texto, crítico, foto, peso).';
comment on column public.task_items.template_item_id is
  'Item da rotina de origem (linhagem para "falhas recorrentes"). Precisa ser da rotina da tarefa; item usado em tarefa não pode ser apagado da rotina (só desativado).';
