-- =============================================================================
-- Funções RPC de auditoria e administração.
--   log_event          : registra exportações no audit_log (gerente ou
--                        proprietária; detalhes com chaves conhecidas, valores
--                        simples e no máximo 2 KB; no máximo 10 por minuto e
--                        200 por dia por pessoa: o audit_log é append-only e
--                        não pode virar depósito)
--   custom_access_token_hook (private): hook do Auth (Custom Access Token). Grava
--                        'admin_login' para TODO login de admin, inclusive direto
--                        na API pública do Auth (D79): a regra fica no Auth, não
--                        na tela do app (D64). Só o papel do Auth executa.
--   log_admin_login    : complementa o login de admin com ip e user_agent de
--                        fonte confiável ('admin_login_context'). SÓ a chave
--                        secreta chama (o servidor, logo depois do login): o
--                        navegador não consegue gravar um contexto inventado
--   admin_read_tasks   : leitura de tarefas pelo admin, sempre auditada
--                        (admin não tem SELECT direto em tabelas operacionais)
--   set_profile_status : admin ativa/desativa uma pessoa da organização
--                        (auditado pelo gatilho); nunca proprietária nem admin
-- =============================================================================

-- -----------------------------------------------------------------------------
-- log_event
-- -----------------------------------------------------------------------------
create function public.log_event(p_action text, p_details jsonb default '{}'::jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_allowed text[];
begin
  if v_uid is null then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- admin_login não passa por aqui: só o servidor grava, por log_admin_login
  if p_action = 'export' then
    if not private.has_role('{manager,owner}'::public.membership_role[]) then
      raise exception 'forbidden' using errcode = 'P0001';
    end if;
    v_allowed := array['formato', 'escopo', 'filtros', 'periodo', 'linhas'];
  else
    raise exception 'forbidden' using errcode = 'P0001',
      detail = 'Evento não permitido. Use export.';
  end if;

  -- Detalhes: objeto pequeno, só com as chaves conhecidas do evento e valores simples
  -- (texto de até 500 caracteres, número ou booleano; nada aninhado)
  if jsonb_typeof(v_details) <> 'object'
     or octet_length(v_details::text) > 2048
     or exists (select 1 from jsonb_object_keys(v_details) as k (key) where k.key <> all (v_allowed))
     or exists (
       select 1
       from jsonb_each(v_details) as d (key, value)
       where jsonb_typeof(d.value) not in ('string', 'number', 'boolean')
          or (jsonb_typeof(d.value) = 'string' and char_length(d.value #>> '{}') > 500)
     ) then
    raise exception 'invalid_details' using errcode = 'P0001',
      detail = format('Detalhes: objeto de até 2 KB com as chaves %s e valores simples.', array_to_string(v_allowed, ', '));
  end if;

  -- Quantidade limitada por pessoa (D76): o audit_log é append-only, então o tamanho (2 KB)
  -- não basta. Acima do limite a exportação é recusada (o Route Handler registra antes de
  -- exportar, então nada sai sem registro). Trava por pessoa: chamadas simultâneas contam
  -- uma de cada vez.
  perform pg_advisory_xact_lock(hashtextextended('log_event:' || v_uid::text, 0));
  if (select count(*) from public.audit_log l
      where l.actor_id = v_uid and l.action = p_action
        and l.occurred_at > now() - interval '1 minute') >= 10
     or (select count(*) from public.audit_log l
         where l.actor_id = v_uid and l.action = p_action
           and l.occurred_at > now() - interval '1 day') >= 200 then
    raise exception 'rate_limited' using errcode = 'P0001',
      detail = 'Muitas exportações seguidas. Espere um minuto e tente de novo.';
  end if;

  insert into public.audit_log (occurred_at, organization_id, actor_id, action, table_name, record_id, diff)
  values (now(), private.current_org_id(), v_uid, p_action, null, null, v_details);
end;
$$;

comment on function public.log_event(text, jsonb) is
  'Registra no audit_log uma exportação (só gerente ou proprietária; detalhes formato, escopo, filtros, periodo, linhas, com valores simples e até 2 KB: invalid_details; no máximo 10 por minuto e 200 por dia por pessoa: rate_limited). Autor = usuário logado. O login de admin é registrado pelo Auth (private.custom_access_token_hook).';

-- -----------------------------------------------------------------------------
-- custom_access_token_hook: login de admin registrado pelo próprio Auth (D79)
--   O Auth (GoTrue) chama a função a cada token emitido, como supabase_auth_admin
--   ([auth.hook.custom_access_token] no config.toml). Login (qualquer método que não
--   seja a renovação do token) de quem tem vínculo vigente de admin, com perfil
--   ativo, grava 'admin_login' com o método, a sessão e o nível de autenticação;
--   um registro por sessão (dois logins no mesmo minuto, em aparelhos diferentes,
--   são dois registros; D102) e, contra inundação, no máximo 20 por admin por
--   minuto. Devolve as claims sem mudança e NUNCA levanta erro (erro no hook
--   bloquearia o login de todo mundo): falha vira aviso no log do Postgres.
--   Função ausente ou sem permissão derruba o login de todos: desligue o hook no
--   Auth antes do rollback desta migration e, no deploy, ligue-o só depois dela
--   (docs/dev-local.md §6).
-- -----------------------------------------------------------------------------
create function private.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_method text := left(coalesce(event ->> 'authentication_method', 'desconhecido'), 40);
  v_user_id uuid;
  v_org uuid;
  v_session text;
  v_aal text;
begin
  if v_method <> 'token_refresh' then
    begin
      v_user_id := (event ->> 'user_id')::uuid;
      -- Sessão e nível de autenticação vêm das claims que o próprio Auth montou
      v_session := lower(event -> 'claims' ->> 'session_id');
      if v_session !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        v_session := null;
      end if;
      v_aal := case when event -> 'claims' ->> 'aal' in ('aal1', 'aal2', 'aal3')
                    then event -> 'claims' ->> 'aal' end;

      select m.organization_id into v_org
      from public.memberships m
      join public.profiles p on p.id = m.profile_id
      where m.profile_id = v_user_id
        and m.role = 'admin'
        and m.store_id is null
        and p.status = 'active'
        and m.starts_at <= now()
        and (m.ends_at is null or m.ends_at > now())
      order by m.starts_at desc, m.id
      limit 1;

      if v_org is not null then
        perform pg_advisory_xact_lock(hashtextextended('admin_login:' || v_user_id::text, 0));
        if not exists (
             -- Um registro por sessão (o mesmo login não se repete); sem sessão nas claims,
             -- um por minuto
             select 1 from public.audit_log l
             where l.actor_id = v_user_id
               and l.action = 'admin_login'
               and (case when v_session is null then l.occurred_at > now() - interval '1 minute'
                         else l.occurred_at > now() - interval '1 day' and l.diff ->> 'sessao' = v_session end)
           )
           -- Contra inundação: no máximo 20 por admin por minuto
           and (select count(*) from public.audit_log l
                where l.actor_id = v_user_id
                  and l.action = 'admin_login'
                  and l.occurred_at > now() - interval '1 minute') < 20 then
          insert into public.audit_log (occurred_at, organization_id, actor_id, action, table_name, record_id, diff)
          values (now(), v_org, v_user_id, 'admin_login', null, null,
                  jsonb_strip_nulls(jsonb_build_object('metodo', v_method, 'sessao', v_session, 'aal', v_aal)));
        end if;
      end if;
    exception
      when others then
        raise warning 'custom_access_token_hook: login de admin não registrado (%: %)', sqlstate, sqlerrm;
    end;
  end if;

  return jsonb_build_object('claims', event -> 'claims');
end;
$$;

comment on function private.custom_access_token_hook(jsonb) is
  'Hook Custom Access Token do Auth: todo login de admin (vínculo de rede vigente, perfil ativo) que não seja renovação de token grava admin_login no audit_log com o método (password, recovery...), a sessão e o nível de autenticação (aal), um por sessão (sem sessão nas claims, um por minuto) e no máximo 20 por admin por minuto, inclusive quando o login é feito direto na API do Auth. Devolve as claims sem mudança e nunca levanta erro. Só o papel do Auth (supabase_auth_admin) executa. Desligue o hook no Auth antes de remover esta função.';

revoke all on function private.custom_access_token_hook(jsonb) from public, anon, authenticated, service_role;
grant usage on schema private to supabase_auth_admin;
grant execute on function private.custom_access_token_hook(jsonb) to supabase_auth_admin;

-- -----------------------------------------------------------------------------
-- log_admin_login (só service_role: o servidor chama logo depois do login)
--   Contexto do login de admin (ip de fonte confiável, D68, e user_agent). O login
--   em si é registrado pelo Auth (custom_access_token_hook, 'admin_login').
-- -----------------------------------------------------------------------------
create function public.log_admin_login(p_actor_id uuid, p_ip text default null, p_user_agent text default null)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_ip inet;
  v_user_agent text := left(private.clean_text(p_user_agent), 300);
  v_details jsonb := '{}'::jsonb;
begin
  -- Só vale para quem tem, agora, vínculo de admin de rede vigente com perfil ativo
  select m.organization_id into v_org
  from public.memberships m
  join public.profiles p on p.id = m.profile_id
  where m.profile_id = p_actor_id
    and m.role = 'admin'
    and m.store_id is null
    and p.status = 'active'
    and m.starts_at <= now()
    and (m.ends_at is null or m.ends_at > now())
  order by m.starts_at desc, m.id
  limit 1;
  if v_org is null then
    return false;
  end if;

  -- No máximo um registro por admin por minuto (pedidos repetidos não enchem a trilha)
  perform pg_advisory_xact_lock(hashtextextended('admin_login_context:' || p_actor_id::text, 0));
  if exists (
    select 1 from public.audit_log l
    where l.actor_id = p_actor_id
      and l.action = 'admin_login_context'
      and l.occurred_at > now() - interval '1 minute'
  ) then
    return false;
  end if;

  -- ip só se for um endereço válido; user_agent cortado
  begin
    v_ip := nullif(btrim(p_ip), '')::inet;
  exception
    when others then
      v_ip := null;
  end;
  if v_ip is not null then
    v_details := v_details || jsonb_build_object('ip', host(v_ip));
  end if;
  if v_user_agent is not null then
    v_details := v_details || jsonb_build_object('user_agent', v_user_agent);
  end if;

  insert into public.audit_log (occurred_at, organization_id, actor_id, action, table_name, record_id, diff)
  values (now(), v_org, p_actor_id, 'admin_login_context', null, null, v_details);
  return true;
end;
$$;

comment on function public.log_admin_login(uuid, text, text) is
  'Registra no audit_log o contexto do login de um admin (admin_login_context: ip, só endereço válido, e user_agent, até 300 caracteres), para quem tem vínculo de rede vigente e perfil ativo. Só a chave secreta executa: o servidor chama logo depois do login, com o id do usuário autenticado; no máximo um registro por admin por minuto. O login em si é gravado pelo Auth (private.custom_access_token_hook). Devolve verdadeiro se registrou.';

-- -----------------------------------------------------------------------------
-- admin_read_tasks
-- -----------------------------------------------------------------------------
create function public.admin_read_tasks(p_store_id uuid, p_from date, p_to date)
returns setof public.tasks
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null
     or not private.is_admin()
     or not (p_store_id = any (private.current_store_ids('{admin}'::public.membership_role[]))) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  insert into public.audit_log (occurred_at, organization_id, actor_id, action, table_name, record_id, diff)
  values (
    now(),
    private.current_org_id(),
    v_uid,
    'admin_read',
    'tasks',
    p_store_id::text,
    jsonb_build_object('store_id', p_store_id, 'from', p_from, 'to', p_to)
  );

  return query
    select t.*
    from public.tasks t
    join public.stores s on s.id = t.store_id
    where t.store_id = p_store_id
      and (t.due_at at time zone s.timezone)::date between p_from and p_to
    order by t.due_at, t.id;
end;
$$;

comment on function public.admin_read_tasks(uuid, date, date) is
  'Admin lê as tarefas de uma loja num período (datas locais da loja). Cada chamada grava admin_read no audit_log.';

-- -----------------------------------------------------------------------------
-- set_profile_status
-- -----------------------------------------------------------------------------
create function public.set_profile_status(p_profile_id uuid, p_status public.profile_status)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_org uuid := private.current_org_id();
begin
  if v_uid is null or v_org is null or not private.is_admin() or p_status is null then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- Ninguém se desativa (evita perder o último acesso de administração)
  if p_profile_id = v_uid then
    raise exception 'forbidden' using errcode = 'P0001', detail = 'Não é possível alterar a própria situação.';
  end if;

  -- Só pessoas com vínculo (atual ou antigo) nesta organização. Perfil inexistente,
  -- sem vínculo ou de outra organização: o mesmo erro.
  if not exists (
    select 1 from public.memberships m
    where m.profile_id = p_profile_id and m.organization_id = v_org
  ) then
    raise exception 'forbidden' using errcode = 'P0001';
  end if;

  -- Proprietária e admin (vínculo não encerrado) não são desativados por admin:
  -- o acesso deles muda pelo vínculo, que só a proprietária altera (can_manage_membership)
  if exists (
    select 1 from public.memberships m
    where m.profile_id = p_profile_id
      and m.role in ('owner', 'admin')
      and (m.ends_at is null or m.ends_at > now())
  ) then
    raise exception 'forbidden' using errcode = 'P0001',
      detail = 'Proprietária e admin não são desativados por aqui.';
  end if;

  perform 1 from public.profiles p where p.id = p_profile_id for update;

  update public.profiles set status = p_status where id = p_profile_id;
end;
$$;

comment on function public.set_profile_status(uuid, public.profile_status) is
  'Admin ativa ou desativa uma pessoa com vínculo na organização (nunca a si mesmo, a proprietária ou outro admin). Pessoa inativa perde todo acesso na hora. Auditado (profile_status_changed).';

revoke execute on function public.log_event(text, jsonb) from public, anon;
revoke execute on function public.log_admin_login(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.admin_read_tasks(uuid, date, date) from public, anon;
revoke execute on function public.set_profile_status(uuid, public.profile_status) from public, anon;
grant execute on function public.log_event(text, jsonb) to authenticated;
grant execute on function public.log_admin_login(uuid, text, text) to service_role;
grant execute on function public.admin_read_tasks(uuid, date, date) to authenticated;
grant execute on function public.set_profile_status(uuid, public.profile_status) to authenticated;
