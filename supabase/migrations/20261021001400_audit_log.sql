-- =============================================================================
-- Trilha de auditoria (append-only).
-- Gravada somente por código SECURITY DEFINER (gatilhos e funções RPC).
-- Ninguém insere direto pela API; UPDATE/DELETE são bloqueados por gatilho
-- para todos os papéis (migration de imutabilidade).
-- =============================================================================

create table public.audit_log (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  organization_id uuid,
  actor_id uuid references public.profiles (id) on delete restrict,
  action text not null,
  table_name text,
  record_id text,
  diff jsonb not null default '{}'::jsonb,
  constraint audit_log_action_not_blank check (btrim(action) <> '')
);

alter table public.audit_log enable row level security;

comment on table public.audit_log is
  'Auditoria append-only: quem fez o quê, em qual registro, com quais mudanças. Nunca alterada nem apagada.';
comment on column public.audit_log.id is 'Sequencial (ordem estável dos eventos).';
comment on column public.audit_log.organization_id is
  'Organização do registro afetado (escopo de leitura). Sem FK para que a auditoria nunca impeça outra operação.';
comment on column public.audit_log.actor_id is 'Quem fez (auth.uid()). Nulo = sistema (jobs, seed, chave secreta).';
comment on column public.audit_log.action is
  'insert, update, delete, task_cancelled, evidence_purged, profile_status_changed, admin_login, export, admin_read.';
comment on column public.audit_log.table_name is 'Tabela afetada (nulo em eventos como login de admin).';
comment on column public.audit_log.record_id is 'Id do registro afetado, em texto.';
comment on column public.audit_log.diff is
  'Mudanças: { coluna: { "old": valor, "new": valor } } só com as colunas alteradas; em eventos, os detalhes.';
