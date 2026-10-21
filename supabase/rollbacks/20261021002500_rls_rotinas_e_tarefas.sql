-- Desfaz 20261021002500_rls_rotinas_e_tarefas.sql.

drop policy task_items_delete_manager_owner on public.task_items;
drop policy task_items_update_manager_owner on public.task_items;
drop policy task_items_insert_manager_owner on public.task_items;
drop policy task_items_select_with_task on public.task_items;

drop policy tasks_update_manager_owner on public.tasks;
drop policy tasks_insert_manager_owner on public.tasks;
drop policy tasks_select_staff on public.tasks;
drop policy tasks_select_manager_owner on public.tasks;

drop policy schedules_delete_manager_owner on public.schedules;
drop policy schedules_update_manager_owner on public.schedules;
drop policy schedules_insert_manager_owner on public.schedules;
drop policy schedules_select_manager_owner on public.schedules;

drop policy template_items_delete_manager_owner on public.template_items;
drop policy template_items_update_manager_owner on public.template_items;
drop policy template_items_insert_manager_owner on public.template_items;
drop policy template_items_select_with_template on public.template_items;

drop policy task_templates_delete_manager_owner on public.task_templates;
drop policy task_templates_update_manager_owner on public.task_templates;
drop policy task_templates_insert_manager_owner on public.task_templates;
drop policy task_templates_select_manager_owner on public.task_templates;
