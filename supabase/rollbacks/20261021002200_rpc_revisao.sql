-- Desfaz 20261021002200_rpc_revisao.sql.

drop function public.cancel_task(uuid, text);
drop function public.review_attempt(uuid, public.review_decision, text, uuid[]);
