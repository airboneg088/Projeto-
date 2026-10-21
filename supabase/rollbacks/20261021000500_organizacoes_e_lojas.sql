-- Desfaz 20261021000500_organizacoes_e_lojas.sql.

drop table public.sectors;
drop trigger stores_create_settings on public.stores;
drop function private.create_store_settings();
drop table public.store_settings;
drop table public.stores;
drop table public.organizations;
