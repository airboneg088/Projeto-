-- =============================================================================
-- Shim do schema "storage" para a stack local.
--
-- O serviço storage-api não roda localmente (sem Docker). Este shim recria as
-- tabelas storage.buckets e storage.objects com as mesmas colunas, tipos e
-- padrões do schema real do storage-api, além das funções auxiliares
-- storage.foldername/filename/extension. Assim as policies de storage das
-- migrations são aplicadas e testadas em SQL (pgTAP) como no hospedado.
--
-- Idempotente. Aplicado ao template ede_template.
-- =============================================================================

create schema if not exists storage authorization supabase_storage_admin;

grant usage on schema storage to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_storage_admin in schema storage
  grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_storage_admin in schema storage
  grant all on sequences to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_storage_admin in schema storage
  grant all on functions to postgres, anon, authenticated, service_role;

-- Tipo do bucket (storage-api: STANDARD, ANALYTICS e VECTOR)
do $$
begin
  if not exists (
    select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'storage' and t.typname = 'buckettype'
  ) then
    create type storage.buckettype as enum ('STANDARD', 'ANALYTICS', 'VECTOR');
  end if;
end
$$;
alter type storage.buckettype owner to supabase_storage_admin;

-- Buckets
create table if not exists storage.buckets (
  id text not null primary key,
  name text not null,
  owner uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  public boolean default false,
  avif_autodetection boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  owner_id text,
  type storage.buckettype not null default 'STANDARD'
);
create unique index if not exists bname on storage.buckets using btree (name);
comment on column storage.buckets.owner is 'Campo obsoleto; use owner_id';
alter table storage.buckets owner to supabase_storage_admin;

-- Objetos (arquivos)
create table if not exists storage.objects (
  id uuid not null default gen_random_uuid() primary key,
  bucket_id text constraint "objects_bucketId_fkey" references storage.buckets (id),
  name text,
  owner uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  last_accessed_at timestamptz default now(),
  metadata jsonb,
  path_tokens text[] generated always as (string_to_array(name, '/')) stored,
  version text,
  owner_id text,
  user_metadata jsonb
);
create unique index if not exists bucketid_objname on storage.objects using btree (bucket_id, name);
create index if not exists name_prefix_search on storage.objects using btree (name text_pattern_ops);
comment on column storage.objects.owner is 'Campo obsoleto; use owner_id';
alter table storage.objects owner to supabase_storage_admin;

-- RLS habilitada nas duas tabelas: as policies das migrations decidem o acesso
alter table storage.buckets enable row level security;
alter table storage.objects enable row level security;

-- Grants como no hospedado (tudo para as roles da API; a RLS decide)
grant all on storage.buckets to postgres, anon, authenticated, service_role;
grant all on storage.objects to postgres, anon, authenticated, service_role;

-- Funções auxiliares usadas nas policies (mesma semântica do storage-api)
create or replace function storage.foldername(name text)
returns text[]
language plpgsql
immutable
as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1 : array_length(_parts, 1) - 1];
end
$$;

create or replace function storage.filename(name text)
returns text
language plpgsql
immutable
as $$
declare
  _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[array_length(_parts, 1)];
end
$$;

create or replace function storage.extension(name text)
returns text
language plpgsql
immutable
as $$
declare
  _parts text[];
  _filename text;
begin
  select string_to_array(name, '/') into _parts;
  select _parts[array_length(_parts, 1)] into _filename;
  return reverse(split_part(reverse(_filename), '.', 1));
end
$$;

create or replace function storage.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end
$$;

alter function storage.foldername(text) owner to supabase_storage_admin;
alter function storage.filename(text) owner to supabase_storage_admin;
alter function storage.extension(text) owner to supabase_storage_admin;
alter function storage.update_updated_at_column() owner to supabase_storage_admin;
grant execute on function storage.foldername(text), storage.filename(text), storage.extension(text)
  to postgres, anon, authenticated, service_role;

drop trigger if exists update_objects_updated_at on storage.objects;
create trigger update_objects_updated_at
  before update on storage.objects
  for each row execute function storage.update_updated_at_column();
