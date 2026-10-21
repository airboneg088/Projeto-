-- =============================================================================
-- 139 · Regressão R3-APP-05: o login de admin é registrado pelo próprio Auth
-- (hook Custom Access Token, private.custom_access_token_hook), não só quando
-- passa pela Server Action do app. Um login feito direto na API pública do Auth
-- (POST /auth/v1/token com a chave publicável) também grava 'admin_login'.
--   - login de admin (qualquer método que não seja a renovação do token): 1
--     registro com o método, no máximo um por minuto;
--   - renovação do token (token_refresh), quem não é admin, admin desativado: nada;
--   - devolve as claims sem mudança e nunca levanta erro (erro bloquearia o login);
--   - só o papel do Auth (supabase_auth_admin) executa; o navegador não.
-- O teste ponta a ponta (HTTP, GoTrue local com o hook ligado) está em
-- e2e/auth.spec.ts.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(11);

select tests.create_base_fixture();

-- O Auth chama o hook com o papel dele (supabase_auth_admin)
create function tests.auth_hook(p_user text, p_method text)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform tests.reset_role();
  perform set_config('role', 'supabase_auth_admin', true);
  v_result := private.custom_access_token_hook(jsonb_build_object(
    'user_id', tests.fx(p_user),
    'authentication_method', p_method,
    'claims', jsonb_build_object('sub', tests.fx(p_user), 'role', 'authenticated', 'aal', 'aal1')
  ));
  perform tests.reset_role();
  return v_result;
end;
$$;

create function tests.admin_logins(p_user text)
returns bigint
language sql
as $$
  select count(*) from public.audit_log where action = 'admin_login' and actor_id = tests.fx(p_user)
$$;

select is(
  tests.auth_hook('admin_a', 'password'),
  jsonb_build_object('claims', jsonb_build_object('sub', tests.fx('admin_a'), 'role', 'authenticated', 'aal', 'aal1')),
  'o hook devolve as claims sem mudança');
select is(tests.admin_logins('admin_a'), 1::bigint, 'login de admin por senha grava admin_login (mesmo sem passar pelo app)');
select is(
  (select diff from public.audit_log where action = 'admin_login' and actor_id = tests.fx('admin_a')),
  '{"metodo": "password"}'::jsonb,
  'o registro diz o método do login (e nada informado pelo cliente)');

select tests.auth_hook('admin_a', 'token_refresh');
select tests.auth_hook('admin_a', 'password');
select is(tests.admin_logins('admin_a'), 1::bigint,
  'renovação do token não é login, e outro login no mesmo minuto não gera outra linha');

select tests.auth_hook('staff_p1', 'password');
select tests.auth_hook('owner_a', 'password');
select is(
  (select count(*) from public.audit_log where action = 'admin_login'),
  1::bigint, 'colaborador e proprietária não geram login de admin');

-- Admin com vínculo encerrado: não é login de admin
select tests.create_user('admin_a2', '[TESTE] Admin A2', 'org_a');
select tests.create_membership('admin_a2', 'org_a', null, null, 'admin');
update public.memberships set ends_at = now() where id = tests.fx('m_admin_a2');
select tests.auth_hook('admin_a2', 'recovery');
select is(tests.admin_logins('admin_a2'), 0::bigint, 'admin com vínculo encerrado não gera registro');

-- Entrada inesperada nunca derruba o login
create function tests.auth_hook_raw(p_event jsonb)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb;
begin
  perform tests.reset_role();
  perform set_config('role', 'supabase_auth_admin', true);
  v_result := private.custom_access_token_hook(p_event);
  perform tests.reset_role();
  return v_result;
end;
$$;
set local client_min_messages = error; -- o aviso no log do Postgres é esperado
select is(
  tests.auth_hook_raw('{"user_id": "não é uuid", "authentication_method": "password", "claims": {"sub": "x"}}'::jsonb),
  '{"claims": {"sub": "x"}}'::jsonb,
  'evento malformado não levanta erro: devolve as claims e o login segue');

-- Quem executa
select ok(has_function_privilege('supabase_auth_admin', 'private.custom_access_token_hook(jsonb)', 'EXECUTE'),
  'o papel do Auth executa o hook');
select ok(
  not has_function_privilege('authenticated', 'private.custom_access_token_hook(jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.custom_access_token_hook(jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role', 'private.custom_access_token_hook(jsonb)', 'EXECUTE'),
  'navegador (anon/authenticated) e chave secreta não chamam o hook');
select tests.authenticate_as('admin_a2');
select ok(
  tests.exec_result(format($$ select private.custom_access_token_hook(%L::jsonb) $$,
    jsonb_build_object('user_id', tests.fx('admin_a2'), 'authentication_method', 'password', 'claims', '{}'::jsonb)))
  like '42501:%',
  'admin logado não grava um login pelo hook (42501)');
select tests.reset_role();
select is(
  (select count(*) from public.audit_log where action = 'admin_login'),
  1::bigint, 'no fim, um único registro de login de admin');

select * from finish();
rollback;
