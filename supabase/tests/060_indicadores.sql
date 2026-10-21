-- =============================================================================
-- 060 · Indicadores (docs §7) com resultado esperado escrito no teste.
--
-- Cenário (Loja P e Loja C, fuso America/Sao_Paulo = UTC-3; horários em UTC).
-- Todas criadas em 2026-03-10 03:05Z. S1 = sector_p1, S2 = sector_p2,
-- S3 = sector_c1; U1 = staff_p1, U2 = staff_p2, U3 = staff_c1.
--
--  tarefa loja setor resp peso aprov janela (início..prazo)   tentativas (envio) / revisões              status
--  k1     P    S1    U1   3    sim   03-10 10:30..11:15        #1 10:50 / aprovada 11:20                   approved
--  k2     P    S1    U1   2    sim   03-10 13:00..15:00        #1 13:30 / reprov. 14:00 (itens 1 e 2)       approved
--                                                              #2 16:00 (fora da janela) / aprov. 16:30
--  k3     P    S2    U2   1    não   03-10 18:00..20:00        #1 18:30 / auto-aprovada 18:30              approved
--  k4     P    S2    U2   4    sim   03-10 19:00..21:00        #1 20:00 / -                                submitted (vencida)
--  k5     P    S1    -    5    sim   03-10 20:00..21:00        -                                           overdue
--  k6     P    S1    U1   2    sim   03-10 13:00..15:00        #1 14:00 / reprov. 14:30 (item 1)           cancelled
--  k7     P    S1    U1   3    sim   03-11 01:30..02:30        #1 02:00 / aprovada 02:10                   approved
--                                    (02:30Z = 03-10 23:30 local: conta no dia 10)
--  k8     P    S1    U1   2    sim   03-10 01:30..02:30        -                                           pending (dia local 09)
--  k9     C    S3    U3   3    sim   03-10 13:00..15:00        #1 14:00 / aprovada 15:00                   approved
--  k10    C    S3    U3   2    sim   03-10 15:00..17:00        #1 16:00 / reprov. 16:20 (item 1)           rejected (vencida)
--  k11    P    S1    U1   3    sim   2099-01-01 11:00..12:00   -                                           pending (futura)
--  k12    P    S2    U2   2    sim   2099-01-01 13:00..15:00   #1 14:00 / reprov. 14:10 (item 1)           submitted (futura)
--                                                              #2 14:30 / -
-- Item 1 = "Item crítico de teste" (crítico), item 2 = "Item comum de teste".
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(18);

select tests.create_base_fixture();

insert into public.task_templates (id, organization_id, store_id, title)
values (tests.fx('kpi_tpl'), tests.fx('org_a'), null, 'Rotina de teste');
insert into public.template_items (id, template_id, position, text, is_critical)
values (tests.fx('kpi_ti1'), tests.fx('kpi_tpl'), 1, 'Item crítico de teste', true),
       (tests.fx('kpi_ti2'), tests.fx('kpi_tpl'), 2, 'Item comum de teste', false);

create function tests.kpi_task(
  p_name text, p_store text, p_sector text, p_assignee text, p_weight integer,
  p_requires_approval boolean, p_window_start timestamptz, p_due timestamptz
)
returns void
language plpgsql
as $$
begin
  -- O snapshot copia a versão atual da rotina: a rotina passa a ter o peso e a
  -- exigência de aprovação desta tarefa antes de ela ser criada
  update public.task_templates set weight = p_weight, requires_approval = p_requires_approval
   where id = tests.fx('kpi_tpl');
  insert into public.tasks (id, organization_id, store_id, sector_id, template_id, template_version, title,
                            weight, requires_approval, assignee_id, window_start_at, due_at, created_at)
  values (tests.fx(p_name), tests.fx('org_a'), tests.fx(p_store), tests.fx(p_sector), tests.fx('kpi_tpl'),
          (select t.version from public.task_templates t where t.id = tests.fx('kpi_tpl')),
          'Rotina de teste', p_weight, p_requires_approval,
          case when p_assignee is null then null else tests.fx(p_assignee) end,
          p_window_start, p_due, '2026-03-10 03:05+00');
  insert into public.task_items (id, task_id, template_item_id, position, text, is_critical)
  values (tests.fx(p_name || ':i1'), tests.fx(p_name), tests.fx('kpi_ti1'), 1, 'Item crítico de teste', true),
         (tests.fx(p_name || ':i2'), tests.fx(p_name), tests.fx('kpi_ti2'), 2, 'Item comum de teste', false);
end;
$$;

create function tests.kpi_attempt(p_task text, p_number integer, p_performer text, p_submitted timestamptz)
returns void
language plpgsql
as $$
begin
  insert into public.task_attempts (id, task_id, store_id, attempt_number, performed_by, started_at, submitted_at)
  select tests.fx(p_task || ':a' || p_number), t.id, t.store_id, p_number, tests.fx(p_performer),
         p_submitted - interval '10 minutes', p_submitted
  from public.tasks t where t.id = tests.fx(p_task);
end;
$$;

create function tests.kpi_review(
  p_task text, p_number integer, p_reviewer text, p_decision public.review_decision,
  p_at timestamptz, p_flagged_items integer[] default '{}'
)
returns void
language plpgsql
as $$
begin
  insert into public.reviews (id, attempt_id, task_id, reviewer_id, decision, reason, is_auto, reviewed_at)
  values (tests.fx(p_task || ':r' || p_number), tests.fx(p_task || ':a' || p_number), tests.fx(p_task),
          case when p_reviewer is null then null else tests.fx(p_reviewer) end,
          p_decision, case when p_decision = 'rejected' then 'Refazer' end, p_reviewer is null, p_at);
  insert into public.review_item_flags (review_id, task_id, task_item_id)
  select tests.fx(p_task || ':r' || p_number), tests.fx(p_task), tests.fx(p_task || ':i' || i)
  from unnest(p_flagged_items) as i;
end;
$$;

-- k1
select tests.kpi_task('k1', 'store_p', 'sector_p1', 'staff_p1', 3, true, '2026-03-10 10:30+00', '2026-03-10 11:15+00');
select tests.kpi_attempt('k1', 1, 'staff_p1', '2026-03-10 10:50+00');
select tests.kpi_review('k1', 1, 'manager_p', 'approved', '2026-03-10 11:20+00');
select tests.walk(tests.fx('k1'), 'in_progress', 'submitted', 'approved');
-- k2
select tests.kpi_task('k2', 'store_p', 'sector_p1', 'staff_p1', 2, true, '2026-03-10 13:00+00', '2026-03-10 15:00+00');
select tests.kpi_attempt('k2', 1, 'staff_p1', '2026-03-10 13:30+00');
select tests.kpi_review('k2', 1, 'manager_p', 'rejected', '2026-03-10 14:00+00', '{1,2}');
select tests.kpi_attempt('k2', 2, 'staff_p1', '2026-03-10 16:00+00');
select tests.kpi_review('k2', 2, 'manager_p', 'approved', '2026-03-10 16:30+00');
select tests.walk(tests.fx('k2'), 'in_progress', 'submitted', 'rejected', 'in_progress', 'submitted', 'approved');
-- k3 (auto-aprovada)
select tests.kpi_task('k3', 'store_p', 'sector_p2', 'staff_p2', 1, false, '2026-03-10 18:00+00', '2026-03-10 20:00+00');
select tests.kpi_attempt('k3', 1, 'staff_p2', '2026-03-10 18:30+00');
select tests.kpi_review('k3', 1, null, 'approved', '2026-03-10 18:30+00');
select tests.walk(tests.fx('k3'), 'in_progress', 'submitted', 'approved');
-- k4 (aguardando aprovação, vencida)
select tests.kpi_task('k4', 'store_p', 'sector_p2', 'staff_p2', 4, true, '2026-03-10 19:00+00', '2026-03-10 21:00+00');
select tests.kpi_attempt('k4', 1, 'staff_p2', '2026-03-10 20:00+00');
select tests.walk(tests.fx('k4'), 'in_progress', 'submitted');
-- k5 (equipe, atrasada sem tentativa)
select tests.kpi_task('k5', 'store_p', 'sector_p1', null, 5, true, '2026-03-10 20:00+00', '2026-03-10 21:00+00');
select tests.walk(tests.fx('k5'), 'overdue');
-- k6 (reprovada e depois cancelada: fora de tudo)
select tests.kpi_task('k6', 'store_p', 'sector_p1', 'staff_p1', 2, true, '2026-03-10 13:00+00', '2026-03-10 15:00+00');
select tests.kpi_attempt('k6', 1, 'staff_p1', '2026-03-10 14:00+00');
select tests.kpi_review('k6', 1, 'manager_p', 'rejected', '2026-03-10 14:30+00', '{1}');
select tests.walk(tests.fx('k6'), 'in_progress', 'submitted', 'rejected', 'cancelled');
-- k7 (virada de dia: 02:30Z é 23:30 do dia 10 no fuso da loja)
select tests.kpi_task('k7', 'store_p', 'sector_p1', 'staff_p1', 3, true, '2026-03-11 01:30+00', '2026-03-11 02:30+00');
select tests.kpi_attempt('k7', 1, 'staff_p1', '2026-03-11 02:00+00');
select tests.kpi_review('k7', 1, 'manager_p', 'approved', '2026-03-11 02:10+00');
select tests.walk(tests.fx('k7'), 'in_progress', 'submitted', 'approved');
-- k8 (02:30Z do dia 10 = 23:30 do dia 9 local)
select tests.kpi_task('k8', 'store_p', 'sector_p1', 'staff_p1', 2, true, '2026-03-10 01:30+00', '2026-03-10 02:30+00');
-- k9 (loja C)
select tests.kpi_task('k9', 'store_c', 'sector_c1', 'staff_c1', 3, true, '2026-03-10 13:00+00', '2026-03-10 15:00+00');
select tests.kpi_attempt('k9', 1, 'staff_c1', '2026-03-10 14:00+00');
select tests.kpi_review('k9', 1, 'manager_c', 'approved', '2026-03-10 15:00+00');
select tests.walk(tests.fx('k9'), 'in_progress', 'submitted', 'approved');
-- k10 (loja C, reprovada)
select tests.kpi_task('k10', 'store_c', 'sector_c1', 'staff_c1', 2, true, '2026-03-10 15:00+00', '2026-03-10 17:00+00');
select tests.kpi_attempt('k10', 1, 'staff_c1', '2026-03-10 16:00+00');
select tests.kpi_review('k10', 1, 'manager_c', 'rejected', '2026-03-10 16:20+00', '{1}');
select tests.walk(tests.fx('k10'), 'in_progress', 'submitted', 'rejected');
-- k11 (futura, pendente)
select tests.kpi_task('k11', 'store_p', 'sector_p1', 'staff_p1', 3, true, '2099-01-01 11:00+00', '2099-01-01 12:00+00');
-- k12 (futura, reprovada e reenviada)
select tests.kpi_task('k12', 'store_p', 'sector_p2', 'staff_p2', 2, true, '2099-01-01 13:00+00', '2099-01-01 15:00+00');
select tests.kpi_attempt('k12', 1, 'staff_p2', '2099-01-01 14:00+00');
select tests.kpi_review('k12', 1, 'manager_p', 'rejected', '2099-01-01 14:10+00', '{1}');
select tests.kpi_attempt('k12', 2, 'staff_p2', '2099-01-01 14:30+00');
select tests.walk(tests.fx('k12'), 'in_progress', 'submitted', 'rejected', 'in_progress', 'submitted');

-- =============================================================================
-- kpi_summary (colunas: previstas, executadas, aprovadas, pendentes,
-- aguardando_aprovacao, atrasadas, pct_aprovadas_na_janela,
-- pct_aprovadas_primeira_tentativa, media_min_atribuicao_envio,
-- media_min_envio_revisao, devolvidas, adocao)
-- =============================================================================
select tests.authenticate_as('owner_a');

-- Período inteiro: 11 previstas (k6 cancelada fica fora)
--   executadas 8 (k1 k2 k3 k4 k7 k9 k10 k12); aprovadas 5 (k1 k2 k3 k7 k9)
--   atrasadas 4 (k4 k5 k8 k10); pendentes 2 (k11 k12); aguardando 1 (k12)
--   na janela 4/11 = 36.4 (k2 aprovada fora da janela)
--   1ª tentativa 3/4 = 75.0 (k3 auto fica fora; k2 aprovada na 2ª)
--   atribuição→envio (20+30+30+60+30+60+60+60)/8 = 43.75 -> 43.8 min
--   envio→revisão manual (30+30+30+10+60+20+10)/7 = 27.14 -> 27.1 min
--   devolvidas 3 (k2 #1, k10 #1, k12 #1); adoção 8/11 = 72.7
select results_eq(
  $$ select * from public.kpi_summary('2026-03-01', '2099-12-31') $$,
  $$ values (11, 8, 5, 2, 1, 4, 36.4, 75.0, 43.8, 27.1, 3, 72.7) $$,
  'kpi_summary no período inteiro (proprietária)'
);

-- Só o dia local 10/03: k1 k2 k3 k4 k5 k7 k9 k10 (k7 entra pela virada de fuso; k8 sai)
select results_eq(
  $$ select * from public.kpi_summary('2026-03-10', '2026-03-10') $$,
  $$ values (8, 7, 5, 0, 0, 3, 50.0, 75.0, 41.4, 30.0, 2, 87.5) $$,
  'kpi_summary do dia local 10/03 (02:30Z do dia 11 conta no dia 10)'
);

-- Só o dia local 09/03: k8 (02:30Z do dia 10 pertence ao dia 9 local)
select results_eq(
  $$ select * from public.kpi_summary('2026-03-09', '2026-03-09') $$,
  $$ values (1, 0, 0, 0, 0, 1, 0.0, null::numeric, null::numeric, null::numeric, 0, 0.0) $$,
  'kpi_summary do dia local 09/03 (percentuais e médias sem base ficam nulos)'
);

select results_eq(
  $$ select * from public.kpi_summary('2026-03-01', '2099-12-31', null, array[tests.fx('sector_p2')]) $$,
  $$ values (3, 3, 1, 1, 1, 1, 33.3, null::numeric, 50.0, 10.0, 1, 100.0) $$,
  'kpi_summary filtrado pelo setor P2 (k3 k4 k12)'
);

select results_eq(
  $$ select * from public.kpi_summary('2026-03-01', '2099-12-31', null, null, array[tests.fx('staff_c1')]) $$,
  $$ values (2, 2, 1, 0, 0, 1, 50.0, 100.0, 60.0, 40.0, 1, 100.0) $$,
  'kpi_summary filtrado pela pessoa C1 (k9 k10)'
);

select results_eq(
  $$ select * from public.kpi_summary('2026-03-01', '2099-12-31', array[tests.fx('store_c')]) $$,
  $$ values (2, 2, 1, 0, 0, 1, 50.0, 100.0, 60.0, 40.0, 1, 100.0) $$,
  'kpi_summary filtrado pela loja C'
);

-- RLS: gerente P pede as duas lojas e recebe só a Loja P
--   previstas 9 (k1 k2 k3 k4 k5 k7 k8 k11 k12); executadas 6; aprovadas 4
--   atrasadas 3 (k4 k5 k8); pendentes 2; aguardando 1
--   janela 3/9 = 33.3; 1ª tentativa 2/3 = 66.7
--   atribuição→envio (20+30+30+60+30+60)/6 = 38.3; revisão (30+30+30+10+10)/5 = 22.0
--   devolvidas 2; adoção 6/9 = 66.7
select tests.authenticate_as('manager_p');
select results_eq(
  format($$ select * from public.kpi_summary('2026-03-01', '2099-12-31', array[%L, %L]::uuid[]) $$,
         tests.fx('store_p'), tests.fx('store_c')),
  $$ values (9, 6, 4, 2, 1, 3, 33.3, 66.7, 38.3, 22.0, 2, 66.7) $$,
  'gerente P pede todas as lojas e recebe só os números da Loja P (RLS)'
);

select tests.authenticate_as('admin_a');
select results_eq(
  $$ select previstas, executadas from public.kpi_summary('2026-03-01', '2099-12-31') $$,
  $$ values (0, 0) $$,
  'admin não lê dados operacionais pelos indicadores (só por admin_read_*)'
);

-- =============================================================================
-- weighted_scores: nota = 100 × Σ peso aprovadas ÷ Σ peso
-- =============================================================================
select tests.authenticate_as('owner_a');

-- Loja P: k1 3 k2 2 k3 1 k4 4 k5 5 k7 3 k8 2 k11 3 k12 2 = 25; aprovadas 3+2+1+3 = 9 -> 36.0
--         críticos reprovados: k2 #1 item 1, k12 #1 item 1 = 2 (k6 cancelada fora)
-- Loja C: k9 3 k10 2 = 5; aprovada 3 -> 60.0; críticos: k10 = 1
select set_eq(
  $$ select * from public.weighted_scores('2026-03-01', '2099-12-31', 'store') $$,
  format($$ values (%L::uuid, 'Loja P Teste'::text, 9, 25, 36.0, 2), (%L::uuid, 'Loja C Teste'::text, 2, 5, 60.0, 1) $$,
         tests.fx('store_p'), tests.fx('store_c')),
  'weighted_scores por loja'
);

-- Pessoa = executor da tentativa aprovada, senão o responsável
--   U1: k1 k2 k7 (aprovadas por ele) + k8 k11 (responsável) = 5 | peso 13 | 8/13 = 61.5 | crít. 1 (k2)
--   U2: k3 (aprovada por ele) + k4 k12 = 3 | peso 7 | 1/7 = 14.3 | crít. 1 (k12)
--   U3: k9 k10 = 2 | peso 5 | 60.0 | crít. 1 (k10)
--   sem responsável: k5 = 1 | peso 5 | 0.0
select set_eq(
  $$ select * from public.weighted_scores('2026-03-01', '2099-12-31', 'person') $$,
  format(
    $$ values (%L::uuid, '[TESTE] Colaborador P1'::text, 5, 13, 61.5, 1),
              (%L::uuid, '[TESTE] Colaborador P2'::text, 3, 7, 14.3, 1),
              (%L::uuid, '[TESTE] Colaborador C1'::text, 2, 5, 60.0, 1),
              (null::uuid, 'Sem responsável'::text, 1, 5, 0.0, 0) $$,
    tests.fx('staff_p1'), tests.fx('staff_p2'), tests.fx('staff_c1')
  ),
  'weighted_scores por pessoa (sempre com volume e peso ao lado da nota)'
);

--   S1: k1 k2 k5 k7 k8 k11 = 6 | peso 18 | 8/18 = 44.4 | crít. 1
--   S2: k3 k4 k12 = 3 | peso 7 | 14.3 | crít. 1
--   S3: k9 k10 = 2 | peso 5 | 60.0 | crít. 1
select set_eq(
  $$ select * from public.weighted_scores('2026-03-01', '2099-12-31', 'sector') $$,
  format(
    $$ values (%L::uuid, 'Setor P1'::text, 6, 18, 44.4, 1),
              (%L::uuid, 'Setor P2'::text, 3, 7, 14.3, 1),
              (%L::uuid, 'Setor C1'::text, 2, 5, 60.0, 1) $$,
    tests.fx('sector_p1'), tests.fx('sector_p2'), tests.fx('sector_c1')
  ),
  'weighted_scores por setor'
);

select set_eq(
  $$ select * from public.weighted_scores('2026-03-10', '2026-03-10', 'store') $$,
  format($$ values (%L::uuid, 'Loja P Teste'::text, 6, 18, 50.0, 1), (%L::uuid, 'Loja C Teste'::text, 2, 5, 60.0, 1) $$,
         tests.fx('store_p'), tests.fx('store_c')),
  'weighted_scores por loja no dia local 10/03 (P: k1 k2 k3 k4 k5 k7)'
);

select throws_ok(
  $$ select * from public.weighted_scores('2026-03-01', '2099-12-31', 'ranking') $$,
  '22023', 'invalid_group', 'agrupamento desconhecido é recusado'
);

select tests.authenticate_as('manager_p');
select set_eq(
  $$ select * from public.weighted_scores('2026-03-01', '2099-12-31', 'store') $$,
  format($$ values (%L::uuid, 'Loja P Teste'::text, 9, 25, 36.0, 2) $$, tests.fx('store_p')),
  'gerente P só vê a nota da própria loja (RLS)'
);

-- =============================================================================
-- top_failed_items (k6 cancelada fica fora)
--   item 1 / Loja P: k2 #1 + k12 #1 = 2; item 1 / Loja C: k10 #1 = 1; item 2 / Loja P: k2 #1 = 1
-- =============================================================================
select tests.authenticate_as('owner_a');
select results_eq(
  $$ select * from public.top_failed_items('2026-03-01', '2099-12-31') $$,
  format(
    $$ values (%1$L::uuid, 'Item crítico de teste'::text, 'Rotina de teste'::text, %3$L::uuid, 'Loja P Teste'::text, 2),
              (%1$L::uuid, 'Item crítico de teste'::text, 'Rotina de teste'::text, %4$L::uuid, 'Loja C Teste'::text, 1),
              (%2$L::uuid, 'Item comum de teste'::text, 'Rotina de teste'::text, %3$L::uuid, 'Loja P Teste'::text, 1) $$,
    tests.fx('kpi_ti1'), tests.fx('kpi_ti2'), tests.fx('store_p'), tests.fx('store_c')
  ),
  'top_failed_items: mais reprovados primeiro, por item e loja'
);

select results_eq(
  $$ select template_item_id, store_id, reprovacoes from public.top_failed_items('2026-03-01', '2099-12-31', null, 1) $$,
  format($$ values (%L::uuid, %L::uuid, 2) $$, tests.fx('kpi_ti1'), tests.fx('store_p')),
  'top_failed_items respeita o limite'
);

select results_eq(
  $$ select template_item_id, store_id, reprovacoes from public.top_failed_items('2026-03-10', '2026-03-10') $$,
  format($$ values (%1$L::uuid, %4$L::uuid, 1), (%2$L::uuid, %3$L::uuid, 1), (%1$L::uuid, %3$L::uuid, 1) $$,
         tests.fx('kpi_ti1'), tests.fx('kpi_ti2'), tests.fx('store_p'), tests.fx('store_c')),
  'top_failed_items no dia local 10/03 (empate: loja e texto do item)'
);

select tests.authenticate_as('manager_p');
select results_eq(
  $$ select template_item_id, store_id, reprovacoes from public.top_failed_items('2026-03-01', '2099-12-31') $$,
  format($$ values (%1$L::uuid, %3$L::uuid, 2), (%2$L::uuid, %3$L::uuid, 1) $$,
         tests.fx('kpi_ti1'), tests.fx('kpi_ti2'), tests.fx('store_p')),
  'gerente P só vê as falhas da própria loja (RLS)'
);

select * from finish();
rollback;
