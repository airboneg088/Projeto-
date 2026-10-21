-- =============================================================================
-- Planos de ação: criados quando o mesmo item é reprovado 3 vezes em 30 dias
-- na mesma loja (regra automática na Fase 4).
-- =============================================================================

create table public.action_plans (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete restrict,
  template_item_id uuid not null references public.template_items (id) on delete restrict,
  what text not null,
  owner_id uuid references public.profiles (id) on delete restrict,
  due_on date,
  status public.action_plan_status not null default 'open',
  trigger_count smallint not null default 1,
  created_by uuid references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint action_plans_what_not_blank check (btrim(what) <> ''),
  constraint action_plans_what_length check (char_length(what) <= 1000),
  constraint action_plans_trigger_count_non_negative check (trigger_count >= 0)
);

alter table public.action_plans enable row level security;

comment on table public.action_plans is
  'Plano de ação simples (o quê, quem, até quando, situação) para um item reprovado de forma recorrente numa loja.';
comment on column public.action_plans.template_item_id is 'Item da rotina com falha recorrente.';
comment on column public.action_plans.what is 'O que será feito.';
comment on column public.action_plans.owner_id is 'Responsável pelo plano (quem).';
comment on column public.action_plans.due_on is 'Até quando (data local da loja).';
comment on column public.action_plans.trigger_count is 'Quantas reprovações do item dispararam ou reforçaram o plano.';

-- No máximo um plano aberto por item e loja
create unique index action_plans_open_item_key
  on public.action_plans (store_id, template_item_id)
  where status in ('open', 'in_progress');

create trigger action_plans_set_updated_at
  before update on public.action_plans
  for each row execute function private.set_updated_at();
