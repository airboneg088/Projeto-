-- =============================================================================
-- RLS: planos de ação, notificações, solicitações do titular e auditoria.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- action_plans: gerente (sua loja) e proprietária; responsável lê o seu (gerente,
-- colaborador ou proprietária; admin nunca: D15, lê operação só por admin_read_*)
-- -----------------------------------------------------------------------------
create policy action_plans_select on public.action_plans
  for select to authenticated
  using (
    store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[])
    or (
      owner_id = (select auth.uid())
      and store_id = any ((select private.current_store_ids('{owner,manager,staff}'::public.membership_role[]))::uuid[])
    )
  );

create policy action_plans_insert_manager_owner on public.action_plans
  for insert to authenticated
  with check (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]));

create policy action_plans_update_manager_owner on public.action_plans
  for update to authenticated
  using (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]))
  with check (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]));

comment on policy action_plans_select on public.action_plans is
  'Gerente lê os planos da sua loja; proprietária, todos; o responsável lê o seu.';
comment on policy action_plans_insert_manager_owner on public.action_plans is 'Gerente (sua loja) e proprietária criam planos.';
comment on policy action_plans_update_manager_owner on public.action_plans is 'Gerente (sua loja) e proprietária atualizam planos.';

-- -----------------------------------------------------------------------------
-- notifications: só as próprias, com perfil ativo e vínculo vigente (na loja da
-- notificação, quando ela é de uma loja); marcar como lida (privilégio só em read_at).
-- Quem perdeu o vínculo deixa de ler na hora (docs §6.4).
-- -----------------------------------------------------------------------------
create policy notifications_select_own on public.notifications
  for select to authenticated
  using (
    recipient_id = (select auth.uid())
    and (select private.has_role('{owner,manager,staff,admin}'::public.membership_role[]))
    and (
      store_id is null
      or store_id = any ((select private.current_store_ids('{owner,manager,staff,admin}'::public.membership_role[]))::uuid[])
    )
  );

create policy notifications_update_own on public.notifications
  for update to authenticated
  using (
    recipient_id = (select auth.uid())
    and (select private.has_role('{owner,manager,staff,admin}'::public.membership_role[]))
    and (
      store_id is null
      or store_id = any ((select private.current_store_ids('{owner,manager,staff,admin}'::public.membership_role[]))::uuid[])
    )
  )
  with check (recipient_id = (select auth.uid()));

comment on policy notifications_select_own on public.notifications is
  'Cada pessoa lê só as próprias notificações, com perfil ativo e vínculo vigente (na loja da notificação).';
comment on policy notifications_update_own on public.notifications is
  'A pessoa marca as próprias notificações como lidas (só read_at), com perfil ativo e vínculo vigente.';

-- -----------------------------------------------------------------------------
-- data_requests: titular lê e abre os seus; proprietária lê; admin lê e trata.
-- O titular abre pedido na organização dos vínculos que teve, mesmo depois de sair ou
-- de ter o perfil desativado (LGPD art. 18; D37, D78): private.home_org_id, não
-- current_org_id (que é nula sem vínculo vigente). Um pedido em andamento por tipo
-- (índice data_requests_one_open_per_kind, D76).
-- -----------------------------------------------------------------------------
create policy data_requests_select on public.data_requests
  for select to authenticated
  using (
    profile_id = (select auth.uid())
    or (
      organization_id = (select private.current_org_id())
      and ((select private.is_owner()) or (select private.is_admin()))
    )
  );

create policy data_requests_insert_own on public.data_requests
  for insert to authenticated
  with check (
    profile_id = (select auth.uid())
    and organization_id = (select private.home_org_id())
    and status = 'open'
    and resolution is null
    and resolved_by is null
    and resolved_at is null
  );

create policy data_requests_update_admin on public.data_requests
  for update to authenticated
  using (organization_id = (select private.current_org_id()) and (select private.is_admin()))
  with check (organization_id = (select private.current_org_id()) and (select private.is_admin()));

comment on policy data_requests_select on public.data_requests is
  'O titular lê os próprios pedidos; proprietária e admin leem os da organização.';
comment on policy data_requests_insert_own on public.data_requests is
  'O titular abre pedido em nome próprio, sempre como open, na organização dos vínculos que teve (inclusive depois de sair ou de ter o perfil desativado).';
comment on policy data_requests_update_admin on public.data_requests is
  'Admin trata os pedidos (situação e resolução). Quem concluiu e quando são gravados pelo sistema (gatilho), nunca informados.';

-- -----------------------------------------------------------------------------
-- audit_log (escrita só por SECURITY DEFINER):
--   proprietária: tudo da organização
--   admin: só cadastros e eventos; registros de tabelas operacionais (rotinas,
--          itens, agendamentos, tarefas e seus itens, tentativas, evidências) guardam conteúdo
--          operacional no diff, e o admin só lê operação por admin_read_* (D15)
-- -----------------------------------------------------------------------------
create policy audit_log_select_owner on public.audit_log
  for select to authenticated
  using (
    organization_id = (select private.current_org_id())
    and (select private.is_owner())
  );

create policy audit_log_select_admin on public.audit_log
  for select to authenticated
  using (
    organization_id = (select private.current_org_id())
    and (select private.is_admin())
    and (
      table_name is null
      or table_name not in ('task_templates', 'template_items', 'schedules', 'tasks', 'task_items', 'task_attempts', 'evidences')
    )
  );

comment on policy audit_log_select_owner on public.audit_log is
  'Proprietária lê toda a auditoria da organização. Ninguém insere, altera ou apaga pela API.';
comment on policy audit_log_select_admin on public.audit_log is
  'Admin lê a auditoria de cadastros e eventos da organização, sem registros de tabelas operacionais (D15: operação só por admin_read_*).';
