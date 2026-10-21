-- =============================================================================
-- RLS: rotinas, itens de rotina, agendamentos, tarefas e itens de tarefa.
--   staff  : só tarefas atribuídas a si ou à equipe do seu setor, em loja com
--            vínculo vigente (sem escrita direta; executa via RPC)
--   manager: tudo da própria loja (+ rotinas da rede em leitura)
--   owner  : tudo da organização
--   admin  : sem SELECT direto (lê por admin_read_*, auditado)
-- Tarefas não têm DELETE (cancelar com motivo via cancel_task). O status só
-- muda pelas RPCs (privilégios de coluna em outra migration).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- task_templates
-- -----------------------------------------------------------------------------
create policy task_templates_select_manager_owner on public.task_templates
  for select to authenticated
  using (
    organization_id = (select private.current_org_id())
    and (
      store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[])
      or (
        store_id is null
        and cardinality((select private.current_store_ids('{manager,owner}'::public.membership_role[]))) > 0
      )
    )
  );

create policy task_templates_insert_manager_owner on public.task_templates
  for insert to authenticated
  with check (
    organization_id = (select private.current_org_id())
    and (
      store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[])
      or (store_id is null and (select private.is_owner()))
    )
  );

create policy task_templates_update_manager_owner on public.task_templates
  for update to authenticated
  using (
    organization_id = (select private.current_org_id())
    and (
      store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[])
      or (store_id is null and (select private.is_owner()))
    )
  )
  with check (
    organization_id = (select private.current_org_id())
    and (
      store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[])
      or (store_id is null and (select private.is_owner()))
    )
  );

create policy task_templates_delete_manager_owner on public.task_templates
  for delete to authenticated
  using (
    organization_id = (select private.current_org_id())
    and (
      store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[])
      or (store_id is null and (select private.is_owner()))
    )
  );

comment on policy task_templates_select_manager_owner on public.task_templates is
  'Gerente lê as rotinas da sua loja e as da rede; proprietária lê todas.';
comment on policy task_templates_insert_manager_owner on public.task_templates is
  'Gerente cria rotinas da sua loja; proprietária cria rotinas de qualquer loja e da rede.';
comment on policy task_templates_update_manager_owner on public.task_templates is
  'Gerente altera rotinas da sua loja; proprietária altera todas (inclusive as da rede).';
comment on policy task_templates_delete_manager_owner on public.task_templates is
  'Remove rotina nunca usada (com tarefas ou agendamentos, a FK impede; desative).';

-- -----------------------------------------------------------------------------
-- template_items: visíveis com a rotina; escrita por quem pode alterar a rotina
-- -----------------------------------------------------------------------------
create policy template_items_select_with_template on public.template_items
  for select to authenticated
  using (exists (select 1 from public.task_templates t where t.id = template_items.template_id));

create policy template_items_insert_manager_owner on public.template_items
  for insert to authenticated
  with check ((select private.can_manage_template(template_id)));

create policy template_items_update_manager_owner on public.template_items
  for update to authenticated
  using ((select private.can_manage_template(template_id)))
  with check ((select private.can_manage_template(template_id)));

create policy template_items_delete_manager_owner on public.template_items
  for delete to authenticated
  using ((select private.can_manage_template(template_id)));

comment on policy template_items_select_with_template on public.template_items is
  'Itens visíveis para quem vê a rotina.';
comment on policy template_items_insert_manager_owner on public.template_items is
  'Quem pode alterar a rotina inclui itens.';
comment on policy template_items_update_manager_owner on public.template_items is
  'Quem pode alterar a rotina altera itens (tarefas já geradas não mudam).';
comment on policy template_items_delete_manager_owner on public.template_items is
  'Quem pode alterar a rotina remove itens (o snapshot nas tarefas permanece).';

-- -----------------------------------------------------------------------------
-- schedules: gerente da loja e proprietária
-- -----------------------------------------------------------------------------
create policy schedules_select_manager_owner on public.schedules
  for select to authenticated
  using (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]));

create policy schedules_insert_manager_owner on public.schedules
  for insert to authenticated
  with check (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]));

create policy schedules_update_manager_owner on public.schedules
  for update to authenticated
  using (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]))
  with check (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]));

create policy schedules_delete_manager_owner on public.schedules
  for delete to authenticated
  using (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]));

comment on policy schedules_select_manager_owner on public.schedules is 'Gerente lê os agendamentos da sua loja; proprietária, todos.';
comment on policy schedules_insert_manager_owner on public.schedules is 'Gerente cria agendamentos da sua loja; proprietária, de qualquer loja.';
comment on policy schedules_update_manager_owner on public.schedules is 'Gerente altera agendamentos da sua loja; proprietária, de qualquer loja.';
comment on policy schedules_delete_manager_owner on public.schedules is
  'Remove agendamento nunca usado (com tarefas geradas, a FK impede; desative).';

-- -----------------------------------------------------------------------------
-- tasks
-- -----------------------------------------------------------------------------
create policy tasks_select_manager_owner on public.tasks
  for select to authenticated
  using (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]));

create policy tasks_select_staff on public.tasks
  for select to authenticated
  using (
    store_id = any ((select private.current_store_ids('{staff}'::public.membership_role[]))::uuid[])
    and (
      assignee_id = (select auth.uid())
      or (assignee_id is null and sector_id = any ((select private.current_sector_ids())::uuid[]))
    )
  );

create policy tasks_insert_manager_owner on public.tasks
  for insert to authenticated
  with check (
    store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[])
    and (created_by is null or created_by = (select auth.uid()))
  );

create policy tasks_update_manager_owner on public.tasks
  for update to authenticated
  using (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]))
  with check (store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[]));

comment on policy tasks_select_manager_owner on public.tasks is 'Gerente lê as tarefas da sua loja; proprietária, todas.';
comment on policy tasks_select_staff on public.tasks is
  'Colaborador lê as tarefas atribuídas a si ou à equipe do seu setor, só em loja com vínculo vigente.';
comment on policy tasks_insert_manager_owner on public.tasks is
  'Gerente cria tarefas avulsas na sua loja; proprietária, em qualquer loja. Sempre nascem pending.';
comment on policy tasks_update_manager_owner on public.tasks is
  'Gerente/proprietária ajustam dados da tarefa (título, prazo, responsável...). Status só via RPC.';

-- -----------------------------------------------------------------------------
-- task_items: visíveis com a tarefa; editáveis só antes da primeira tentativa
-- -----------------------------------------------------------------------------
create policy task_items_select_with_task on public.task_items
  for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_items.task_id));

create policy task_items_insert_manager_owner on public.task_items
  for insert to authenticated
  with check ((select private.can_manage_pending_task(task_id)));

create policy task_items_update_manager_owner on public.task_items
  for update to authenticated
  using ((select private.can_manage_pending_task(task_id)))
  with check ((select private.can_manage_pending_task(task_id)));

create policy task_items_delete_manager_owner on public.task_items
  for delete to authenticated
  using ((select private.can_manage_pending_task(task_id)));

comment on policy task_items_select_with_task on public.task_items is 'Itens visíveis para quem vê a tarefa.';
comment on policy task_items_insert_manager_owner on public.task_items is
  'Gerente/proprietária incluem itens em tarefa pendente ainda não iniciada.';
comment on policy task_items_update_manager_owner on public.task_items is
  'Gerente/proprietária alteram itens de tarefa pendente ainda não iniciada.';
comment on policy task_items_delete_manager_owner on public.task_items is
  'Gerente/proprietária removem itens de tarefa pendente ainda não iniciada.';
