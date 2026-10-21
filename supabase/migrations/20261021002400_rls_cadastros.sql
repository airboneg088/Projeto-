-- =============================================================================
-- RLS: organização, lojas, configurações, setores, perfis e vínculos
-- (docs/modelo-de-dados.md §6). A RLS já está ligada desde a criação de cada
-- tabela; aqui entram as policies. anon não recebe nenhuma policy.
-- Funções auxiliares sempre dentro de (select ...) para avaliar uma vez.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- organizations: membros leem a própria; admin altera
-- -----------------------------------------------------------------------------
create policy organizations_select_member on public.organizations
  for select to authenticated
  using (id = (select private.current_org_id()));

create policy organizations_update_admin on public.organizations
  for update to authenticated
  using (id = (select private.current_org_id()) and (select private.is_admin()))
  with check (id = (select private.current_org_id()) and (select private.is_admin()));

comment on policy organizations_select_member on public.organizations is
  'Quem tem vínculo vigente lê a própria organização.';
comment on policy organizations_update_admin on public.organizations is
  'Admin altera dados da organização (ex.: retenção de fotos).';

-- -----------------------------------------------------------------------------
-- stores: cada um lê as lojas do seu vínculo vigente; admin cria e altera
-- -----------------------------------------------------------------------------
create policy stores_select_member on public.stores
  for select to authenticated
  using (id = any ((select private.current_store_ids('{owner,manager,staff,admin}'::public.membership_role[]))::uuid[]));

create policy stores_insert_admin on public.stores
  for insert to authenticated
  with check (organization_id = (select private.current_org_id()) and (select private.is_admin()));

create policy stores_update_admin on public.stores
  for update to authenticated
  using (id = any ((select private.current_store_ids('{admin}'::public.membership_role[]))::uuid[]))
  with check (organization_id = (select private.current_org_id()) and (select private.is_admin()));

comment on policy stores_select_member on public.stores is
  'Colaborador e gerente leem as lojas do vínculo vigente; proprietária e admin, todas da organização.';
comment on policy stores_insert_admin on public.stores is 'Admin cadastra lojas na própria organização.';
comment on policy stores_update_admin on public.stores is 'Admin altera lojas da própria organização.';

-- -----------------------------------------------------------------------------
-- store_settings: gerente lê; proprietária e admin leem e alteram
-- (a linha é criada por gatilho junto com a loja)
-- -----------------------------------------------------------------------------
create policy store_settings_select on public.store_settings
  for select to authenticated
  using (store_id = any ((select private.current_store_ids('{owner,manager,admin}'::public.membership_role[]))::uuid[]));

create policy store_settings_update_owner_admin on public.store_settings
  for update to authenticated
  using (store_id = any ((select private.current_store_ids('{owner,admin}'::public.membership_role[]))::uuid[]))
  with check (store_id = any ((select private.current_store_ids('{owner,admin}'::public.membership_role[]))::uuid[]));

comment on policy store_settings_select on public.store_settings is 'Gerente da loja, proprietária e admin leem as configurações.';
comment on policy store_settings_update_owner_admin on public.store_settings is 'Proprietária e admin alteram as configurações da loja.';

-- -----------------------------------------------------------------------------
-- sectors: membros da loja leem; gerente (sua loja), proprietária e admin escrevem
-- -----------------------------------------------------------------------------
create policy sectors_select_member on public.sectors
  for select to authenticated
  using (store_id = any ((select private.current_store_ids('{owner,manager,staff,admin}'::public.membership_role[]))::uuid[]));

create policy sectors_insert_manager on public.sectors
  for insert to authenticated
  with check (store_id = any ((select private.current_store_ids('{owner,manager,admin}'::public.membership_role[]))::uuid[]));

create policy sectors_update_manager on public.sectors
  for update to authenticated
  using (store_id = any ((select private.current_store_ids('{owner,manager,admin}'::public.membership_role[]))::uuid[]))
  with check (store_id = any ((select private.current_store_ids('{owner,manager,admin}'::public.membership_role[]))::uuid[]));

create policy sectors_delete_manager on public.sectors
  for delete to authenticated
  using (store_id = any ((select private.current_store_ids('{owner,manager,admin}'::public.membership_role[]))::uuid[]));

comment on policy sectors_select_member on public.sectors is 'Quem tem vínculo vigente na loja lê os setores dela.';
comment on policy sectors_insert_manager on public.sectors is 'Gerente (sua loja), proprietária e admin criam setores.';
comment on policy sectors_update_manager on public.sectors is 'Gerente (sua loja), proprietária e admin alteram setores.';
comment on policy sectors_delete_manager on public.sectors is
  'Gerente (sua loja), proprietária e admin removem setores sem uso (com tarefas, a FK impede; desative).';

-- -----------------------------------------------------------------------------
-- profiles: o próprio; gerente vê a equipe; proprietária/admin, a organização.
-- A pessoa altera só o próprio nome (privilégio de coluna em outra migration).
-- -----------------------------------------------------------------------------
create policy profiles_select_visible on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or id = any ((select private.visible_profile_ids())::uuid[])
  );

-- Só com perfil ativo e vínculo vigente: quem foi desativado ou saiu não muda mais o
-- nome que aparece no histórico (correção depois disso: pedido do titular, data_requests)
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (
    id = (select auth.uid())
    and (select private.has_role('{owner,manager,staff,admin}'::public.membership_role[]))
  )
  with check (
    id = (select auth.uid())
    and (select private.has_role('{owner,manager,staff,admin}'::public.membership_role[]))
  );

comment on policy profiles_select_visible on public.profiles is
  'Lê o próprio perfil; gerente lê a equipe da loja; proprietária e admin leem as pessoas da organização.';
comment on policy profiles_update_self on public.profiles is
  'A pessoa altera o próprio perfil (só full_name, por privilégio de coluna), com perfil ativo e vínculo vigente. Situação muda via set_profile_status.';

-- -----------------------------------------------------------------------------
-- memberships: os próprios; gerente vê os da loja; proprietária e admin gerenciam
-- (sem DELETE: vínculo é encerrado com ends_at). No UPDATE só mudam setor e
-- período (privilégio de coluna): troca de papel ou de loja = encerrar e abrir.
-- private.can_manage_membership: proprietária pode tudo; admin só cuida de
-- vínculos de gerente e colaborador (vínculo de proprietária e de admin só a
-- proprietária altera), nunca o próprio (D15: não se dá acesso operacional) e
-- não dá papel operacional a quem tem papel de rede.
-- -----------------------------------------------------------------------------
create policy memberships_select_visible on public.memberships
  for select to authenticated
  using (
    profile_id = (select auth.uid())
    or store_id = any ((select private.current_store_ids('{manager}'::public.membership_role[]))::uuid[])
    or (
      organization_id = (select private.current_org_id())
      and ((select private.is_owner()) or (select private.is_admin()))
    )
  );

create policy memberships_insert_owner_admin on public.memberships
  for insert to authenticated
  with check (
    organization_id = (select private.current_org_id())
    and private.can_manage_membership(profile_id, role)
  );

-- USING e WITH CHECK iguais: a linha atual (inclusive um vínculo de proprietária)
-- também precisa estar ao alcance de quem altera, não só a linha nova
create policy memberships_update_owner_admin on public.memberships
  for update to authenticated
  using (
    organization_id = (select private.current_org_id())
    and private.can_manage_membership(profile_id, role)
  )
  with check (
    organization_id = (select private.current_org_id())
    and private.can_manage_membership(profile_id, role)
  );

comment on policy memberships_select_visible on public.memberships is
  'Lê os próprios vínculos; gerente lê os da sua loja; proprietária e admin, todos da organização.';
comment on policy memberships_insert_owner_admin on public.memberships is
  'Proprietária e admin criam vínculos (transferência = encerrar e abrir outro). Só a proprietária cria vínculo de proprietária ou de admin; admin cria vínculos de gerente e colaborador, nunca para si nem para quem tem papel de rede.';
comment on policy memberships_update_owner_admin on public.memberships is
  'Proprietária e admin alteram setor/período e encerram vínculos. Só a proprietária mexe em vínculo de proprietária ou de admin (encerrar, estender, reabrir); admin só em vínculos de gerente e colaborador, nunca no próprio.';
