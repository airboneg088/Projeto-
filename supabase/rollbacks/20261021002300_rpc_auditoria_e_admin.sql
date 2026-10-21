-- Desfaz 20261021002300_rpc_auditoria_e_admin.sql.
--
-- ATENÇÃO (R4-INTEGRIDADE-04): ANTES de aplicar este rollback, desligue o hook Custom
-- Access Token no Auth ([auth.hook.custom_access_token] enabled = false no config.toml +
-- `supabase config push`, ou Authentication -> Hooks no painel; na stack local,
-- `pnpm stack:up --restart auth` depois de mudar o config.toml). Com o hook ligado e a
-- função private.custom_access_token_hook removida (ou sem USAGE no schema private), o Auth
-- responde 500 a TODO login, inclusive de quem precisaria consertar. O "nunca levanta erro"
-- da D79 vale só dentro da função. Ver docs/dev-local.md §6 (Hooks do Auth).

drop function public.set_profile_status(uuid, public.profile_status);
drop function public.admin_read_tasks(uuid, date, date);
drop function public.log_admin_login(uuid, text, text);
revoke usage on schema private from supabase_auth_admin;
drop function private.custom_access_token_hook(jsonb);
drop function public.log_event(text, jsonb);
