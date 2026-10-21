-- Desfaz 20261021002100_rpc_execucao.sql.

drop function public.submit_attempt(uuid, text, uuid);
drop function public.register_evidence(uuid, uuid, text, timestamptz, numeric, numeric, numeric, text, bigint, integer, boolean, uuid);
drop function public.answer_item(uuid, uuid, boolean, text);
drop function public.start_attempt(uuid, uuid);
