-- Desfaz 20261021000400_perfis.sql.

drop trigger on_auth_user_created on auth.users;
drop function private.handle_new_user();
drop table public.profiles;
