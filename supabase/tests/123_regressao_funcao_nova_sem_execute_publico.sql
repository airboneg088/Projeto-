-- =============================================================================
-- 123 · Regressão R2-FUNC-13 (correção incompleta de R1-FI-10): função nova
-- criada pelo postgres não nasce executável por PUBLIC (que anon e
-- authenticated herdam). O padrão é global (alter default privileges ... revoke
-- execute on functions from public); em public, authenticated e service_role
-- recebem pelo padrão do schema; em private, só com grant explícito.
-- =============================================================================
begin;

select plan(4);

create function public.r2_funcao_esquecida() returns integer language sql set search_path = '' as $$ select 1 $$;
create function private.r2_funcao_esquecida() returns integer language sql set search_path = '' as $$ select 1 $$;

select ok(not has_function_privilege('anon', 'public.r2_funcao_esquecida()', 'EXECUTE'),
  'função nova em public NÃO nasce executável por anon');
select ok(not has_function_privilege('authenticated', 'private.r2_funcao_esquecida()', 'EXECUTE'),
  'função nova em private NÃO nasce executável por authenticated (só com grant explícito)');
select ok(not exists (select 1 from aclexplode((select proacl from pg_proc where oid = 'private.r2_funcao_esquecida()'::regprocedure)) a
                      where a.grantee = 0),
  'função nova em private não tem EXECUTE para PUBLIC');
select ok(exists (select 1 from pg_default_acl d
                  where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 0 and d.defaclobjtype = 'f'
                    and not exists (select 1 from aclexplode(d.defaclacl) a where a.grantee = 0)),
  'padrão global do postgres para funções não inclui PUBLIC');

select * from finish();
rollback;
