-- =============================================================================
-- 001 · Estrutura e segurança do catálogo
-- RLS em toda tabela, search_path fixo nas funções SECURITY DEFINER, nenhuma
-- função de public executável por anon, sem TRUNCATE/TRIGGER/REFERENCES para
-- as roles da API, privilégios por coluna e buckets privados.
-- =============================================================================
begin;
\ir helpers/auth.psql

select plan(23);

-- RLS -------------------------------------------------------------------------
select is_empty(
  $$
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
  $$,
  'toda tabela de public tem RLS habilitada'
);

select set_eq(
  $$
    select c.relname::text
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
  $$,
  array[
    'action_plans', 'attempt_item_answers', 'audit_log', 'data_requests', 'evidences',
    'memberships', 'notifications', 'organizations', 'profiles', 'review_item_flags',
    'reviews', 'schedules', 'sectors', 'store_settings', 'stores', 'task_attempts',
    'task_items', 'task_templates', 'tasks', 'template_items'
  ],
  'public tem exatamente as tabelas do modelo (tabela nova exige atualizar os testes de isolamento)'
);

select is_empty(
  $$
    select schemaname || '.' || tablename || '.' || policyname
    from pg_policies
    where schemaname in ('public', 'storage') and roles <> '{authenticated}'::name[]
  $$,
  'todas as policies valem só para authenticated (anon não tem nenhuma)'
);

-- Funções ---------------------------------------------------------------------
select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prosecdef
      and not coalesce('search_path=""' = any (p.proconfig), false)
  $$,
  'toda função SECURITY DEFINER em public/private fixa search_path vazio'
);

select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
  $$,
  'toda função em public/private fixa search_path (inclusive as SECURITY INVOKER)'
);

select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'EXECUTE')
  $$,
  'anon não executa nenhuma função de public'
);

select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname <> 'log_admin_login'
      and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
  $$,
  'authenticated executa todas as RPCs e indicadores de public (menos log_admin_login)'
);

select ok(
  not has_function_privilege('authenticated', 'public.log_admin_login(uuid, text, text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.log_admin_login(uuid, text, text)', 'EXECUTE'),
  'log_admin_login: só a chave secreta (service_role) executa, nunca o navegador'
);

select set_eq(
  $$
    select p.proname::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
  $$,
  array[
    'start_attempt', 'answer_item', 'register_evidence', 'submit_attempt', 'review_attempt',
    'cancel_task', 'log_event', 'log_admin_login', 'admin_read_tasks', 'set_profile_status',
    'kpi_summary', 'weighted_scores', 'top_failed_items', 'can_read_evidence', 'can_read_reference'
  ],
  'public expõe só as RPCs e os indicadores previstos'
);

select ok(
  not has_schema_privilege('anon', 'private', 'USAGE'),
  'anon não usa o schema private'
);

select is_empty(
  $$
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and (has_function_privilege('anon', p.oid, 'EXECUTE')
           or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0))
  $$,
  'nenhuma função de private é executável por anon ou PUBLIC'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.instantiate_task(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid, date, uuid, public.task_priority)',
    'EXECUTE'
  ),
  'authenticated não gera tarefas chamando private.instantiate_task direto'
);

-- Privilégios de tabela ------------------------------------------------------
select is_empty(
  $$
    select format('%s:%s:%s', r.rolname, c.relname, pr.priv)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join (values ('anon'), ('authenticated')) as r (rolname)
    cross join (values ('TRUNCATE'), ('TRIGGER'), ('REFERENCES')) as pr (priv)
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and (has_table_privilege(r.rolname, c.oid, pr.priv)
           or (pr.priv = 'REFERENCES' and has_any_column_privilege(r.rolname, c.oid, 'REFERENCES')))
  $$,
  'anon e authenticated não têm TRUNCATE, TRIGGER nem REFERENCES em nenhuma tabela de public'
);

select is_empty(
  $$
    select format('%s:%s:%s', r.rolname, c.relname, pr.priv)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join (values ('anon'), ('authenticated')) as r (rolname)
    cross join (values ('INSERT'), ('UPDATE'), ('DELETE')) as pr (priv)
    where n.nspname = 'public'
      and c.relname in ('task_attempts', 'attempt_item_answers', 'evidences', 'reviews', 'review_item_flags', 'audit_log')
      and (has_table_privilege(r.rolname, c.oid, pr.priv)
           or case when pr.priv = 'DELETE' then false
                   else has_any_column_privilege(r.rolname, c.oid, pr.priv) end)
  $$,
  'execução, revisão e auditoria: sem INSERT/UPDATE/DELETE direto para anon e authenticated (só via RPC)'
);

select ok(
  not has_table_privilege('service_role', 'public.audit_log', 'INSERT')
  and not has_table_privilege('service_role', 'public.audit_log', 'UPDATE')
  and not has_table_privilege('service_role', 'public.audit_log', 'DELETE'),
  'nem a service_role grava direto no audit_log'
);

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'full_name', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.profiles', 'status', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.profiles', 'id', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.profiles', 'INSERT')
  and not has_table_privilege('authenticated', 'public.profiles', 'DELETE'),
  'profiles: authenticated só altera full_name'
);

select ok(
  has_column_privilege('authenticated', 'public.notifications', 'read_at', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.notifications', 'recipient_id', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.notifications', 'payload', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.notifications', 'INSERT'),
  'notifications: authenticated só altera read_at'
);

select ok(
  not has_column_privilege('authenticated', 'public.tasks', 'status', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.tasks', 'status', 'INSERT')
  and not has_column_privilege('authenticated', 'public.tasks', 'cancel_reason', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.tasks', 'attempt_count', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.tasks', 'DELETE')
  and has_column_privilege('authenticated', 'public.tasks', 'due_at', 'UPDATE'),
  'tasks: status, tentativas e cancelamento só mudam via RPC; sem DELETE'
);

-- Storage ---------------------------------------------------------------------
select results_eq(
  $$
    select id, public, file_size_limit, allowed_mime_types
    from storage.buckets
    where id in ('evidences', 'references')
    order by id
  $$,
  $$
    values ('evidences'::text, false, 5242880::bigint, array['image/jpeg', 'image/png', 'image/webp']::text[]),
           ('references'::text, false, 5242880::bigint, array['image/jpeg', 'image/png', 'image/webp']::text[])
  $$,
  'buckets evidences e references são privados, até 5 MB, só imagens'
);

select set_eq(
  $$
    select policyname::text || ':' || cmd
    from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
  $$,
  array['evidences_insert_performer:INSERT', 'references_insert_manager:INSERT'],
  'storage.objects: só policies de INSERT (sem SELECT, UPDATE, DELETE: leitura só por signed URL do servidor, D77)'
);

-- Perfil nasce com o usuário do Auth -----------------------------------------
select has_trigger('auth', 'users', 'on_auth_user_created', 'gatilho de criação de perfil existe em auth.users');

insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', tests.fx('novo'), 'authenticated', 'authenticated',
        'novo@teste.local', '{"full_name": "[TESTE] Pessoa Nova"}', now(), now());

select results_eq(
  $$ select full_name, status::text from public.profiles where id = tests.fx('novo') $$,
  $$ values ('[TESTE] Pessoa Nova'::text, 'active'::text) $$,
  'cadastro no Auth cria o perfil ativo com o nome do metadata'
);

select throws_ok(
  $$ delete from auth.users where id = tests.fx('novo') $$,
  '23503',
  null,
  'apagar usuário com perfil falha (pessoas são desativadas, nunca apagadas)'
);

select * from finish();
rollback;
