-- Desfaz 20261021001800_imutabilidade.sql.

drop trigger task_items_guard_change on public.task_items;
drop trigger tasks_forbid_delete on public.tasks;

drop trigger attempt_item_answers_forbid_truncate on public.attempt_item_answers;
drop trigger attempt_item_answers_guard_change on public.attempt_item_answers;
drop trigger task_attempts_forbid_truncate on public.task_attempts;
drop trigger task_attempts_guard_change on public.task_attempts;
drop trigger review_item_flags_forbid_truncate on public.review_item_flags;
drop trigger review_item_flags_forbid_change on public.review_item_flags;
drop trigger reviews_forbid_truncate on public.reviews;
drop trigger reviews_forbid_change on public.reviews;
drop trigger evidences_forbid_truncate on public.evidences;
drop trigger evidences_guard_change on public.evidences;
drop trigger audit_log_forbid_truncate on public.audit_log;
drop trigger audit_log_forbid_change on public.audit_log;

drop function private.guard_task_item_change();
drop function private.guard_answer_change();
drop function private.guard_attempt_change();
drop function private.guard_evidence_change();
drop function private.forbid_change();
