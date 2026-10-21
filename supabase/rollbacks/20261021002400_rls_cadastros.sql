-- Desfaz 20261021002400_rls_cadastros.sql (a RLS continua ligada: sem policies, nada é lido pela API).

drop policy memberships_update_owner_admin on public.memberships;
drop policy memberships_insert_owner_admin on public.memberships;
drop policy memberships_select_visible on public.memberships;

drop policy profiles_update_self on public.profiles;
drop policy profiles_select_visible on public.profiles;

drop policy sectors_delete_manager on public.sectors;
drop policy sectors_update_manager on public.sectors;
drop policy sectors_insert_manager on public.sectors;
drop policy sectors_select_member on public.sectors;

drop policy store_settings_update_owner_admin on public.store_settings;
drop policy store_settings_select on public.store_settings;

drop policy stores_update_admin on public.stores;
drop policy stores_insert_admin on public.stores;
drop policy stores_select_member on public.stores;

drop policy organizations_update_admin on public.organizations;
drop policy organizations_select_member on public.organizations;
