-- Desfaz 20261021002000_geracao_de_tarefas.sql.

drop function private.instantiate_task(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid, date, uuid, public.task_priority);
