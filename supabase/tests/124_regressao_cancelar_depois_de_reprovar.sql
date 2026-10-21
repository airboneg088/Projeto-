-- =============================================================================
-- 124 · Regressão R2-REGRAS-01 (correção incompleta de R1-REGRAS-02, D28): o
-- gerente não apaga dos indicadores uma reprovação já registrada. Depois de
-- uma reprovação, o colaborador reinicia (rejected -> in_progress) e o status
-- volta a ser "em andamento"; mesmo assim, tarefa que já teve tentativa
-- enviada só a proprietária cancela (owner_only).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(7);

select tests.create_base_fixture();

insert into public.task_templates (id, organization_id, store_id, title, weight)
values (tests.fx('r2c_tpl'), tests.fx('org_a'), null, 'Fechamento do caixa', 5);
insert into public.template_items (id, template_id, position, text, is_critical)
values (tests.fx('r2c_ti1'), tests.fx('r2c_tpl'), 1, 'Sangria no cofre', true),
       (tests.fx('r2c_ti2'), tests.fx('r2c_tpl'), 2, 'Balcão limpo', false);

insert into public.tasks (id, organization_id, store_id, sector_id, template_id, template_version, title,
                          weight, assignee_id, window_start_at, due_at)
values (tests.fx('r2c_t'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), tests.fx('r2c_tpl'), 1,
        'Fechamento do caixa', 5, tests.fx('staff_p1'), now() - interval '1 hour', now() + interval '3 hours');
insert into public.task_items (id, task_id, template_item_id, position, text, is_critical)
values (tests.fx('r2c_t:i1'), tests.fx('r2c_t'), tests.fx('r2c_ti1'), 1, 'Sangria no cofre', true),
       (tests.fx('r2c_t:i2'), tests.fx('r2c_t'), tests.fx('r2c_ti2'), 2, 'Balcão limpo', false);
select tests.create_task('r2c_nova', 'store_p', 'sector_p1', 'staff_p1');

-- Colaborador executa e envia (tentativa 1)
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('r2c_t'), gen_random_uuid());
select public.answer_item(tests.attempt_of('r2c_t', 1), tests.fx('r2c_t:i1'), true);
select public.answer_item(tests.attempt_of('r2c_t', 1), tests.fx('r2c_t:i2'), true);
select public.submit_attempt(tests.attempt_of('r2c_t', 1), null, gen_random_uuid());

-- Gerente reprova marcando o item crítico
select tests.authenticate_as('manager_p');
select public.review_attempt(tests.attempt_of('r2c_t', 1), 'rejected', 'Sangria fora do cofre',
                             array[tests.fx('r2c_t:i1')]);

-- Colaborador começa a correção (rejected -> in_progress), como manda o fluxo
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('r2c_t'), gen_random_uuid());
select public.start_attempt(tests.fx('r2c_nova'), gen_random_uuid());

-- Gerente avaliado tenta cancelar antes do prazo
select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ select public.cancel_task(%L, 'Não precisa mais') $$, tests.fx('r2c_t')),
  'P0001', 'owner_only',
  'gerente não cancela tarefa que já foi enviada e reprovada (mesmo depois de reiniciada)'
);
select lives_ok(
  format($$ select public.cancel_task(%L, 'Não precisa mais') $$, tests.fx('r2c_nova')),
  'controle: gerente cancela tarefa em andamento que nunca foi enviada'
);

-- A falha continua nos indicadores (proprietária olhando o período)
select tests.authenticate_as('owner_a');
select is(
  (select devolvidas from public.kpi_summary(current_date - 2, current_date + 2)),
  1, 'kpi_summary.devolvidas mantém a reprovação');
select is(
  (select count(*)::int from public.top_failed_items(current_date - 2, current_date + 2)),
  1, 'top_failed_items mantém o item crítico reprovado');
select is(
  (select criticos_reprovados from public.weighted_scores(current_date - 2, current_date + 2, 'store')
    where group_id = tests.fx('store_p')),
  1, 'weighted_scores mantém o crítico reprovado da Loja P');
select is(
  (select status::text from public.tasks where id = tests.fx('r2c_t')),
  'in_progress', 'a tarefa continua em andamento (não cancelada pelo gerente)');
-- A proprietária pode
select lives_ok(
  format($$ select public.cancel_task(%L, 'Loja fechada') $$, tests.fx('r2c_t')),
  'a proprietária cancela tarefa que já teve envio');

select * from finish();
rollback;
