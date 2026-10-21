-- Desfaz 20261021001900_auditoria.sql.
-- Os registros já gravados em audit_log ficam (a tabela só sai no rollback dela).

drop trigger data_requests_forbid_truncate on public.data_requests;
drop trigger task_items_forbid_truncate on public.task_items;
drop trigger tasks_forbid_truncate on public.tasks;
drop trigger schedules_forbid_truncate on public.schedules;
drop trigger template_items_forbid_truncate on public.template_items;
drop trigger task_templates_forbid_truncate on public.task_templates;
drop trigger profiles_forbid_truncate on public.profiles;
drop trigger memberships_forbid_truncate on public.memberships;
drop trigger sectors_forbid_truncate on public.sectors;
drop trigger store_settings_forbid_truncate on public.store_settings;
drop trigger stores_forbid_truncate on public.stores;
drop trigger organizations_forbid_truncate on public.organizations;

drop trigger data_requests_audit on public.data_requests;
drop trigger evidences_audit_purge on public.evidences;
drop trigger tasks_audit_edit on public.tasks;
drop trigger tasks_audit_cancel on public.tasks;
drop trigger tasks_audit_insert on public.tasks;
drop trigger schedules_audit on public.schedules;
drop trigger template_items_audit on public.template_items;
drop trigger task_templates_audit on public.task_templates;
drop trigger profiles_audit_status on public.profiles;
drop trigger memberships_audit on public.memberships;
drop trigger sectors_audit on public.sectors;
drop trigger store_settings_audit on public.store_settings;
drop trigger stores_audit on public.stores;
drop trigger organizations_audit on public.organizations;

drop function private.audit_row();
drop function private.audit_value(jsonb);
