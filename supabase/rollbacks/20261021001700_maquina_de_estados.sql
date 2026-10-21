-- Desfaz 20261021001700_maquina_de_estados.sql.

drop trigger tasks_enforce_status on public.tasks;
drop function private.enforce_task_status();
drop function private.task_status_transition_allowed(public.task_status, public.task_status);
