-- =============================================================================
-- Índices para FKs, policies de RLS e consultas frequentes
-- (as constraints UNIQUE/PK/EXCLUDE já criam os seus próprios índices).
-- =============================================================================

create index stores_organization_id_idx on public.stores (organization_id);
create index sectors_responsible_id_idx on public.sectors (responsible_id);

create index memberships_profile_id_idx on public.memberships (profile_id);
create index memberships_organization_id_idx on public.memberships (organization_id);
create index memberships_store_id_idx on public.memberships (store_id);
create index memberships_sector_id_idx on public.memberships (sector_id);

create index task_templates_organization_store_idx on public.task_templates (organization_id, store_id);
create index task_templates_store_id_idx on public.task_templates (store_id);
create index task_templates_created_by_idx on public.task_templates (created_by);

create index schedules_store_id_idx on public.schedules (store_id);
create index schedules_template_id_idx on public.schedules (template_id);
create index schedules_sector_id_idx on public.schedules (sector_id);
create index schedules_assignee_id_idx on public.schedules (assignee_id);
create index schedules_created_by_idx on public.schedules (created_by);

create index tasks_store_due_at_idx on public.tasks (store_id, due_at);
create index tasks_organization_id_idx on public.tasks (organization_id);
create index tasks_sector_id_idx on public.tasks (sector_id);
create index tasks_assignee_id_idx on public.tasks (assignee_id);
create index tasks_template_id_idx on public.tasks (template_id);
create index tasks_status_due_at_idx on public.tasks (status, due_at);
create index tasks_created_by_idx on public.tasks (created_by);
create index tasks_cancelled_by_idx on public.tasks (cancelled_by);

create index task_items_template_item_id_idx on public.task_items (template_item_id);

create index task_attempts_store_id_idx on public.task_attempts (store_id);
create index task_attempts_performed_by_idx on public.task_attempts (performed_by);

create index attempt_item_answers_task_item_id_idx on public.attempt_item_answers (task_item_id);
create index attempt_item_answers_task_id_idx on public.attempt_item_answers (task_id);
-- Reenvio de resposta (answer_item): busca o id em todas as respostas já aplicadas
create index attempt_item_answers_applied_mutation_ids_idx on public.attempt_item_answers
  using gin (applied_mutation_ids);

create index evidences_attempt_id_idx on public.evidences (attempt_id);
create index evidences_task_id_idx on public.evidences (task_id);
create index evidences_task_item_id_idx on public.evidences (task_item_id);
create index evidences_store_id_idx on public.evidences (store_id);
create index evidences_organization_received_idx on public.evidences (organization_id, received_at_server);
create index evidences_similar_to_id_idx on public.evidences (similar_to_id);

create index reviews_task_id_idx on public.reviews (task_id);
create index reviews_reviewer_id_idx on public.reviews (reviewer_id);

create index review_item_flags_task_item_id_idx on public.review_item_flags (task_item_id);
create index review_item_flags_task_id_idx on public.review_item_flags (task_id);

create index action_plans_template_item_id_idx on public.action_plans (template_item_id);
create index action_plans_owner_id_idx on public.action_plans (owner_id);
create index action_plans_created_by_idx on public.action_plans (created_by);

create index notifications_recipient_read_idx on public.notifications (recipient_id, read_at);
create index notifications_store_id_idx on public.notifications (store_id);
create index notifications_task_id_idx on public.notifications (task_id);

create index data_requests_organization_id_idx on public.data_requests (organization_id);
create index data_requests_profile_id_idx on public.data_requests (profile_id);
create index data_requests_resolved_by_idx on public.data_requests (resolved_by);

create index audit_log_organization_occurred_idx on public.audit_log (organization_id, occurred_at desc);
create index audit_log_actor_id_idx on public.audit_log (actor_id);
create index audit_log_table_record_idx on public.audit_log (table_name, record_id);
