-- =============================================================================
-- Notificações (in-app e e-mail). Geradas pelo sistema (jobs e funções); a
-- pessoa só lê as próprias e marca como lida.
-- =============================================================================

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete restrict,
  store_id uuid references public.stores (id) on delete restrict,
  task_id uuid references public.tasks (id) on delete restrict,
  type public.notification_type not null,
  channel public.notification_channel not null default 'in_app',
  dedupe_key text not null,
  payload jsonb not null default '{}'::jsonb,
  sent_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_dedupe_key_key unique (dedupe_key),
  constraint notifications_dedupe_key_not_blank check (btrim(dedupe_key) <> ''),
  constraint notifications_payload_object check (jsonb_typeof(payload) = 'object')
);

alter table public.notifications enable row level security;

comment on table public.notifications is 'Notificação para uma pessoa, por canal. A chave de deduplicação impede envio repetido.';
comment on column public.notifications.dedupe_key is
  'Chave única que impede duplicar a mesma notificação (ex.: overdue:{task_id}:{recipient_id}:{canal}).';
comment on column public.notifications.payload is 'Dados para montar o texto (títulos, horários).';
comment on column public.notifications.sent_at is 'Quando foi entregue no canal (nulo = ainda na fila).';
comment on column public.notifications.read_at is 'Quando a pessoa marcou como lida (única coluna que ela pode alterar).';
