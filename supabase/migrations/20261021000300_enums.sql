-- =============================================================================
-- Tipos enumerados do domínio (docs/modelo-de-dados.md §3).
-- Novos valores entram por migration aditiva (alter type ... add value).
-- =============================================================================

create type public.membership_role as enum ('owner', 'manager', 'staff', 'admin');
comment on type public.membership_role is
  'Papel no vínculo: owner (proprietária), manager (gerente), staff (colaborador), admin (suporte técnico).';

create type public.profile_status as enum ('active', 'inactive');
comment on type public.profile_status is
  'Situação da pessoa. Pessoas são desativadas (inactive), nunca apagadas.';

create type public.task_status as enum (
  'pending', 'in_progress', 'submitted', 'approved', 'rejected', 'overdue', 'cancelled'
);
comment on type public.task_status is
  'Estado da tarefa: pendente, em andamento, aguardando aprovação (submitted), aprovada, correção solicitada (rejected), atrasada (overdue), cancelada. Só approved conta como concluída.';

create type public.task_priority as enum ('low', 'normal', 'high', 'urgent');
comment on type public.task_priority is 'Prioridade exibida como Baixa, Normal, Alta e Urgente.';

create type public.schedule_frequency as enum ('daily', 'weekly', 'monthly', 'specific_days');
comment on type public.schedule_frequency is
  'Recorrência do agendamento: diária, semanal (rule.weekdays), mensal (rule.monthdays) ou datas específicas (rule.dates).';

create type public.review_decision as enum ('approved', 'rejected');
comment on type public.review_decision is 'Decisão da revisão de uma tentativa.';

create type public.action_plan_status as enum ('open', 'in_progress', 'done', 'cancelled');
comment on type public.action_plan_status is 'Situação do plano de ação.';

create type public.notification_channel as enum ('in_app', 'email');
comment on type public.notification_channel is
  'Canal de envio. Push e WhatsApp entram depois por migration aditiva.';

create type public.notification_type as enum (
  'due_soon', 'overdue', 'correction_requested', 'recurring_reminder', 'awaiting_approval',
  'escalation_manager', 'escalation_owner', 'daily_summary', 'task_cancelled', 'sync_conflict'
);
comment on type public.notification_type is 'Tipo de notificação (regras na Fase 6).';

create type public.data_request_kind as enum ('correction', 'export');
comment on type public.data_request_kind is 'Pedido do titular (LGPD): correção ou exportação dos próprios dados.';
