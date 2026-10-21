-- Desfaz 20261021001650_integridade_entre_organizacoes.sql.

drop trigger data_requests_stamp_resolution on public.data_requests;
drop function private.stamp_data_request_resolution();

drop trigger action_plans_stamp_created_by on public.action_plans;
drop trigger tasks_stamp_created_by on public.tasks;
drop trigger schedules_stamp_created_by on public.schedules;
drop trigger task_templates_stamp_created_by on public.task_templates;
drop function private.stamp_created_by();

drop trigger action_plans_validate on public.action_plans;
drop function private.validate_action_plan();

drop trigger task_items_validate_lineage on public.task_items;
drop function private.validate_task_item_lineage();

drop trigger tasks_validate_references on public.tasks;
drop function private.validate_task_references();

drop trigger schedules_validate_assignee on public.schedules;
drop function private.validate_schedule_assignee();

drop trigger task_templates_validate_reference on public.task_templates;
drop function private.validate_template_reference();

drop trigger sectors_validate_responsible on public.sectors;
drop function private.validate_sector_responsible();

drop trigger memberships_protect_last_owner on public.memberships;
drop function private.protect_last_owner();

drop trigger memberships_single_organization on public.memberships;
drop function private.enforce_single_organization();

drop function private.raise_rls_violation(text);
drop function private.is_reference_path(text, uuid, uuid, uuid[]);
drop function private.is_member_of(uuid, uuid, uuid, boolean);
