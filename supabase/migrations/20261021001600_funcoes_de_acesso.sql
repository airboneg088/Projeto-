-- =============================================================================
-- Funções auxiliares de acesso (schema private), usadas pelas policies de RLS
-- e pelas funções RPC. Todas SECURITY DEFINER + STABLE + search_path vazio:
-- leem memberships/profiles sem passar pela RLS (evita recursão) e devolvem só
-- o que diz respeito a quem está logado (auth.uid()).
--
-- "Vínculo vigente" = starts_at <= now() < ends_at (ou ends_at nulo) e perfil
-- ativo. Cada pessoa pertence a uma única organização (garantido por gatilho em
-- memberships); mesmo assim, todo papel é contado só dentro da organização atual
-- (current_org_id) e owner/admin só valem como vínculo de rede (store_id nulo).
-- Se a pessoa tivesse vínculos vigentes em duas organizações, current_org_id
-- devolve nulo e todas as funções negam acesso (falha fechada).
-- Nas policies, sempre chamar dentro de (select ...) para avaliar uma vez por
-- consulta, não por linha.
-- =============================================================================

-- Organização do usuário logado (única; nula se não houver ou se houver mais de uma)
create function private.current_org_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case when count(distinct m.organization_id) = 1 then (array_agg(m.organization_id))[1] end
  from public.memberships m
  join public.profiles p on p.id = m.profile_id
  where m.profile_id = auth.uid()
    and p.status = 'active'
    and m.starts_at <= now()
    and (m.ends_at is null or m.ends_at > now())
$$;

comment on function private.current_org_id() is
  'Organização do usuário logado, pelos vínculos vigentes (perfil ativo). Nulo se não houver vínculo vigente ou se eles forem de mais de uma organização (falha fechada).';

-- Organização a que o usuário logado pertence ou pertenceu, por QUALQUER vínculo (vigente,
-- futuro ou encerrado) e com qualquer situação do perfil. Uma pessoa, uma organização (D21);
-- se houver mais de uma, nula (falha fechada). Só para o canal do titular (LGPD, D78): quem
-- saiu ou foi desativado continua podendo pedir correção ou exportação dos próprios dados.
-- Não dá acesso a nada da operação.
create function private.home_org_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case when count(distinct m.organization_id) = 1 then (array_agg(m.organization_id))[1] end
  from public.memberships m
  where m.profile_id = auth.uid()
$$;

comment on function private.home_org_id() is
  'Organização dos vínculos do usuário logado, vigentes ou não, com qualquer situação do perfil (nula se não houver vínculo ou se houver mais de uma organização). Usada só no pedido do titular (LGPD), que continua aberto a quem saiu.';

-- Lojas em que o usuário logado tem vínculo vigente com um dos papéis pedidos.
-- Vínculo de rede (store_id nulo) de owner/admin vale para todas as lojas da organização.
create function private.current_store_ids(p_roles public.membership_role[])
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct s.id), '{}'::uuid[])
  from public.memberships m
  join public.profiles p on p.id = m.profile_id
  join public.stores s
    on s.organization_id = m.organization_id
   and (
     (m.store_id is not null and m.role in ('manager', 'staff') and s.id = m.store_id)
     or (m.store_id is null and m.role in ('owner', 'admin'))
   )
  where m.profile_id = auth.uid()
    and p.status = 'active'
    and m.role = any (p_roles)
    and m.organization_id = private.current_org_id()
    and m.starts_at <= now()
    and (m.ends_at is null or m.ends_at > now())
$$;

comment on function private.current_store_ids(public.membership_role[]) is
  'Lojas da organização atual em que o usuário logado tem vínculo vigente com algum dos papéis pedidos (owner/admin, sempre de rede = todas as lojas da organização).';

-- Tem vínculo vigente com algum dos papéis pedidos?
create function private.has_role(p_roles public.membership_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.profiles p on p.id = m.profile_id
    where m.profile_id = auth.uid()
      and p.status = 'active'
      and m.role = any (p_roles)
      and m.organization_id = private.current_org_id()
      -- owner/admin só contam como vínculo de rede; gerente/colaborador, com loja
      and (m.store_id is null) = (m.role in ('owner', 'admin'))
      and m.starts_at <= now()
      and (m.ends_at is null or m.ends_at > now())
  )
$$;

comment on function private.has_role(public.membership_role[]) is
  'Verdadeiro se o usuário logado tem, na organização atual, vínculo vigente com algum dos papéis pedidos (owner/admin só de rede).';

create function private.is_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_role('{owner}'::public.membership_role[])
$$;

comment on function private.is_owner() is
  'Verdadeiro se o usuário logado é proprietária (vínculo de rede vigente) da organização atual.';

create function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_role('{admin}'::public.membership_role[])
$$;

comment on function private.is_admin() is
  'Verdadeiro se o usuário logado é admin (suporte técnico, vínculo de rede vigente) da organização atual.';

-- Setores em que o usuário logado é colaborador vigente (tarefas de equipe)
create function private.current_sector_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct m.sector_id), '{}'::uuid[])
  from public.memberships m
  join public.profiles p on p.id = m.profile_id
  where m.profile_id = auth.uid()
    and p.status = 'active'
    and m.role = 'staff'
    and m.sector_id is not null
    and m.organization_id = private.current_org_id()
    and m.starts_at <= now()
    and (m.ends_at is null or m.ends_at > now())
$$;

comment on function private.current_sector_ids() is
  'Setores em que o usuário logado tem vínculo vigente de colaborador. Define as tarefas de equipe (assignee nulo) que ele vê e executa.';

-- Perfis que o usuário logado pode ver além do próprio
create function private.visible_profile_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select private.current_org_id() as org_id,
           private.current_store_ids('{manager}'::public.membership_role[]) as manager_stores,
           (private.is_owner() or private.is_admin()) as org_wide,
           private.is_admin() as is_admin
  )
  select coalesce(array_agg(distinct x.id), '{}'::uuid[])
  from (
    -- gerente: equipe da loja (vínculos atuais e antigos, para o histórico)
    select m.profile_id as id
    from public.memberships m, me
    where m.store_id = any (me.manager_stores)
    union
    -- gerente: pessoas de rede da organização (proprietária, admin)
    select m.profile_id
    from public.memberships m, me
    where cardinality(me.manager_stores) > 0
      and m.store_id is null
      and m.organization_id = me.org_id
    union
    -- proprietária e admin: todas as pessoas com vínculo na organização
    select m.profile_id
    from public.memberships m, me
    where me.org_wide
      and m.organization_id = me.org_id
    union
    -- admin: pessoas recém-criadas para ESTA organização, ainda sem vínculo (para
    -- cadastrar o vínculo). A organização vem de auth.users.raw_app_meta_data
    -- (organization_id), gravada por quem cria a conta com a chave secreta.
    select p.id
    from public.profiles p
    join auth.users u on u.id = p.id, me
    where me.is_admin
      and me.org_id is not null
      and u.raw_app_meta_data ->> 'organization_id' = me.org_id::text
      and not exists (select 1 from public.memberships m where m.profile_id = p.id)
  ) x
$$;

comment on function private.visible_profile_ids() is
  'Perfis visíveis ao usuário logado além do próprio: equipe da loja (gerente), pessoas da organização (proprietária/admin) e perfis ainda sem vínculo criados para a organização do admin (app_metadata.organization_id).';

-- Pode criar/alterar um vínculo com este papel para esta pessoa? (policies de memberships)
create function private.can_manage_membership(p_profile_id uuid, p_role public.membership_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.is_owner() then true
    when private.is_admin() then
      -- admin só cuida de vínculos de gerente e colaborador: vínculo de proprietária e de
      -- admin (papéis de rede) só a proprietária cria, encerra, estende ou reabre (D23).
      -- Nunca o próprio vínculo (D15: não se dá acesso operacional) e não dá papel
      -- operacional a quem tem papel de rede. Só olha vínculos da organização atual
      -- (não revela papéis da pessoa em outra organização).
      p_role in ('manager', 'staff')
      and p_profile_id is distinct from auth.uid()
      and not exists (
        select 1
        from public.memberships m
        where m.profile_id = p_profile_id
          and m.organization_id = private.current_org_id()
          and (m.ends_at is null or m.ends_at > now())
          and m.role in ('owner', 'admin')
      )
    else false
  end
$$;

comment on function private.can_manage_membership(uuid, public.membership_role) is
  'Verdadeiro se o usuário logado pode criar ou alterar um vínculo com esse papel para essa pessoa: proprietária sempre; admin só vínculos de gerente e colaborador, nunca o próprio e nunca para quem tem papel de rede (proprietária/admin) na organização. Vínculos de proprietária e de admin só a proprietária altera.';

-- Pode criar/editar esta rotina? (gerente da loja da rotina; proprietária em qualquer uma)
create function private.can_manage_template(p_template_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.task_templates t
    where t.id = p_template_id
      and t.organization_id = private.current_org_id()
      and (
        (t.store_id is not null
          and t.store_id = any (private.current_store_ids('{manager,owner}'::public.membership_role[])))
        or (t.store_id is null and private.is_owner())
      )
  )
$$;

comment on function private.can_manage_template(uuid) is
  'Verdadeiro se o usuário logado pode alterar a rotina e seus itens: gerente da loja da rotina ou proprietária (inclusive rotinas da rede).';

-- Pode alterar os itens desta tarefa? (gerente/proprietária, tarefa ainda não iniciada)
create function private.can_manage_pending_task(p_task_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.tasks t
    where t.id = p_task_id
      and t.store_id = any (private.current_store_ids('{manager,owner}'::public.membership_role[]))
      and t.status = 'pending'
      and t.attempt_count = 0
  )
$$;

comment on function private.can_manage_pending_task(uuid) is
  'Verdadeiro se o usuário logado é gerente da loja (ou proprietária) e a tarefa ainda está pendente, sem tentativas.';

-- Pode executar esta tarefa? (usada pelas funções RPC)
create function private.can_execute_task(p_task_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.tasks t
    where t.id = p_task_id
      and t.store_id = any (private.current_store_ids('{staff}'::public.membership_role[]))
      and (
        t.assignee_id = auth.uid()
        or (t.assignee_id is null and t.sector_id = any (private.current_sector_ids()))
      )
  )
$$;

comment on function private.can_execute_task(uuid) is
  'Verdadeiro se o usuário logado é colaborador vigente da loja e a tarefa é dele ou da equipe do seu setor.';

-- A tarefa ainda é de quem iniciou a tentativa aberta? (a mesma regra de
-- can_execute_task, para uma pessoa qualquer em vez do usuário logado). Usada na
-- passagem da tarefa para outra pessoa: nulo = continua com ela; senão, o motivo.
create function private.stale_attempt_reason(p_task_id uuid, p_profile_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  with staff as (
    select m.sector_id
    from public.tasks t
    join public.memberships m
      on m.organization_id = t.organization_id
     and m.store_id = t.store_id
    join public.profiles p on p.id = m.profile_id
    where t.id = p_task_id
      and m.profile_id = p_profile_id
      and m.role = 'staff'
      and p.status = 'active'
      and m.starts_at <= now()
      and (m.ends_at is null or m.ends_at > now())
  )
  select case
    when not exists (select 1 from staff) then 'access_lost'
    when exists (
      select 1
      from public.tasks t
      where t.id = p_task_id
        and (
          t.assignee_id = p_profile_id
          or (t.assignee_id is null and t.sector_id in (select s.sector_id from staff s))
        )
    ) then null
    else 'reassigned'
  end
$$;

comment on function private.stale_attempt_reason(uuid, uuid) is
  'Nulo se a pessoa ainda pode executar a tarefa (colaborador vigente da loja e a tarefa é dela ou da equipe do seu setor). Senão, o motivo para encerrar a tentativa aberta dela: access_lost (sem vínculo vigente de colaborador na loja ou perfil inativo) ou reassigned (a tarefa é de outra pessoa ou de outro setor).';

-- -----------------------------------------------------------------------------
-- Privilégios: nada para public/anon; policies rodam como authenticated
-- -----------------------------------------------------------------------------
revoke all on function private.current_org_id() from public, anon;
revoke all on function private.home_org_id() from public, anon;
revoke all on function private.current_store_ids(public.membership_role[]) from public, anon;
revoke all on function private.has_role(public.membership_role[]) from public, anon;
revoke all on function private.is_owner() from public, anon;
revoke all on function private.is_admin() from public, anon;
revoke all on function private.current_sector_ids() from public, anon;
revoke all on function private.visible_profile_ids() from public, anon;
revoke all on function private.can_manage_membership(uuid, public.membership_role) from public, anon;
revoke all on function private.can_manage_template(uuid) from public, anon;
revoke all on function private.can_manage_pending_task(uuid) from public, anon;
revoke all on function private.can_execute_task(uuid) from public, anon;
revoke all on function private.stale_attempt_reason(uuid, uuid) from public, anon;

grant execute on function private.current_org_id() to authenticated;
grant execute on function private.home_org_id() to authenticated;
grant execute on function private.current_store_ids(public.membership_role[]) to authenticated;
grant execute on function private.has_role(public.membership_role[]) to authenticated;
grant execute on function private.is_owner() to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.current_sector_ids() to authenticated;
grant execute on function private.visible_profile_ids() to authenticated;
grant execute on function private.can_manage_membership(uuid, public.membership_role) to authenticated;
grant execute on function private.can_manage_template(uuid) to authenticated;
grant execute on function private.can_manage_pending_task(uuid) to authenticated;
