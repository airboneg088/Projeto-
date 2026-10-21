-- Desfaz 20261021001500_indices.sql.

drop index public.audit_log_table_record_idx;
drop index public.audit_log_actor_id_idx;
drop index public.audit_log_organization_occurred_idx;

drop index public.data_requests_resolved_by_idx;
drop index public.data_requests_profile_id_idx;
drop index public.data_requests_organization_id_idx;

drop index public.notifications_task_id_idx;
drop index public.notifications_store_id_idx;
drop index public.notifications_recipient_read_idx;

drop index public.action_plans_created_by_idx;
drop index public.action_plans_owner_id_idx;
drop index public.action_plans_template_item_id_idx;

drop index public.review_item_flags_task_id_idx;
drop index public.review_item_flags_task_item_id_idx;

drop index public.reviews_reviewer_id_idx;
drop index public.reviews_task_id_idx;

drop index public.evidences_similar_to_id_idx;
drop index public.evidences_organization_received_idx;
drop index public.evidences_store_id_idx;
drop index public.evidences_task_item_id_idx;
drop index public.evidences_task_id_idx;
drop index public.evidences_attempt_id_idx;

drop index public.attempt_item_answers_applied_mutation_ids_idx;
drop index public.attempt_item_answers_task_id_idx;
drop index public.attempt_item_answers_task_item_id_idx;

drop index public.task_attempts_performed_by_idx;
drop index public.task_attempts_store_id_idx;

drop index public.task_items_template_item_id_idx;

drop index public.tasks_cancelled_by_idx;
drop index public.tasks_created_by_idx;
drop index public.tasks_status_due_at_idx;
drop index public.tasks_template_id_idx;
drop index public.tasks_assignee_id_idx;
drop index public.tasks_sector_id_idx;
drop index public.tasks_organization_id_idx;
drop index public.tasks_store_due_at_idx;

drop index public.schedules_created_by_idx;
drop index public.schedules_assignee_id_idx;
drop index public.schedules_sector_id_idx;
drop index public.schedules_template_id_idx;
drop index public.schedules_store_id_idx;

drop index public.task_templates_created_by_idx;
drop index public.task_templates_store_id_idx;
drop index public.task_templates_organization_store_idx;

drop index public.memberships_sector_id_idx;
drop index public.memberships_store_id_idx;
drop index public.memberships_organization_id_idx;
drop index public.memberships_profile_id_idx;

drop index public.sectors_responsible_id_idx;
drop index public.stores_organization_id_idx;
