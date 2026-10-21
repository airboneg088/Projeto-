-- =============================================================================
-- Solicitações do titular (LGPD): pedir correção ou exportação dos próprios dados.
-- =============================================================================

create table public.data_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  kind public.data_request_kind not null,
  details text not null,
  status text not null default 'open',
  resolution text,
  resolved_by uuid references public.profiles (id) on delete restrict,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint data_requests_details_not_blank check (btrim(details) <> ''),
  constraint data_requests_details_length check (char_length(details) <= 4000),
  constraint data_requests_resolution_length check (resolution is null or char_length(resolution) <= 4000),
  constraint data_requests_status_values check (status in ('open', 'in_progress', 'done', 'rejected')),
  constraint data_requests_resolution_consistent check (
    (status in ('done', 'rejected')) = (resolved_at is not null)
  )
);

alter table public.data_requests enable row level security;

comment on table public.data_requests is 'Pedido do titular (LGPD) de correção ou exportação dos próprios dados, com situação e resolução.';
comment on column public.data_requests.organization_id is 'Organização que trata o pedido.';
comment on column public.data_requests.profile_id is 'Titular que fez o pedido.';
comment on column public.data_requests.details is 'O que a pessoa pediu, nas palavras dela.';
comment on column public.data_requests.status is 'open (aberto), in_progress (em análise), done (atendido) ou rejected (negado, com justificativa).';
comment on column public.data_requests.resolution is 'Resposta registrada ao titular.';
comment on column public.data_requests.resolved_by is
  'Quem concluiu o pedido: gravado pelo sistema com o usuário logado quando a situação vira done/rejected (não é informado pelo cliente).';
comment on column public.data_requests.resolved_at is
  'Quando foi concluído: gravado pelo sistema quando a situação vira done/rejected (obrigatório nesses casos).';

create trigger data_requests_set_updated_at
  before update on public.data_requests
  for each row execute function private.set_updated_at();
