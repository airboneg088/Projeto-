-- Desfaz 20261021003000_indicadores.sql.

drop function public.top_failed_items(date, date, uuid[], integer);
drop function public.weighted_scores(date, date, text, uuid[]);
drop function public.kpi_summary(date, date, uuid[], uuid[], uuid[]);
drop function private.task_person(uuid, uuid, uuid, boolean);
