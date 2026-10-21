-- Desfaz 20261021002600_rls_execucao_e_revisao.sql.

drop policy review_item_flags_select_with_review on public.review_item_flags;
drop policy reviews_select_with_task on public.reviews;
drop policy evidences_select_with_attempt on public.evidences;
drop policy attempt_item_answers_select_with_attempt on public.attempt_item_answers;
drop policy task_attempts_select on public.task_attempts;
