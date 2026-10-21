-- Desfaz 20261021000700_rotinas_e_agendamentos.sql.

drop table public.schedules;
drop function private.is_valid_schedule_rule(jsonb);
drop function private.validate_schedule();
drop table public.template_items;
drop function private.bump_template_version_from_items();
drop table public.task_templates;
drop function private.bump_template_version();
