-- Desfaz 20261021001600_funcoes_de_acesso.sql.

drop function private.can_execute_task(uuid);
drop function private.can_manage_pending_task(uuid);
drop function private.can_manage_template(uuid);
drop function private.can_manage_membership(uuid, public.membership_role);
drop function private.visible_profile_ids();
drop function private.current_sector_ids();
drop function private.is_admin();
drop function private.is_owner();
drop function private.has_role(public.membership_role[]);
drop function private.current_store_ids(public.membership_role[]);
drop function private.current_org_id();
