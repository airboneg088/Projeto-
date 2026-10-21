-- =============================================================================
-- Revisões (aprovação/reprovação de uma tentativa) e itens reprovados.
-- Escrita só pelas funções RPC (review_attempt e auto-aprovação em
-- submit_attempt). Imutáveis depois de gravadas (gatilhos).
-- =============================================================================

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.task_attempts (id) on delete restrict,
  task_id uuid not null references public.tasks (id) on delete restrict,
  reviewer_id uuid references public.profiles (id) on delete restrict,
  decision public.review_decision not null,
  reason text,
  is_auto boolean not null default false,
  reviewed_at timestamptz not null default now(),
  constraint reviews_attempt_id_key unique (attempt_id),
  -- Reprovação exige motivo de verdade (só espaços, quebras de linha ou espaço não
  -- separável não valem)
  constraint reviews_reason_required check (
    decision <> 'rejected' or not private.is_blank(reason)
  ),
  constraint reviews_reason_length check (reason is null or char_length(reason) <= 1000),
  -- Auto-aprovação não tem revisor; revisão manual sempre tem
  constraint reviews_auto_without_reviewer check (is_auto = (reviewer_id is null)),
  constraint reviews_auto_is_approval check (not is_auto or decision = 'approved'),
  constraint reviews_attempt_task_fkey foreign key (attempt_id, task_id)
    references public.task_attempts (id, task_id) on delete restrict,
  -- Alvo de FK composta (item reprovado da mesma tarefa da revisão)
  constraint reviews_id_task_key unique (id, task_id)
);

alter table public.reviews enable row level security;

comment on table public.reviews is
  'Revisão de uma tentativa enviada: aprovada ou reprovada (com motivo). Uma por tentativa. Imutável.';
comment on column public.reviews.task_id is 'Tarefa da tentativa (cópia para consultas e RLS).';
comment on column public.reviews.reviewer_id is 'Quem revisou. Nulo = auto-aprovação (tarefa sem exigência de aprovação).';
comment on column public.reviews.reason is 'Motivo da reprovação (obrigatório quando rejected).';
comment on column public.reviews.is_auto is 'Verdadeiro quando a aprovação foi automática no envio.';
comment on column public.reviews.reviewed_at is 'Horário do servidor na revisão.';

create table public.review_item_flags (
  review_id uuid not null references public.reviews (id) on delete restrict,
  task_id uuid not null references public.tasks (id) on delete restrict,
  task_item_id uuid not null references public.task_items (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint review_item_flags_pkey primary key (review_id, task_item_id),
  -- Revisão e item da MESMA tarefa (nunca item de outra tarefa ou organização)
  constraint review_item_flags_review_task_fkey foreign key (review_id, task_id)
    references public.reviews (id, task_id) on delete restrict,
  constraint review_item_flags_item_task_fkey foreign key (task_item_id, task_id)
    references public.task_items (id, task_id) on delete restrict
);

alter table public.review_item_flags enable row level security;

comment on table public.review_item_flags is
  'Itens marcados com problema numa reprovação. Alimenta "top itens reprovados" e os planos de ação. Imutável.';
comment on column public.review_item_flags.task_id is
  'Tarefa da revisão (cópia para as FKs compostas: o item marcado é da mesma tarefa).';
