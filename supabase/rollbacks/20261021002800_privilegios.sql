-- Desfaz 20261021002800_privilegios.sql, voltando aos privilégios padrão do
-- Supabase hospedado (ALL para anon, authenticated e service_role, sem
-- privilégio por coluna). Revoga tudo e concede de novo, nesta ordem, para as
-- entradas de ACL voltarem na mesma ordem de antes (anon, authenticated,
-- service_role). Revogar o privilégio da tabela também revoga os de coluna.

revoke all on all tables in schema public from anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;

revoke all on all sequences in schema public from anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on tables to anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on functions to anon, authenticated, service_role;

-- Padrão global: funções novas voltam a nascer com EXECUTE para PUBLIC
alter default privileges for role postgres grant execute on functions to public;
