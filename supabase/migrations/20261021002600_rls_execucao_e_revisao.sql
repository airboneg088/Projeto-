-- =============================================================================
-- RLS: tentativas, respostas, evidências, revisões e itens reprovados.
-- Só leitura pela API; escrita exclusivamente pelas funções RPC
-- (os privilégios de INSERT/UPDATE/DELETE são revogados em outra migration).
--   staff  : as próprias tentativas (com respostas e evidências) e as revisões
--            das tarefas que vê
--   manager: tudo da própria loja
--   owner  : tudo da organização
--   admin  : nada direto
-- =============================================================================

create policy task_attempts_select on public.task_attempts
  for select to authenticated
  using (
    store_id = any ((select private.current_store_ids('{manager,owner}'::public.membership_role[]))::uuid[])
    or (
      performed_by = (select auth.uid())
      and store_id = any ((select private.current_store_ids('{staff}'::public.membership_role[]))::uuid[])
    )
  );

comment on policy task_attempts_select on public.task_attempts is
  'Gerente lê as tentativas da sua loja; proprietária, todas; colaborador, as próprias (em loja com vínculo vigente).';

create policy attempt_item_answers_select_with_attempt on public.attempt_item_answers
  for select to authenticated
  using (exists (select 1 from public.task_attempts a where a.id = attempt_item_answers.attempt_id));

comment on policy attempt_item_answers_select_with_attempt on public.attempt_item_answers is
  'Respostas visíveis para quem vê a tentativa.';

create policy evidences_select_with_attempt on public.evidences
  for select to authenticated
  using (exists (select 1 from public.task_attempts a where a.id = evidences.attempt_id));

comment on policy evidences_select_with_attempt on public.evidences is
  'Evidências visíveis para quem vê a tentativa (executor, gerente da loja, proprietária).';

create policy reviews_select_with_task on public.reviews
  for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = reviews.task_id));

comment on policy reviews_select_with_task on public.reviews is
  'Revisões visíveis para quem vê a tarefa (colaborador: das suas tarefas; gerente: da loja; proprietária: todas).';

create policy review_item_flags_select_with_review on public.review_item_flags
  for select to authenticated
  using (exists (select 1 from public.reviews r where r.id = review_item_flags.review_id));

comment on policy review_item_flags_select_with_review on public.review_item_flags is
  'Itens reprovados visíveis para quem vê a revisão.';
