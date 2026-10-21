-- =============================================================================
-- 103 · Regressão R1-FI-10: privilégios padrão que sobravam.
--   - anon: nenhum privilégio em tabela/sequência de public (nem nas futuras);
--   - authenticated: só tem INSERT/UPDATE/DELETE onde existe policy do comando;
--   - TRUNCATE (ignora RLS e gatilhos de auditoria por linha): nenhuma role da
--     API trunca, nem a service_role; nas tabelas auditadas nem o postgres.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(9);

select tests.create_base_fixture();

select is(
  array(
    select c.relname::text || ':' || p.priv
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) as p (priv)
    where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm')
      and (has_table_privilege('anon', c.oid, p.priv)
           or (p.priv in ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES') and has_any_column_privilege('anon', c.oid, p.priv)))
    order by 1
  ),
  '{}'::text[],
  'anon não tem privilégio nenhum em tabela de public'
);

select is(
  array(
    select c.relname::text
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'S'
      and (has_sequence_privilege('anon', c.oid, 'USAGE') or has_sequence_privilege('anon', c.oid, 'SELECT')
           or has_sequence_privilege('anon', c.oid, 'UPDATE'))
  ),
  '{}'::text[],
  'anon não usa sequência de public'
);

select is(
  array(
    select d.defaclobjtype::text
    from pg_default_acl d
    cross join aclexplode(d.defaclacl) a
    where d.defaclrole = 'postgres'::regrole
      and d.defaclnamespace = 'public'::regnamespace
      and a.grantee = 'anon'::regrole
  ),
  '{}'::text[],
  'tabelas, sequências e funções futuras de public não nascem com privilégio para anon'
);

-- authenticated: comando só com policy ------------------------------------------
select is(
  array(
    select c.relname::text || ':' || p.cmd
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join (values ('INSERT', 'a'), ('UPDATE', 'w'), ('DELETE', 'd')) as p (cmd, polcmd)
    where n.nspname = 'public' and c.relkind = 'r'
      and (has_table_privilege('authenticated', c.oid, p.cmd)
           or (p.cmd <> 'DELETE' and has_any_column_privilege('authenticated', c.oid, p.cmd)))
      and not exists (
        select 1 from pg_policy pol
        where pol.polrelid = c.oid
          and pol.polcmd in (p.polcmd::"char", '*')
          and 'authenticated'::regrole = any (pol.polroles)
      )
    order by 1
  ),
  '{}'::text[],
  'authenticated só tem INSERT/UPDATE/DELETE em tabelas com policy para o comando'
);

-- TRUNCATE -------------------------------------------------------------------------
select is(
  array(
    select c.relname::text || ':' || r.rolname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join (values ('anon'), ('authenticated'), ('service_role')) as r (rolname)
    where n.nspname = 'public' and c.relkind = 'r'
      and has_table_privilege(r.rolname, c.oid, 'TRUNCATE')
    order by 1
  ),
  '{}'::text[],
  'nenhuma role da API (nem service_role) tem TRUNCATE em public'
);

select is(
  array(
    select t.relname::text
    from unnest(array['organizations', 'stores', 'store_settings', 'sectors', 'memberships', 'profiles',
                      'task_templates', 'template_items', 'schedules', 'tasks']) as t (relname)
    where not exists (
      select 1 from pg_trigger tg
      where tg.tgrelid = ('public.' || t.relname)::regclass
        and not tg.tgisinternal
        and (tg.tgtype & 32) <> 0      -- TRUNCATE
        and (tg.tgtype & 2) <> 0       -- BEFORE
    )
  ),
  '{}'::text[],
  'tabelas auditadas têm gatilho que barra TRUNCATE'
);

select tests.authenticate_service_role();
select throws_ok($$ truncate public.memberships $$, '42501', null, 'service_role NÃO trunca memberships');
select tests.reset_role();
select throws_ok($$ truncate public.memberships cascade $$, 'P0001', 'immutable',
  'nem o postgres trunca memberships (sumiria sem auditoria)');
select is(
  (select count(*) from public.memberships where organization_id = tests.fx('org_a')),
  7::bigint,
  'vínculos da org A continuam lá'
);

select * from finish();
rollback;
