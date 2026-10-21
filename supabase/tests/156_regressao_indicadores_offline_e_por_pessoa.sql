-- =============================================================================
-- 156 · Regressão R4-REGRAS-02, R4-REGRAS-03 e R4-REGRAS-05 (indicadores).
--   - Trabalho offline feito antes do prazo não vira "Atrasada" só porque a fila
--     chegou depois: o envio guarda o horário do aparelho (submitted_at_device,
--     limitado pelo servidor; D94) e os prazos usam esse horário; a pessoa da
--     tarefa no prazo considera o início pelo aparelho (D72).
--   - Por pessoa, devolvidas e envio → revisão contam as tentativas que a pessoa
--     executou, e a "1ª tentativa" é o 1º envio dela na tarefa: quem socorre uma
--     tarefa reprovada não herda a reprovação (D96).
--   - Envio feito a tempo e reprovado só depois do prazo fica em "Pendentes"
--     (Correção solicitada), não em "Atrasadas" (D95).
-- Fixture independente (conta à mão). N = now(). Loja P, peso 2, 1 item crítico.
-- A = staff_p1, B = staff_p2.
--  T1 A  janela N-5h prazo N-3h  envio N-3.5h  aprovada N-3h
--  T2 A  janela N-5h prazo N-3h  envio N-3.5h  reprovada N-1h (depois do prazo)
--  T3 A->B antes do prazo (tentativa de A encerrada), B envia N, aprovada N
--  T4 A envia N-3h, reprovada N-2h; reatribuída a B; B envia N-0.5h, aprovada N-0.25h
--  T5 A  janela N-3h prazo N-1h  início no aparelho N-2h, envio no aparelho N-100min,
--        fila chegou N-24min -> aguardando (enviada a tempo)
--  T6 equipe (setor P1) janela N-3h prazo N-1h; A iniciou no aparelho N-2h, fila
--        chegou N-0.5h; em andamento -> atrasada, da A
--  T7 A  janela N-5h prazo N-2h  envio N-3h  aguardando
--  T8 B  sem exigência de aprovação, envio N-3h, auto-aprovada
--  T9 cancelada; T10 A pendente, prazo N+3h
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(14);

select tests.create_base_fixture();

create function tests.mk(p_name text, p_assignee text, p_win interval, p_due interval,
                         p_req_approval boolean default true)
returns void language plpgsql as $$
begin
  insert into public.tasks (id, organization_id, store_id, sector_id, title, requires_approval, weight,
                            assignee_id, window_start_at, due_at, created_at)
  values (tests.fx(p_name), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'K ' || p_name,
          p_req_approval, 2, case when p_assignee is null then null else tests.fx(p_assignee) end,
          now() + p_win, now() + p_due, now() - interval '6 hours');
  insert into public.task_items (id, task_id, position, text, is_critical)
  values (tests.fx(p_name || ':item1'), tests.fx(p_name), 1, 'Item crítico', true);
end $$;

create function tests.att(p_name text, p_n int, p_who text, p_start interval, p_sub interval,
                          p_dev_start interval default null, p_dev_sub interval default null)
returns uuid language plpgsql as $$
declare v uuid := tests.fx(p_name || ':att' || p_n);
begin
  insert into public.task_attempts (id, task_id, store_id, attempt_number, performed_by, started_at,
                                    started_at_device, submitted_at, submitted_at_device)
  values (v, tests.fx(p_name), tests.fx('store_p'), p_n, tests.fx(p_who), now() + p_start,
          case when p_dev_start is null then null else now() + p_dev_start end,
          case when p_sub is null then null else now() + p_sub end,
          case when p_dev_sub is null then null else now() + p_dev_sub end);
  return v;
end $$;

create function tests.rev(p_name text, p_n int, p_decision public.review_decision, p_at interval,
                          p_auto boolean default false)
returns void language plpgsql as $$
begin
  insert into public.reviews (id, attempt_id, task_id, reviewer_id, decision, reason, is_auto, reviewed_at)
  values (tests.fx(p_name || ':rev' || p_n), tests.fx(p_name || ':att' || p_n), tests.fx(p_name),
          case when p_auto then null else tests.fx('manager_p') end, p_decision,
          case when p_decision = 'rejected' then 'Item crítico fora do padrão' end, p_auto, now() + p_at);
  if p_decision = 'rejected' then
    insert into public.review_item_flags (review_id, task_id, task_item_id)
    values (tests.fx(p_name || ':rev' || p_n), tests.fx(p_name), tests.fx(p_name || ':item1'));
  end if;
end $$;

-- T1
select tests.mk('t1', 'staff_p1', '-5 hours', '-3 hours');
select tests.walk(tests.fx('t1'), 'in_progress');
select tests.att('t1', 1, 'staff_p1', '-4 hours', '-3.5 hours');
select tests.walk(tests.fx('t1'), 'submitted');
select tests.rev('t1', 1, 'approved', '-3 hours');
select tests.walk(tests.fx('t1'), 'approved');
-- T2: enviada a tempo, reprovada depois do prazo
select tests.mk('t2', 'staff_p1', '-5 hours', '-3 hours');
select tests.walk(tests.fx('t2'), 'in_progress');
select tests.att('t2', 1, 'staff_p1', '-4 hours', '-3.5 hours');
select tests.walk(tests.fx('t2'), 'submitted');
select tests.rev('t2', 1, 'rejected', '-1 hour');
select tests.walk(tests.fx('t2'), 'rejected');
-- T3: passagem antes do prazo
select tests.mk('t3', 'staff_p1', '-2 hours', '1 hour');
select tests.walk(tests.fx('t3'), 'in_progress');
select tests.att('t3', 1, 'staff_p1', '-1 hour', null);
update public.tasks set assignee_id = tests.fx('staff_p2') where id = tests.fx('t3');
select tests.att('t3', 2, 'staff_p2', '0 hours', '0 hours');
select tests.walk(tests.fx('t3'), 'submitted');
select tests.rev('t3', 2, 'approved', '0 hours');
select tests.walk(tests.fx('t3'), 'approved');
-- T4: reprovada, reatribuída, socorrida por B
select tests.mk('t4', 'staff_p1', '-5 hours', '2 hours');
select tests.walk(tests.fx('t4'), 'in_progress');
select tests.att('t4', 1, 'staff_p1', '-4 hours', '-3 hours');
select tests.walk(tests.fx('t4'), 'submitted');
select tests.rev('t4', 1, 'rejected', '-2 hours');
select tests.walk(tests.fx('t4'), 'rejected');
update public.tasks set assignee_id = tests.fx('staff_p2') where id = tests.fx('t4');
select tests.walk(tests.fx('t4'), 'in_progress');
select tests.att('t4', 2, 'staff_p2', '-1 hour', '-30 minutes');
select tests.walk(tests.fx('t4'), 'submitted');
select tests.rev('t4', 2, 'approved', '-15 minutes');
select tests.walk(tests.fx('t4'), 'approved');
-- T5: offline; aberta e enviada no aparelho antes do prazo, fila chegou depois
select tests.mk('t5', 'staff_p1', '-3 hours', '-1 hour');
select tests.walk(tests.fx('t5'), 'in_progress');
select tests.att('t5', 1, 'staff_p1', '-30 minutes', '-24 minutes', '-2 hours', '-100 minutes');
select tests.walk(tests.fx('t5'), 'submitted');
-- T6: equipe, início offline antes do prazo, fila chegou depois
select tests.mk('t6', null, '-3 hours', '-1 hour');
select tests.walk(tests.fx('t6'), 'in_progress');
select tests.att('t6', 1, 'staff_p1', '-30 minutes', null, '-2 hours');
-- T7
select tests.mk('t7', 'staff_p1', '-5 hours', '-2 hours');
select tests.walk(tests.fx('t7'), 'in_progress');
select tests.att('t7', 1, 'staff_p1', '-4 hours', '-3 hours');
select tests.walk(tests.fx('t7'), 'submitted');
-- T8: auto-aprovada
select tests.mk('t8', 'staff_p2', '-5 hours', '-2 hours', false);
select tests.walk(tests.fx('t8'), 'in_progress');
select tests.att('t8', 1, 'staff_p2', '-4 hours', '-3 hours');
select tests.walk(tests.fx('t8'), 'submitted');
select tests.rev('t8', 1, 'approved', '-3 hours', true);
select tests.walk(tests.fx('t8'), 'approved');
-- T9: cancelada
select tests.mk('t9', 'staff_p1', '-5 hours', '-2 hours');
select tests.walk(tests.fx('t9'), 'cancelled');
-- T10: pendente no futuro
select tests.mk('t10', 'staff_p1', '-1 hour', '3 hours');

create temporary table periodo as
  select ((now() at time zone 'America/Sao_Paulo')::date - 3) as d_from,
         ((now() at time zone 'America/Sao_Paulo')::date + 3) as d_to;
grant select on periodo to public;

select tests.authenticate_as('owner_a');

-- (1) Loja. previstas 9; executadas 7 (T1,T2,T3,T4,T5,T7,T8); aprovadas 4 (T1,T3,T4,T8);
-- atrasadas 1 (T6 sem envio; T2 reprovada só depois do prazo e T5 enviada no aparelho a
-- tempo não contam); pendentes 4 (T2,T5,T7,T10); aguardando 2 (T5,T7); na janela 4/9 = 44.4;
-- 1ª tentativa 2/3 = 66.7 (T1, T3 sim; T4 não; T8 fora); atribuição -> envio
-- (90+90+120+120+80+120+120)/7 = 105.7 (T5 pelo envio no aparelho: N-100min - (N-3h) = 80);
-- envio -> revisão pela chegada ao servidor (30+150+0+60+15)/5 = 51.0; devolvidas 2;
-- adoção 7/9 = 77.8
select results_eq(
  $$ select previstas, executadas, aprovadas, pendentes, aguardando_aprovacao, atrasadas,
            pct_aprovadas_na_janela, pct_aprovadas_primeira_tentativa, media_min_atribuicao_envio,
            media_min_envio_revisao, devolvidas, adocao
     from public.kpi_summary((select d_from from periodo), (select d_to from periodo),
                             array[tests.fx('store_p')]) $$,
  $$ values (9, 7, 4, 4, 2, 1, 44.4, 66.7, 105.7, 51.0, 2, 77.8) $$,
  'loja: indicadores batem com a conta à mão');

-- (2) Pessoa B (socorreu T4 depois da reprovação de A): 1º envio de B aprovado em T3 e T4
-- (T8 é auto): 100.0; nenhuma devolvida; envio -> revisão só das tentativas de B (0 + 15)/2
select results_eq(
  $$ select pct_aprovadas_primeira_tentativa, devolvidas, media_min_envio_revisao
     from public.kpi_summary((select d_from from periodo), (select d_to from periodo),
                             array[tests.fx('store_p')], null, array[tests.fx('staff_p2')]) $$,
  $$ values (100.0::numeric, 0, 7.5::numeric) $$,
  'pessoa B: a reprovação do trabalho de A não pesa em quem socorreu');

-- (3) Pessoa A: as duas reprovações foram do trabalho de A (T2 e T4); envio -> revisão das
-- tentativas de A (T1 30, T2 150, T4 60) = 80.0
select results_eq(
  $$ select devolvidas, media_min_envio_revisao, atrasadas, aguardando_aprovacao
     from public.kpi_summary((select d_from from periodo), (select d_to from periodo),
                             array[tests.fx('store_p')], null, array[tests.fx('staff_p1')]) $$,
  $$ values (2, 80.0::numeric, 1, 2) $$,
  'pessoa A: as devolvidas e a espera pela revisão das tentativas de A contam para A');

-- (4) Devolvidas por pessoa somam as da loja
select is(
  (select sum(k.devolvidas)::int
   from (values (tests.fx('staff_p1')), (tests.fx('staff_p2'))) p(id),
        lateral public.kpi_summary((select d_from from periodo), (select d_to from periodo),
                                   array[tests.fx('store_p')], null, array[p.id]) k),
  2, 'devolvidas por pessoa somam as da loja');

-- (5) T6: A abriu a tarefa de equipe no aparelho 1 h antes do prazo (D72); a falha é de
-- quem estava com ela no prazo (D74), não de "Sem responsável"
select is(
  (select private.task_person(t.id, t.assignee_id, t.assignee_at_due, t.assignee_at_due_recorded)
   from public.tasks t where t.id = tests.fx('t6')),
  tests.fx('staff_p1'),
  'T6: a tarefa de equipe iniciada no aparelho antes do prazo fica com quem a iniciou');

-- (6) Nota por pessoa: A = T1,T2,T5,T6,T7,T10 -> 2/12 = 16.7; B = T3,T4,T8 -> 100;
-- críticos reprovados: A = 2 (T2, T4); ninguém em "Sem responsável"
select results_eq(
  $$ select group_id, volume, peso_total, nota, criticos_reprovados
     from public.weighted_scores((select d_from from periodo), (select d_to from periodo),
                                 'person', array[tests.fx('store_p')])
     order by group_id nulls last $$,
  $$ select * from (values
       (tests.fx('staff_p1'), 6, 12, 16.7::numeric, 2),
       (tests.fx('staff_p2'), 3, 6, 100.0::numeric, 0)) v(a,b,c,d,e) order by a nulls last $$,
  'pessoas: nota e críticos (T6 com A, pelo início no aparelho)');

-- (7) O horário do envio no aparelho congela com a tentativa enviada
select tests.reset_role();
select throws_ok(
  format($$ update public.task_attempts set submitted_at_device = null where id = %L $$, tests.fx('t5:att1')),
  'P0001', 'immutable', 'o horário do envio no aparelho não muda depois do envio');

-- (8..14) Pela RPC: o horário do aparelho no envio é limitado pelo servidor
select tests.create_task('off', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.create_task('off2', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.create_task('onl', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('off'), gen_random_uuid(), now() - interval '40 minutes');
select public.answer_item(tests.attempt_of('off', 1), tests.fx('off:item1'), true, null, gen_random_uuid(),
                          now() - interval '30 minutes');
select public.submit_attempt(tests.attempt_of('off', 1), null, gen_random_uuid(), now() - interval '20 minutes');
select public.start_attempt(tests.fx('off2'), gen_random_uuid(), now() - interval '40 minutes');
select public.answer_item(tests.attempt_of('off2', 1), tests.fx('off2:item1'), true, null, gen_random_uuid(),
                          now() - interval '30 minutes');
-- Aparelho diz que enviou ANTES da última resposta: vale a última resposta
select public.submit_attempt(tests.attempt_of('off2', 1), null, gen_random_uuid(), now() - interval '50 minutes');
select public.start_attempt(tests.fx('onl'), gen_random_uuid());
select public.answer_item(tests.attempt_of('onl', 1), tests.fx('onl:item1'), true);
-- Relógio adiantado: vale no máximo agora
select public.submit_attempt(tests.attempt_of('onl', 1), null, gen_random_uuid(), now() + interval '1 day');
select tests.reset_role();

select is(
  (select submitted_at_device from public.task_attempts where id = tests.attempt_of('off', 1)),
  now() - interval '20 minutes', 'envio offline: grava o horário do aparelho');
select is(
  (select submitted_at from public.task_attempts where id = tests.attempt_of('off', 1)),
  now(), 'envio offline: submitted_at continua sendo a chegada ao servidor');
select is(
  (select submitted_at_device from public.task_attempts where id = tests.attempt_of('off2', 1)),
  now() - interval '30 minutes', 'envio no aparelho antes da última resposta: limitado à última resposta');
select is(
  (select submitted_at_device from public.task_attempts where id = tests.attempt_of('onl', 1)),
  now(), 'relógio adiantado: limitado à hora do servidor');
select throws_like(
  format($$ insert into public.task_attempts (task_id, store_id, attempt_number, performed_by, started_at,
                                              submitted_at, submitted_at_device)
            values (%L, %L, 2, %L, now() - interval '1 hour', now(), now() - interval '2 hours') $$,
         tests.fx('t10'), tests.fx('store_p'), tests.fx('staff_p1')),
  '%task_attempts_device_submit_bounds%', 'CHECK: envio no aparelho nunca antes do início');
select throws_like(
  format($$ insert into public.task_attempts (task_id, store_id, attempt_number, performed_by, started_at,
                                              submitted_at_device)
            values (%L, %L, 2, %L, now() - interval '1 hour', now() - interval '30 minutes') $$,
         tests.fx('t10'), tests.fx('store_p'), tests.fx('staff_p1')),
  '%task_attempts_device_submit_bounds%', 'CHECK: horário do envio no aparelho só com envio');
select has_function('public', 'submit_attempt', array['uuid', 'text', 'uuid', 'timestamp with time zone'],
  'submit_attempt recebe o horário do aparelho');

select * from finish();
rollback;
