-- Desfaz 20261021002700_rls_planos_notificacoes_lgpd_auditoria.sql.

drop policy audit_log_select_admin on public.audit_log;
drop policy audit_log_select_owner on public.audit_log;

drop policy data_requests_update_admin on public.data_requests;
drop policy data_requests_insert_own on public.data_requests;
drop policy data_requests_select on public.data_requests;

drop policy notifications_update_own on public.notifications;
drop policy notifications_select_own on public.notifications;

drop policy action_plans_update_manager_owner on public.action_plans;
drop policy action_plans_insert_manager_owner on public.action_plans;
drop policy action_plans_select on public.action_plans;
