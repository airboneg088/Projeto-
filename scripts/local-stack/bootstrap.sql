-- =============================================================================
-- Bootstrap da stack local: reproduz o ambiente do Supabase hospedado
-- (papéis, schemas, extensões e grants) num Postgres 16 comum.
--
-- Idempotente. Aplicado:
--   1. ao banco 'postgres' quando o cluster é criado (os papéis são globais);
--   2. ao template 'ede_template', do qual todo `pnpm db:reset` clona o banco.
--
-- Referência: scripts de inicialização da imagem supabase/postgres
-- (00000000000000-initial-schema.sql, auth-schema e permissões de API).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Papéis (globais do cluster)
-- -----------------------------------------------------------------------------
do $$
begin
  -- Papel usado em requisições sem login (chave anon/publishable)
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  -- Papel de qualquer usuário autenticado (JWT com role=authenticated)
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  -- Papel do servidor (chave secreta). Ignora RLS. Nunca chega ao navegador.
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  -- Papel de login do PostgREST; troca para anon/authenticated/service_role conforme o JWT
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login noinherit password 'postgres';
  end if;
  -- Dono do schema auth (GoTrue)
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin login noinherit createrole password 'postgres';
  end if;
  -- Dono do schema storage (storage-api; aqui só o shim SQL)
  if not exists (select 1 from pg_roles where rolname = 'supabase_storage_admin') then
    create role supabase_storage_admin login noinherit createrole password 'postgres';
  end if;
end
$$;

grant anon to authenticator;
grant authenticated to authenticator;
grant service_role to authenticator;
grant authenticator to supabase_storage_admin;

alter role supabase_auth_admin set search_path = auth;
alter role supabase_storage_admin set search_path = storage;

-- Limites de tempo por papel, como no hospedado (aplicados pelo PostgREST na troca de papel)
alter role anon set statement_timeout = '3s';
alter role authenticated set statement_timeout = '8s';

-- -----------------------------------------------------------------------------
-- Extensões no schema "extensions" (como no hospedado)
-- -----------------------------------------------------------------------------
create schema if not exists extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;

grant usage on schema extensions to postgres, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Schema public: exatamente como no Supabase hospedado.
-- Tudo que o papel postgres criar em public fica acessível às roles da API;
-- a proteção real é a RLS. Por isso toda tabela precisa de RLS habilitada.
-- -----------------------------------------------------------------------------
grant usage on schema public to postgres, anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on functions to postgres, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Schema auth: criado vazio e entregue ao supabase_auth_admin.
-- As tabelas e funções vêm das migrations do próprio GoTrue.
-- -----------------------------------------------------------------------------
create schema if not exists auth authorization supabase_auth_admin;
grant usage on schema auth to postgres, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Recarga automática do cache de schema do PostgREST após DDL
-- (mesmas event triggers do Supabase hospedado).
-- -----------------------------------------------------------------------------
create or replace function extensions.pgrst_ddl_watch() returns event_trigger
language plpgsql
as $$
declare
  cmd record;
begin
  for cmd in select * from pg_event_trigger_ddl_commands()
  loop
    if cmd.command_tag in (
        'CREATE SCHEMA', 'ALTER SCHEMA',
        'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE',
        'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE',
        'CREATE VIEW', 'ALTER VIEW',
        'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW',
        'CREATE FUNCTION', 'ALTER FUNCTION',
        'CREATE TRIGGER',
        'CREATE TYPE', 'ALTER TYPE',
        'CREATE RULE',
        'COMMENT'
      )
      -- objetos temporários (pg_temp) não interessam
      and cmd.schema_name is distinct from 'pg_temp'
    then
      notify pgrst, 'reload schema';
    end if;
  end loop;
end;
$$;

create or replace function extensions.pgrst_drop_watch() returns event_trigger
language plpgsql
as $$
declare
  obj record;
begin
  for obj in select * from pg_event_trigger_dropped_objects()
  loop
    if obj.object_type in (
        'schema', 'table', 'foreign table', 'view', 'materialized view',
        'function', 'trigger', 'type', 'rule'
      )
      and obj.is_temporary is false
    then
      notify pgrst, 'reload schema';
    end if;
  end loop;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_event_trigger where evtname = 'pgrst_ddl_watch') then
    create event trigger pgrst_ddl_watch on ddl_command_end
      execute procedure extensions.pgrst_ddl_watch();
  end if;
  if not exists (select 1 from pg_event_trigger where evtname = 'pgrst_drop_watch') then
    create event trigger pgrst_drop_watch on sql_drop
      execute procedure extensions.pgrst_drop_watch();
  end if;
end
$$;
