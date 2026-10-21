-- =============================================================================
-- Ajustes após as migrations do GoTrue (schema auth).
-- Garante auth.uid(), auth.role(), auth.email() e auth.jwt() com as mesmas
-- definições do Supabase hospedado. Só cria as que faltarem (não substitui as
-- criadas pelo próprio GoTrue) e aplica os grants de uso pelas roles da API.
-- Idempotente.
-- =============================================================================

do $outer$
begin
  if to_regprocedure('auth.uid()') is null then
    execute $f$
      create function auth.uid() returns uuid
      language sql stable
      as $body$
        select coalesce(
          nullif(current_setting('request.jwt.claim.sub', true), ''),
          (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
        )::uuid
      $body$
    $f$;
    alter function auth.uid() owner to supabase_auth_admin;
  end if;

  if to_regprocedure('auth.role()') is null then
    execute $f$
      create function auth.role() returns text
      language sql stable
      as $body$
        select coalesce(
          nullif(current_setting('request.jwt.claim.role', true), ''),
          (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
        )::text
      $body$
    $f$;
    alter function auth.role() owner to supabase_auth_admin;
  end if;

  if to_regprocedure('auth.email()') is null then
    execute $f$
      create function auth.email() returns text
      language sql stable
      as $body$
        select coalesce(
          nullif(current_setting('request.jwt.claim.email', true), ''),
          (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
        )::text
      $body$
    $f$;
    alter function auth.email() owner to supabase_auth_admin;
  end if;

  if to_regprocedure('auth.jwt()') is null then
    execute $f$
      create function auth.jwt() returns jsonb
      language sql stable
      as $body$
        select coalesce(
          nullif(current_setting('request.jwt.claim', true), ''),
          nullif(current_setting('request.jwt.claims', true), '')
        )::jsonb
      $body$
    $f$;
    alter function auth.jwt() owner to supabase_auth_admin;
  end if;
end
$outer$;

grant usage on schema auth to postgres, anon, authenticated, service_role;
grant execute on function auth.uid(), auth.role(), auth.email(), auth.jwt()
  to postgres, anon, authenticated, service_role;
