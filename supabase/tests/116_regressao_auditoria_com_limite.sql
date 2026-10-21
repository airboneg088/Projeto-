-- =============================================================================
-- 116 · Regressão R2-FUNC-05 (correção incompleta de R1-FI-08): o audit_log
-- append-only não vira depósito sem limite pelos gatilhos de auditoria.
--   - colunas de texto/jsonb gravadas pela API têm tamanho máximo (CHECK):
--     título 200, instruções 4000, item 500, setor 100, regra do agendamento
--     4 KB só com weekdays/monthdays/dates, canais 2 KB;
--   - no diff, valor acima de 2 KB vai resumido (truncated, bytes, sha256,
--     prefix de 1024 caracteres).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(13);

select tests.create_base_fixture();
select tests.create_store_activity('p');
create temporary table marca as select coalesce(max(id), 0) as last_id from public.audit_log;
grant select on marca to public;

select tests.authenticate_as('manager_p');
select alike(tests.exec_result(format($$ update public.tasks set instructions = repeat('x', 1000000) where id = %L $$, tests.fx('task_p'))),
  '23514:%', 'instruções de 1 MB na tarefa são recusadas');
select alike(tests.exec_result(format($$ update public.tasks set title = repeat('t', 201) where id = %L $$, tests.fx('task_p'))),
  '23514:%', 'título com mais de 200 caracteres é recusado');
select alike(tests.exec_result(format($$ update public.task_templates set instructions = repeat('z', 1000000) where id = %L $$, tests.fx('tpl_p'))),
  '23514:%', 'instruções de 1 MB na rotina são recusadas');
select alike(tests.exec_result(format($$ update public.template_items set text = repeat('i', 501) where id = %L $$, tests.fx('tpl_p:item2'))),
  '23514:%', 'item de rotina com mais de 500 caracteres é recusado');
select alike(tests.exec_result(format($$ update public.schedules set rule = jsonb_build_object('lixo', repeat('w', 1000000)) where id = %L $$, tests.fx('sch_p'))),
  '23514:%', 'regra de agendamento com chave desconhecida é recusada');
select alike(tests.exec_result(format($$ update public.schedules set frequency = 'weekly', rule = jsonb_build_object('weekdays', (select jsonb_agg(1) from generate_series(1, 5000))) where id = %L $$, tests.fx('sch_p'))),
  '23514:%', 'regra de agendamento maior que 4 KB é recusada');
select alike(tests.exec_result(format($$ update public.sectors set name = repeat('v', 101) where id = %L $$, tests.fx('sector_p2'))),
  '23514:%', 'nome de setor com mais de 100 caracteres é recusado');

-- Valor permitido, mas acima de 2 KB: entra resumido no diff
select is(tests.exec_result(format($$ update public.tasks set instructions = repeat('y', 3900) where id = %L $$, tests.fx('task_p'))),
  'ok', 'instruções de 3.900 caracteres são aceitas');
select tests.authenticate_as('owner_a');
select alike(tests.exec_result(format($$ update public.store_settings set channels = jsonb_build_object('lixo', repeat('c', 3000)) where store_id = %L $$, tests.fx('store_p'))),
  '23514:%', 'canais de notificação acima de 2 KB são recusados');
select tests.reset_role();

select results_eq(
  format($$ select (diff -> 'instructions' -> 'new' ->> 'truncated')::boolean, (diff -> 'instructions' -> 'new' ->> 'bytes')::int,
                   char_length(diff -> 'instructions' -> 'new' ->> 'prefix'), diff -> 'instructions' -> 'new' ->> 'sha256'
            from public.audit_log, marca where id > marca.last_id and table_name = 'tasks' and record_id = %L $$,
         tests.fx('task_p')),
  $$ values (true, 3902, 1024, encode(sha256(convert_to(to_jsonb(repeat('y', 3900))::text, 'UTF8')), 'hex')) $$,
  'valor acima de 2 KB vai resumido no diff (truncated, bytes, prefix de 1024, sha256)'
);
select cmp_ok(
  (select coalesce(max(octet_length(diff::text)), 0) from public.audit_log, marca where id > marca.last_id),
  '<=', 65536, 'nenhum registro de auditoria passa de 64 KB');
select cmp_ok(
  (select coalesce(sum(octet_length(diff::text)), 0)::bigint from public.audit_log, marca where id > marca.last_id),
  '<=', 262144::bigint, 'as edições do gerente não acrescentam mais de 256 KB ao audit_log append-only');
select cmp_ok(
  (select octet_length(rule::text) from public.schedules where id = tests.fx('sch_p')),
  '<=', 4096, 'regra do agendamento tem limite de tamanho');

select * from finish();
rollback;
