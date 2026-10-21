-- =============================================================================
-- Perfis (1:1 com auth.users).
-- O perfil nasce automaticamente quando o usuário é criado no Auth (gatilho em
-- auth.users). Pessoas nunca são apagadas: são desativadas (status = inactive).
-- Por isso a FK para auth.users é ON DELETE RESTRICT: apagar o usuário do Auth
-- falha enquanto existir o perfil (o histórico depende dele).
-- =============================================================================

create table public.profiles (
  id uuid primary key references auth.users (id) on delete restrict,
  full_name text not null default '',
  status public.profile_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_full_name_length check (char_length(full_name) <= 200)
);

-- RLS ligada desde a criação (sem policies = ninguém lê pela API até a migration de RLS)
alter table public.profiles enable row level security;

comment on table public.profiles is
  'Pessoa que usa o sistema (1:1 com auth.users). Criada por gatilho no cadastro do Auth; nunca apagada, só desativada.';
comment on column public.profiles.id is 'Mesmo id do usuário em auth.users.';
comment on column public.profiles.full_name is
  'Nome exibido. Copiado de raw_user_meta_data.full_name no cadastro; a própria pessoa pode alterar.';
comment on column public.profiles.status is
  'active ou inactive. Perfil inativo perde todo acesso imediatamente, mesmo com vínculos vigentes.';

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

-- -----------------------------------------------------------------------------
-- Gatilho em auth.users: cria o perfil
-- -----------------------------------------------------------------------------
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    left(
      coalesce(
        nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        ''
      ),
      200
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

comment on function private.handle_new_user() is
  'Gatilho AFTER INSERT em auth.users: cria public.profiles com o nome de raw_user_meta_data.full_name (ou a parte local do e-mail).';

revoke all on function private.handle_new_user() from public, anon;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();
