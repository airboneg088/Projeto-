-- =============================================================================
-- 138 · Regressão R2-REGRAS-S5 (R1-REGRAS-10): fronteiras do agendamento.
--   - a janela termina no mesmo dia local: window_end até 23:59:59 ('24:00'
--     jogaria o prazo para o dia seguinte) e depois do início;
--   - a regra só aceita valores do domínio: weekdays inteiros 1..7, monthdays
--     inteiros 1..31, dates AAAA-MM-DD que existem (em qualquer frequência).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(14);

select tests.create_base_fixture();
insert into public.task_templates (id, organization_id, store_id, title)
values (tests.fx('ag_tpl'), tests.fx('org_a'), tests.fx('store_p'), 'Fechamento');

create function tests.ag(p_frequency public.schedule_frequency, p_rule jsonb, p_start time, p_end time)
returns text language sql as $$
  select tests.exec_result(format(
    $q$ insert into public.schedules (store_id, template_id, sector_id, frequency, rule, window_start, window_end)
        values (%L, %L, %L, %L, %L, %L, %L) $q$,
    tests.fx('store_p'), tests.fx('ag_tpl'), tests.fx('sector_p1'), p_frequency, p_rule, p_start, p_end))
$$;
grant execute on function tests.ag(public.schedule_frequency, jsonb, time, time) to public;

-- Janela
select alike(tests.ag('daily', '{}', '23:00', '24:00'), '23514:%schedules_window_same_day%',
  'janela terminando em 24:00 (vira o dia seguinte) é recusada');
select is(tests.ag('daily', '{}', '23:00', '23:59:59'), 'ok', 'janela até 23:59:59 é aceita');
select alike(tests.ag('daily', '{}', '10:00', '10:00'), '23514:%schedules_window_valid%',
  'janela sem duração é recusada');

-- weekdays
select alike(tests.ag('weekly', '{"weekdays":[0, 9]}', '08:00', '09:00'), '23514:%schedules_rule_values%',
  'weekdays fora de 1..7 é recusado');
select alike(tests.ag('weekly', '{"weekdays":[1.5]}', '08:00', '09:00'), '23514:%schedules_rule_values%',
  'weekdays não inteiro é recusado');
select alike(tests.ag('weekly', '{"weekdays":["1"]}', '08:00', '09:00'), '23514:%schedules_rule_values%',
  'weekdays como texto é recusado');
select is(tests.ag('weekly', '{"weekdays":[1, 7]}', '08:00', '09:00'), 'ok', 'weekdays 1 e 7 são aceitos');

-- monthdays
select alike(tests.ag('monthly', '{"monthdays":["x", 40]}', '08:00', '09:00'), '23514:%schedules_rule_values%',
  'monthdays fora de 1..31 é recusado');
select is(tests.ag('monthly', '{"monthdays":[1, 31]}', '08:00', '09:00'), 'ok', 'monthdays 1 e 31 são aceitos');

-- dates
select alike(tests.ag('specific_days', '{"dates":["amanhã"]}', '08:00', '09:00'), '23514:%schedules_rule_values%',
  'dates fora do formato AAAA-MM-DD é recusado');
select alike(tests.ag('specific_days', '{"dates":["2026-02-30"]}', '08:00', '09:00'), '23514:%schedules_rule_values%',
  'data que não existe é recusada');
select is(tests.ag('specific_days', '{"dates":["2026-02-28", "2028-02-29"]}', '08:00', '09:00'), 'ok',
  'datas válidas são aceitas');

-- Chave de outra frequência também precisa ser válida
select alike(tests.ag('daily', '{"weekdays":[9]}', '08:00', '09:00'), '23514:%schedules_rule_values%',
  'valor inválido é recusado mesmo em chave que a frequência não usa');

-- Pela API (gerente da loja): o CHECK roda com o papel de quem grava
select tests.authenticate_as('manager_p');
select alike(tests.ag('weekly', '{"weekdays":[8]}', '08:00', '09:00'), '23514:%schedules_rule_values%',
  'gerente pela API recebe a mesma recusa (23514)');

select * from finish();
rollback;
