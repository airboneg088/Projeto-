-- =============================================================================
-- Organização (a rede), lojas, configurações por loja e setores.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- organizations
-- -----------------------------------------------------------------------------
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null,
  photo_retention_days smallint not null default 180,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organizations_slug_key unique (slug),
  constraint organizations_name_not_blank check (btrim(name) <> ''),
  constraint organizations_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  -- Tamanhos limitados: os valores vão para o diff do audit_log (append-only)
  constraint organizations_name_length check (char_length(name) <= 100),
  constraint organizations_slug_length check (char_length(slug) <= 63),
  -- Mínimo de 30 dias: a foto precisa durar ao menos até a revisão e o fechamento do mês
  constraint organizations_photo_retention_days_range check (photo_retention_days between 30 and 3650)
);

alter table public.organizations enable row level security;

comment on table public.organizations is 'A rede de lojas (ex.: Éde Utilidades). Raiz do isolamento entre clientes.';
comment on column public.organizations.slug is 'Identificador curto e único, em minúsculas com hífens.';
comment on column public.organizations.photo_retention_days is
  'Dias que as fotos de evidência ficam no storage antes do job de retenção remover o arquivo (padrão 180, mínimo 30). Nenhuma foto é marcada como removida (purged_at) antes desse prazo.';

create trigger organizations_set_updated_at
  before update on public.organizations
  for each row execute function private.set_updated_at();

-- -----------------------------------------------------------------------------
-- stores
-- -----------------------------------------------------------------------------
create table public.stores (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  name text not null,
  address text,
  timezone text not null default 'America/Sao_Paulo',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stores_name_not_blank check (btrim(name) <> ''),
  constraint stores_name_length check (char_length(name) <= 100),
  constraint stores_address_length check (address is null or char_length(address) <= 300),
  constraint stores_timezone_valid check (private.is_valid_timezone(timezone)),
  constraint stores_organization_name_key unique (organization_id, name),
  -- Alvo de FKs compostas que garantem loja e organização coerentes
  constraint stores_id_organization_key unique (id, organization_id)
);

alter table public.stores enable row level security;

comment on table public.stores is 'Loja da rede. Datas locais (dia da tarefa, indicadores) usam o fuso da loja.';
comment on column public.stores.timezone is 'Fuso IANA da loja (padrão America/Sao_Paulo).';
comment on column public.stores.is_active is 'Loja inativa não recebe novas tarefas; o histórico continua visível.';

create trigger stores_set_updated_at
  before update on public.stores
  for each row execute function private.set_updated_at();

-- -----------------------------------------------------------------------------
-- store_settings (1:1 com stores, criada automaticamente)
-- -----------------------------------------------------------------------------
create table public.store_settings (
  store_id uuid primary key references public.stores (id) on delete cascade,
  due_soon_minutes smallint not null default 30,
  awaiting_approval_hours smallint not null default 4,
  escalate_owner_hours smallint not null default 2,
  daily_summary_at time not null default '20:00',
  channels jsonb not null default '{
    "due_soon": ["in_app"],
    "overdue": ["in_app", "email"],
    "correction_requested": ["in_app"],
    "recurring_reminder": ["in_app"],
    "awaiting_approval": ["in_app"],
    "escalation_manager": ["in_app", "email"],
    "escalation_owner": ["in_app", "email"],
    "daily_summary": ["email"],
    "task_cancelled": ["in_app"],
    "sync_conflict": ["in_app"]
  }'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint store_settings_due_soon_minutes_range check (due_soon_minutes between 0 and 1440),
  constraint store_settings_awaiting_approval_hours_range check (awaiting_approval_hours between 1 and 168),
  constraint store_settings_escalate_owner_hours_range check (escalate_owner_hours between 1 and 168),
  constraint store_settings_channels_object check (jsonb_typeof(channels) = 'object'),
  constraint store_settings_channels_size check (octet_length(channels::text) <= 2048)
);

alter table public.store_settings enable row level security;

comment on table public.store_settings is
  'Configurações de notificação por loja. Uma linha por loja, criada automaticamente com os padrões.';
comment on column public.store_settings.due_soon_minutes is 'Minutos antes do prazo para o aviso "vence em breve".';
comment on column public.store_settings.awaiting_approval_hours is
  'Horas com tarefa aguardando aprovação até lembrar o gerente.';
comment on column public.store_settings.escalate_owner_hours is
  'Horas depois de escalar ao gerente uma tarefa crítica não feita até escalar à proprietária.';
comment on column public.store_settings.daily_summary_at is 'Horário local do resumo diário por e-mail.';
comment on column public.store_settings.channels is
  'Canais por tipo de notificação: objeto { tipo: [canal, ...] } com canais in_app e email.';

create trigger store_settings_set_updated_at
  before update on public.store_settings
  for each row execute function private.set_updated_at();

create function private.create_store_settings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.store_settings (store_id) values (new.id) on conflict (store_id) do nothing;
  return null;
end;
$$;

comment on function private.create_store_settings() is
  'Gatilho AFTER INSERT em stores: cria store_settings com os valores padrão.';

revoke all on function private.create_store_settings() from public, anon;

create trigger stores_create_settings
  after insert on public.stores
  for each row execute function private.create_store_settings();

-- -----------------------------------------------------------------------------
-- sectors
-- -----------------------------------------------------------------------------
create table public.sectors (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete restrict,
  name text not null,
  responsible_id uuid references public.profiles (id) on delete restrict,
  sort_order smallint not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sectors_name_not_blank check (btrim(name) <> ''),
  constraint sectors_name_length check (char_length(name) <= 100),
  constraint sectors_store_name_key unique (store_id, name),
  -- Alvo de FKs compostas que garantem setor e loja coerentes
  constraint sectors_id_store_key unique (id, store_id)
);

alter table public.sectors enable row level security;

comment on table public.sectors is 'Setor de uma loja (ex.: Salão de vendas, Estoque, Caixa, Limpeza).';
comment on column public.sectors.responsible_id is 'Pessoa responsável pelo setor (opcional).';
comment on column public.sectors.sort_order is 'Ordem de exibição dentro da loja.';

create trigger sectors_set_updated_at
  before update on public.sectors
  for each row execute function private.set_updated_at();
