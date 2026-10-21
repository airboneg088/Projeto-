-- =============================================================================
-- Integridade entre lojas e organizações.
--
-- As FKs simples (pessoa, rotina, item) não garantem que a referência é da
-- mesma organização ou da mesma loja. Estes gatilhos fecham isso para qualquer
-- papel (inclusive a chave secreta):
--   memberships   : cada pessoa pertence a uma única organização
--   sectors       : responsável com vínculo na loja (ou de rede na organização)
--   task_templates: imagem de referência no caminho da própria rotina
--   schedules     : responsável colaborador ativo da loja
--   tasks         : rotina da mesma organização (rede ou mesma loja), versão
--                   existente, responsável colaborador ativo da loja, imagem de
--                   referência da própria organização/loja
--   task_items    : linhagem (template_item_id) só da rotina da própria tarefa
--   action_plans  : item de rotina da organização/loja e responsável com vínculo
--                   na loja (gerente/colaborador) ou proprietária
-- Tarefa e item criados a partir de rotina copiam a versão ATUAL dela
-- (exigências, peso, item crítico): o snapshot não é forjável.
-- created_by é sempre quem está logado (nulo = sistema) e data_requests.resolved_by
-- é quem concluiu o pedido: nenhum dos dois é informado pelo cliente.
--
-- Erros: errcode 23514 com mensagem estável (chave para a interface):
--   profile_other_organization, invalid_responsible, invalid_reference_path,
--   invalid_assignee, invalid_template, invalid_template_version,
--   invalid_template_item, invalid_owner, invalid_snapshot.
-- A mesma chave vale para id inexistente e para id de outra loja/organização.
--
-- Gatilhos BEFORE rodam ANTES do WITH CHECK da RLS. Para não revelarem o que
-- existe fora do alcance de quem grava (vínculos, rotinas, versões, linhagem),
-- quem grava pela API (auth.uid() presente) sem poder gravar no destino recebe
-- primeiro o MESMO erro da RLS (42501), sem nenhuma consulta: a validação só
-- roda para quem pode gravar ali. Sem usuário logado (sistema, chave secreta),
-- a validação roda sempre.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Auxiliares
-- -----------------------------------------------------------------------------

-- A pessoa tem vínculo não encerrado (vigente ou futuro) na loja (ou de rede na organização)?
create function private.is_member_of(
  p_profile_id uuid,
  p_organization_id uuid,
  p_store_id uuid,
  p_include_network boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_profile_id is not null and exists (
    select 1
    from public.memberships m
    where m.profile_id = p_profile_id
      and m.organization_id = p_organization_id
      and (
        (p_store_id is not null and m.store_id = p_store_id)
        or (p_include_network and m.store_id is null)
      )
      and (m.ends_at is null or m.ends_at > now())
  )
$$;

comment on function private.is_member_of(uuid, uuid, uuid, boolean) is
  'Verdadeiro se a pessoa tem vínculo não encerrado (vigente ou futuro) na loja ou, se pedido, vínculo de rede na organização.';

revoke all on function private.is_member_of(uuid, uuid, uuid, boolean) from public, anon;

-- Pode ser responsável por tarefa/agendamento da loja? Quem executa é o colaborador
-- (start_attempt exige vínculo vigente de staff): gerente, proprietária ou perfil inativo
-- como responsável deixariam a tarefa sem ninguém que pudesse iniciá-la (D86).
create function private.can_be_assignee(
  p_profile_id uuid,
  p_organization_id uuid,
  p_store_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_profile_id is not null and exists (
    select 1
    from public.memberships m
    join public.profiles p on p.id = m.profile_id
    where m.profile_id = p_profile_id
      and m.organization_id = p_organization_id
      and m.store_id = p_store_id
      and m.role = 'staff'
      and p.status = 'active'
      and (m.ends_at is null or m.ends_at > now())
  )
$$;

comment on function private.can_be_assignee(uuid, uuid, uuid) is
  'Verdadeiro se a pessoa pode ser responsável por tarefa ou agendamento da loja: vínculo de colaborador não encerrado (vigente ou futuro) na loja e perfil ativo.';

revoke all on function private.can_be_assignee(uuid, uuid, uuid) from public, anon;

-- Caminho no bucket references: {org}/{loja ou rede}/{dono}/{uuid}.{jpg|png|webp}
create function private.is_reference_path(
  p_path text,
  p_organization_id uuid,
  p_store_id uuid,
  p_owner_ids uuid[]
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  -- coalesce: qualquer nulo (caminho, dono ausente) conta como inválido
  select coalesce(
    p_path ~ ('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
              '/(rede|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'
              '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
              '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$')
    and split_part(p_path, '/', 1) = p_organization_id::text
    and split_part(p_path, '/', 2) in ('rede', coalesce(p_store_id::text, 'rede'))
    and split_part(p_path, '/', 3) in (select o::text from unnest(p_owner_ids) as o where o is not null),
    false
  )
$$;

comment on function private.is_reference_path(text, uuid, uuid, uuid[]) is
  'Verdadeiro se o caminho é {organização}/{loja ou rede}/{um dos donos}/{uuid}.{jpg|png|webp} da própria organização (sem loja = só a pasta rede).';

revoke all on function private.is_reference_path(text, uuid, uuid, uuid[]) from public, anon;

-- Mesmo erro (código e mensagem) que a RLS dá a quem não pode gravar a linha
create function private.raise_rls_violation(p_table text)
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'new row violates row-level security policy for table "%"', p_table
    using errcode = '42501';
end;
$$;

comment on function private.raise_rls_violation(text) is
  'Levanta o mesmo erro da RLS (42501, "new row violates row-level security policy for table ..."). Usada pelos gatilhos de validação antes de qualquer consulta, para quem grava pela API sem alcance no destino.';

revoke all on function private.raise_rls_violation(text) from public, anon;

-- -----------------------------------------------------------------------------
-- memberships: uma pessoa, uma organização
-- BEFORE (e não AFTER): perfil inexistente, de outra organização ou com conta
-- criada para outra organização dão todos a mesma resposta, antes da FK.
-- -----------------------------------------------------------------------------
create function private.enforce_single_organization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_declared_org text;
begin
  -- Pela API, quem não pode gravar o vínculo recebe o erro da RLS antes de qualquer consulta
  if v_uid is not null
     and not (new.organization_id = private.current_org_id()
              and private.can_manage_membership(new.profile_id, new.role)) then
    perform private.raise_rls_violation('memberships');
  end if;

  -- Serializa vínculos da mesma pessoa (dois cadastros simultâneos em organizações diferentes)
  perform 1 from public.profiles p where p.id = new.profile_id for no key update;

  select u.raw_app_meta_data ->> 'organization_id' into v_declared_org
  from auth.users u
  where u.id = new.profile_id;

  if not exists (select 1 from public.profiles p where p.id = new.profile_id)
     -- Já tem vínculo em outra organização
     or exists (
       select 1
       from public.memberships m
       where m.profile_id = new.profile_id
         and m.organization_id <> new.organization_id
     )
     -- Conta criada para outra organização (app_metadata gravado por quem criou a conta)
     or v_declared_org <> new.organization_id::text
     -- Pela API, o 1º vínculo exige a conta criada para ESTA organização: conta sem
     -- organização declarada não é "capturada" por quem a vincular primeiro
     or (v_uid is not null
         and v_declared_org is null
         and not exists (select 1 from public.memberships m where m.profile_id = new.profile_id)) then
    raise exception 'profile_other_organization'
      using errcode = '23514',
            detail = 'Cada pessoa pertence a uma única organização: a conta precisa existir e ter sido criada para esta organização.';
  end if;

  return new;
end;
$$;

comment on function private.enforce_single_organization() is
  'Gatilho BEFORE INSERT/UPDATE em memberships: recusa (profile_other_organization) perfil inexistente, de quem já tem vínculo em outra organização ou cuja conta foi criada para outra; pela API, o 1º vínculo exige app_metadata.organization_id desta organização. Quem não pode gravar o vínculo recebe antes o erro da RLS.';

revoke all on function private.enforce_single_organization() from public, anon;

create trigger memberships_single_organization
  before insert or update of profile_id, organization_id on public.memberships
  for each row execute function private.enforce_single_organization();

-- -----------------------------------------------------------------------------
-- memberships: a organização nunca fica sem proprietária
-- Encerrar, agendar o fim, adiar o início ou apagar o vínculo vigente de
-- proprietária só é aceito se houver OUTRA proprietária vigente e sem fim
-- (só ela cria vínculo de proprietária; sem nenhuma, só a chave secreta resolveria).
-- -----------------------------------------------------------------------------
create function private.protect_last_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'owner'
     and old.store_id is null
     and old.starts_at <= now()
     and (old.ends_at is null or old.ends_at > now())
     and (tg_op = 'DELETE' or new.starts_at > now() or new.ends_at is not null) then
    -- Serializa mudanças de proprietária na mesma organização (duas ao mesmo tempo
    -- não encerram uma a outra)
    perform 1 from public.organizations o where o.id = old.organization_id for no key update;
    if not exists (
      select 1
      from public.memberships m
      join public.profiles p on p.id = m.profile_id
      where m.organization_id = old.organization_id
        and m.id <> old.id
        and m.role = 'owner'
        and m.store_id is null
        and m.starts_at <= now()
        and m.ends_at is null
        and p.status = 'active'
    ) then
      raise exception 'last_owner'
        using errcode = '23514',
              detail = 'A organização precisa de ao menos uma proprietária vigente: cadastre outra antes de encerrar este vínculo.';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

comment on function private.protect_last_owner() is
  'Gatilho BEFORE UPDATE OF starts_at, ends_at / DELETE em memberships: recusa (last_owner) encerrar, adiar ou apagar o último vínculo vigente de proprietária da organização.';

revoke all on function private.protect_last_owner() from public, anon;

create trigger memberships_protect_last_owner
  before update of starts_at, ends_at or delete on public.memberships
  for each row execute function private.protect_last_owner();

-- -----------------------------------------------------------------------------
-- sectors: responsável da loja (ou de rede na organização)
-- -----------------------------------------------------------------------------
create function private.validate_sector_responsible()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null
     and not (new.store_id = any (private.current_store_ids('{owner,manager,admin}'::public.membership_role[]))) then
    perform private.raise_rls_violation('sectors');
  end if;

  if new.responsible_id is not null
     and (tg_op = 'INSERT'
          or new.responsible_id is distinct from old.responsible_id
          or new.store_id is distinct from old.store_id)
     and not private.is_member_of(
       new.responsible_id,
       (select s.organization_id from public.stores s where s.id = new.store_id),
       new.store_id,
       true
     ) then
    raise exception 'invalid_responsible'
      using errcode = '23514',
            detail = 'O responsável precisa ter vínculo na loja do setor (ou de rede na organização).';
  end if;
  return new;
end;
$$;

comment on function private.validate_sector_responsible() is
  'Gatilho BEFORE INSERT/UPDATE em sectors: pela API só gerente da loja, proprietária e admin passam (os demais recebem o erro da RLS antes de qualquer consulta); responsável com vínculo não encerrado na loja (ou de rede na organização).';

revoke all on function private.validate_sector_responsible() from public, anon;

create trigger sectors_validate_responsible
  before insert or update of responsible_id, store_id on public.sectors
  for each row execute function private.validate_sector_responsible();

-- -----------------------------------------------------------------------------
-- task_templates: imagem de referência no caminho da própria rotina
-- -----------------------------------------------------------------------------
create function private.validate_template_reference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.reference_image_path is not null
     and not private.is_reference_path(new.reference_image_path, new.organization_id, new.store_id, array[new.id]) then
    raise exception 'invalid_reference_path'
      using errcode = '23514',
            detail = 'A imagem de referência precisa estar em {organização}/{loja ou rede}/{id da rotina}/{uuid}.{jpg|png|webp}.';
  end if;
  return new;
end;
$$;

comment on function private.validate_template_reference() is
  'Gatilho BEFORE INSERT/UPDATE em task_templates: reference_image_path só no caminho da própria rotina (organização, loja ou rede, id da rotina).';

revoke all on function private.validate_template_reference() from public, anon;

create trigger task_templates_validate_reference
  before insert or update of reference_image_path, organization_id, store_id on public.task_templates
  for each row execute function private.validate_template_reference();

-- -----------------------------------------------------------------------------
-- schedules: responsável com vínculo na loja
-- -----------------------------------------------------------------------------
create function private.validate_schedule_assignee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null
     and not (new.store_id = any (private.current_store_ids('{manager,owner}'::public.membership_role[]))) then
    perform private.raise_rls_violation('schedules');
  end if;

  if new.assignee_id is not null
     and (tg_op = 'INSERT'
          or new.assignee_id is distinct from old.assignee_id
          or new.store_id is distinct from old.store_id)
     and not private.can_be_assignee(
       new.assignee_id,
       (select s.organization_id from public.stores s where s.id = new.store_id),
       new.store_id
     ) then
    raise exception 'invalid_assignee'
      using errcode = '23514',
            detail = 'O responsável precisa ser colaborador ativo da loja do agendamento.';
  end if;
  return new;
end;
$$;

comment on function private.validate_schedule_assignee() is
  'Gatilho BEFORE INSERT/UPDATE em schedules: pela API só gerente da loja ou proprietária passam (os demais recebem o erro da RLS antes de qualquer consulta); responsável fixo precisa ser colaborador ativo com vínculo não encerrado na loja (private.can_be_assignee).';

revoke all on function private.validate_schedule_assignee() from public, anon;

create trigger schedules_validate_assignee
  before insert or update of assignee_id, store_id on public.schedules
  for each row execute function private.validate_schedule_assignee();

-- -----------------------------------------------------------------------------
-- tasks: rotina, versão, snapshot, responsável e imagem de referência coerentes
-- -----------------------------------------------------------------------------
create function private.validate_task_references()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_template public.task_templates%rowtype;
  v_scope_changed boolean := tg_op = 'UPDATE'
    and (new.store_id is distinct from old.store_id or new.organization_id is distinct from old.organization_id);
begin
  -- Pela API, só gerente da loja ou proprietária gravam tarefas: os demais recebem o erro
  -- da RLS antes de qualquer consulta (organização diferente da loja também)
  if auth.uid() is not null
     and not (new.store_id = any (private.current_store_ids('{manager,owner}'::public.membership_role[]))
              and new.organization_id = private.current_org_id()) then
    perform private.raise_rls_violation('tasks');
  end if;

  if new.template_id is not null
     and (tg_op = 'INSERT' or v_scope_changed
          or new.template_id is distinct from old.template_id
          or new.template_version is distinct from old.template_version) then
    -- FOR SHARE: a versão lida não muda até o fim da transação
    select * into v_template from public.task_templates t where t.id = new.template_id for share;
    if not found
       or v_template.organization_id <> new.organization_id
       or (v_template.store_id is not null and v_template.store_id <> new.store_id) then
      raise exception 'invalid_template'
        using errcode = '23514',
              detail = 'A rotina da tarefa precisa ser da mesma organização e da rede ou da mesma loja.';
    end if;

    if tg_op = 'INSERT' then
      -- Snapshot fiel: tarefa nova a partir de rotina copia a versão ATUAL dela (as
      -- anteriores não são guardadas, então não há como conferir outra)
      if new.template_version is distinct from v_template.version then
        raise exception 'invalid_template_version'
          using errcode = '23514',
                detail = 'Tarefa nova a partir de rotina usa a versão atual da rotina.';
      end if;
      if (new.requires_photo, new.requires_note, new.requires_approval, new.weight)
         is distinct from
         (v_template.requires_photo, v_template.requires_note, v_template.requires_approval, v_template.weight) then
        raise exception 'invalid_snapshot'
          using errcode = '23514',
                detail = 'Exigências (foto, observação, aprovação) e peso da tarefa precisam ser os da rotina.';
      end if;
    elsif new.template_version is not null
          and (new.template_version < 1 or new.template_version > v_template.version) then
      raise exception 'invalid_template_version'
        using errcode = '23514',
              detail = 'A versão do snapshot precisa ser uma versão existente da rotina.';
    end if;
  end if;

  if new.assignee_id is not null
     and (tg_op = 'INSERT' or v_scope_changed or new.assignee_id is distinct from old.assignee_id)
     and not private.can_be_assignee(new.assignee_id, new.organization_id, new.store_id) then
    raise exception 'invalid_assignee'
      using errcode = '23514',
            detail = 'O responsável precisa ser colaborador ativo da loja da tarefa.';
  end if;

  if new.reference_image_path is not null
     and (tg_op = 'INSERT' or v_scope_changed
          or new.reference_image_path is distinct from old.reference_image_path)
     and not private.is_reference_path(
       new.reference_image_path, new.organization_id, new.store_id, array[new.template_id, new.id]
     ) then
    raise exception 'invalid_reference_path'
      using errcode = '23514',
            detail = 'A imagem de referência precisa ser da organização e da loja (ou rede) da tarefa.';
  end if;

  return new;
end;
$$;

comment on function private.validate_task_references() is
  'Gatilho BEFORE INSERT/UPDATE em tasks: pela API só quem pode gravar na loja passa (os demais recebem o erro da RLS antes de qualquer consulta); rotina da mesma organização (rede ou mesma loja); tarefa nova a partir de rotina usa a versão atual e as mesmas exigências e peso (invalid_template_version, invalid_snapshot); responsável colaborador ativo com vínculo não encerrado na loja (private.can_be_assignee); imagem de referência da própria organização/loja.';

revoke all on function private.validate_task_references() from public, anon;

create trigger tasks_validate_references
  before insert or update of organization_id, store_id, template_id, template_version, assignee_id, reference_image_path
  on public.tasks
  for each row execute function private.validate_task_references();

-- -----------------------------------------------------------------------------
-- task_items: linhagem só da rotina da própria tarefa; snapshot do item de rotina
-- -----------------------------------------------------------------------------
create function private.validate_task_item_lineage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.template_items%rowtype;
begin
  if auth.uid() is not null and not private.can_manage_pending_task(new.task_id) then
    perform private.raise_rls_violation('task_items');
  end if;

  if new.template_item_id is not null
     and (tg_op = 'INSERT'
          or new.template_item_id is distinct from old.template_item_id
          or new.task_id is distinct from old.task_id)
     and not exists (
       select 1
       from public.template_items ti
       join public.tasks t on t.template_id = ti.template_id
       where ti.id = new.template_item_id
         and t.id = new.task_id
     ) then
    raise exception 'invalid_template_item'
      using errcode = '23514',
            detail = 'O item de origem precisa ser da rotina da própria tarefa.';
  end if;

  -- Item com linhagem copia o item da rotina: texto, crítico, foto e peso não são
  -- escolhidos nem reescritos à mão (D48, D75). Outro checklist = editar a rotina (auditado,
  -- sobe a versão) ou criar tarefa avulsa.
  if new.template_item_id is not null
     and (tg_op = 'INSERT'
          or new.template_item_id is distinct from old.template_item_id
          or (new.text, new.is_critical, new.requires_photo, new.weight)
             is distinct from (old.text, old.is_critical, old.requires_photo, old.weight)) then
    select * into v_item from public.template_items ti where ti.id = new.template_item_id;
    if (new.text, new.is_critical, new.requires_photo, new.weight)
       is distinct from (v_item.text, v_item.is_critical, v_item.requires_photo, v_item.weight) then
      raise exception 'invalid_snapshot'
        using errcode = '23514',
              detail = 'Item criado a partir de item de rotina usa o mesmo texto, crítico, foto e peso do item da rotina.';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.validate_task_item_lineage() is
  'Gatilho BEFORE INSERT/UPDATE em task_items: pela API só quem pode alterar a tarefa pendente passa (os demais recebem o erro da RLS antes de qualquer consulta); template_item_id precisa ser item da rotina da tarefa e o item copia texto, crítico, foto e peso do item da rotina (invalid_snapshot).';

revoke all on function private.validate_task_item_lineage() from public, anon;

create trigger task_items_validate_lineage
  before insert or update of task_id, template_item_id, text, is_critical, requires_photo, weight on public.task_items
  for each row execute function private.validate_task_item_lineage();

-- -----------------------------------------------------------------------------
-- action_plans: item de rotina da organização/loja; responsável com vínculo
-- -----------------------------------------------------------------------------
create function private.validate_action_plan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_template public.task_templates%rowtype;
  v_store_changed boolean := tg_op = 'UPDATE' and new.store_id is distinct from old.store_id;
begin
  if auth.uid() is not null
     and not (new.store_id = any (private.current_store_ids('{manager,owner}'::public.membership_role[]))) then
    perform private.raise_rls_violation('action_plans');
  end if;

  select s.organization_id into v_org from public.stores s where s.id = new.store_id;

  if tg_op = 'INSERT' or v_store_changed or new.template_item_id is distinct from old.template_item_id then
    select t.* into v_template
    from public.template_items ti
    join public.task_templates t on t.id = ti.template_id
    where ti.id = new.template_item_id;
    if not found
       or v_template.organization_id is distinct from v_org
       or (v_template.store_id is not null and v_template.store_id <> new.store_id) then
      raise exception 'invalid_template_item'
        using errcode = '23514',
              detail = 'O item do plano precisa ser de uma rotina da rede ou da própria loja.';
    end if;
  end if;

  -- Responsável: gerente ou colaborador da loja, ou a proprietária. Admin nunca (D15: não
  -- lê dado operacional direto, e o responsável lê o próprio plano)
  if new.owner_id is not null
     and (tg_op = 'INSERT' or v_store_changed or new.owner_id is distinct from old.owner_id)
     and not exists (
       select 1
       from public.memberships m
       where m.profile_id = new.owner_id
         and m.organization_id = v_org
         and (m.ends_at is null or m.ends_at > now())
         and (
           (m.store_id = new.store_id and m.role in ('manager', 'staff'))
           or (m.store_id is null and m.role = 'owner')
         )
     ) then
    raise exception 'invalid_owner'
      using errcode = '23514',
            detail = 'O responsável pelo plano precisa ser gerente ou colaborador da loja, ou a proprietária.';
  end if;

  return new;
end;
$$;

comment on function private.validate_action_plan() is
  'Gatilho BEFORE INSERT/UPDATE em action_plans: pela API só gerente da loja ou proprietária passam (os demais recebem o erro da RLS antes de qualquer consulta); item de rotina da rede ou da própria loja; responsável com vínculo não encerrado de gerente/colaborador na loja ou de proprietária (admin nunca).';

revoke all on function private.validate_action_plan() from public, anon;

create trigger action_plans_validate
  before insert or update of store_id, template_item_id, owner_id on public.action_plans
  for each row execute function private.validate_action_plan();

-- -----------------------------------------------------------------------------
-- created_by: sempre quem está logado (nulo = sistema); não muda depois.
-- Nem a chave secreta informa o autor: sem usuário logado, o autor é o sistema.
-- -----------------------------------------------------------------------------
create function private.stamp_created_by()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    new.created_by := old.created_by;
    return new;
  end if;

  new.created_by := (select p.id from public.profiles p where p.id = auth.uid());
  return new;
end;
$$;

comment on function private.stamp_created_by() is
  'Gatilho BEFORE INSERT/UPDATE OF created_by: grava como autor o usuário logado (sem usuário = sistema, nulo; o valor informado é ignorado) e nunca deixa o autor mudar.';

revoke all on function private.stamp_created_by() from public, anon;

create trigger task_templates_stamp_created_by
  before insert or update of created_by on public.task_templates
  for each row execute function private.stamp_created_by();

create trigger schedules_stamp_created_by
  before insert or update of created_by on public.schedules
  for each row execute function private.stamp_created_by();

create trigger tasks_stamp_created_by
  before insert or update of created_by on public.tasks
  for each row execute function private.stamp_created_by();

create trigger action_plans_stamp_created_by
  before insert or update of created_by on public.action_plans
  for each row execute function private.stamp_created_by();

-- -----------------------------------------------------------------------------
-- data_requests: quem concluiu e quando são gravados pelo sistema
-- -----------------------------------------------------------------------------
create function private.stamp_data_request_resolution()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resolved boolean := new.status in ('done', 'rejected');
begin
  if tg_op = 'UPDATE' and v_resolved and new.status = old.status then
    -- Já concluído: autor e data da conclusão não mudam
    new.resolved_by := old.resolved_by;
    new.resolved_at := old.resolved_at;
  elsif v_resolved then
    new.resolved_by := (select p.id from public.profiles p where p.id = auth.uid());
    new.resolved_at := now();
  else
    new.resolved_by := null;
    new.resolved_at := null;
  end if;
  return new;
end;
$$;

comment on function private.stamp_data_request_resolution() is
  'Gatilho BEFORE INSERT/UPDATE em data_requests: ao virar done/rejected grava resolved_by = usuário logado (nulo = sistema) e resolved_at = agora; fora disso, ambos nulos. Ninguém informa o autor da conclusão.';

revoke all on function private.stamp_data_request_resolution() from public, anon;

create trigger data_requests_stamp_resolution
  before insert or update on public.data_requests
  for each row execute function private.stamp_data_request_resolution();
