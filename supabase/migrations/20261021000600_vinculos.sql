-- =============================================================================
-- Vínculos (pessoa × organização × loja × papel × setor × período).
-- Transferência entre lojas = encerrar um vínculo (ends_at) e abrir outro.
-- O histórico nunca se perde: vínculos não são apagados pela API.
-- =============================================================================

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete restrict,
  organization_id uuid not null references public.organizations (id) on delete restrict,
  store_id uuid references public.stores (id) on delete restrict,
  sector_id uuid references public.sectors (id) on delete restrict,
  role public.membership_role not null,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- owner e admin são papéis de rede (store_id nulo); gerente e colaborador sempre têm loja.
  -- Owner/admin "de uma loja só" não existe: as funções de acesso tratam esses papéis como
  -- da organização inteira.
  constraint memberships_store_required check ((role in ('owner', 'admin')) = (store_id is null)),
  constraint memberships_sector_requires_store check (sector_id is null or store_id is not null),
  constraint memberships_period_valid check (ends_at is null or ends_at > starts_at),
  -- Loja da mesma organização e setor da mesma loja
  constraint memberships_store_organization_fkey foreign key (store_id, organization_id)
    references public.stores (id, organization_id) on delete restrict,
  constraint memberships_sector_store_fkey foreign key (sector_id, store_id)
    references public.sectors (id, store_id) on delete restrict,
  -- Sem períodos sobrepostos para a mesma pessoa, organização, loja e papel.
  -- Vínculo de rede (store_id nulo) usa um uuid sentinela para também ser comparado.
  -- organization_id entra na chave para que uma organização nunca esbarre (nem
  -- descubra pelo erro) em vínculos de outra.
  constraint memberships_no_overlap exclude using gist (
    profile_id with =,
    organization_id with =,
    (coalesce(store_id, '00000000-0000-0000-0000-000000000000'::uuid)) with =,
    role with =,
    tstzrange(starts_at, ends_at) with &&
  )
);

alter table public.memberships enable row level security;

comment on table public.memberships is
  'Vínculo de uma pessoa com a rede ou uma loja, com papel, setor e período. Transferência = encerrar um e abrir outro.';
comment on column public.memberships.store_id is
  'Loja do vínculo. Nulo = vínculo de rede, obrigatório para owner e admin (valem para todas as lojas); gerente e colaborador sempre têm loja.';
comment on column public.memberships.profile_id is
  'Pessoa do vínculo. Cada pessoa pertence a uma única organização (gatilho memberships_single_organization).';
comment on column public.memberships.sector_id is 'Setor do colaborador na loja; define as tarefas de equipe que ele vê e executa.';
comment on column public.memberships.starts_at is 'Início da vigência (inclusive).';
comment on column public.memberships.ends_at is 'Fim da vigência (exclusivo). Nulo = vigente. O acesso termina no instante do fim.';

create trigger memberships_set_updated_at
  before update on public.memberships
  for each row execute function private.set_updated_at();
