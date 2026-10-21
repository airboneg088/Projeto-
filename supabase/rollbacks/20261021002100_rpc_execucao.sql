-- Desfaz 20261021002100_rpc_execucao.sql.

drop function public.submit_attempt(uuid, text, uuid);
drop function public.register_evidence(uuid, uuid, text, timestamptz, numeric, numeric, numeric, text, bigint, integer, boolean, uuid);
drop function public.answer_item(uuid, uuid, boolean, text, uuid, timestamptz);
drop function public.start_attempt(uuid, uuid, timestamptz);
drop trigger profiles_release_attempts on public.profiles;
drop trigger memberships_release_attempts on public.memberships;
drop function private.release_attempts_of_person();
drop trigger tasks_release_attempt_on_reassign on public.tasks;
drop function private.release_attempt_on_reassign();
drop function private.release_stale_attempt(uuid);
