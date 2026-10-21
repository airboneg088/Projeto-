-- Desfaz 20261021002300_rpc_auditoria_e_admin.sql.

drop function public.set_profile_status(uuid, public.profile_status);
drop function public.admin_read_tasks(uuid, date, date);
drop function public.log_admin_login(uuid, text, text);
revoke usage on schema private from supabase_auth_admin;
drop function private.custom_access_token_hook(jsonb);
drop function public.log_event(text, jsonb);
