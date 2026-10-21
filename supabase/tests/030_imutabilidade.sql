-- =============================================================================
-- 030 · Imutabilidade do histórico (docs §5)
-- UPDATE/DELETE em audit_log, evidences (exceto purga), reviews e
-- review_item_flags falham para authenticated, service_role e postgres.
-- Tentativa enviada e suas respostas não mudam mais.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(49);

select tests.create_base_fixture();
select tests.create_store_activity('p');

create temporary table mutations (ord serial primary key, descr text not null, sql text not null);
insert into mutations (descr, sql)
values
  ('UPDATE audit_log', $$ update public.audit_log set action = 'adulterada' where id = (select max(id) from public.audit_log) $$),
  ('DELETE audit_log', $$ delete from public.audit_log where id = (select max(id) from public.audit_log) $$),
  ('UPDATE evidences', $$ update public.evidences set sha256 = repeat('0', 64) where id = tests.fx('ev_p') $$),
  ('DELETE evidences', $$ delete from public.evidences where id = tests.fx('ev_p') $$),
  ('UPDATE reviews', $$ update public.reviews set decision = 'approved', reason = null where id = tests.fx('rev_p') $$),
  ('DELETE reviews', $$ delete from public.reviews where id = tests.fx('rev_p') $$),
  ('UPDATE review_item_flags', $$ update public.review_item_flags set created_at = now() - interval '1 day' where review_id = tests.fx('rev_p') $$),
  ('DELETE review_item_flags', $$ delete from public.review_item_flags where review_id = tests.fx('rev_p') $$);
grant select on mutations to public;

-- postgres (superusuário local / dono das tabelas): o gatilho barra
select throws_ok(m.sql, 'P0001', 'immutable', 'postgres: ' || m.descr || ' falha')
from (select * from mutations order by ord) as m;                                                -- 8

-- service_role: audit_log sem privilégio; demais barrados pelo gatilho
select tests.authenticate_service_role();
select throws_ok(m.sql, case when m.descr like '%audit_log' then '42501' else 'P0001' end, null,
                 'service_role: ' || m.descr || ' falha')
from (select * from mutations order by ord) as m;                                                -- 8

-- authenticated (proprietária e gerente, que conseguem LER essas linhas): sem privilégio
select tests.authenticate_as('owner_a');
select throws_ok(m.sql, '42501', null, 'proprietária: ' || m.descr || ' falha')
from (select * from mutations order by ord) as m;                                                -- 8

select tests.authenticate_as('manager_p');
select throws_ok(m.sql, '42501', null, 'gerente: ' || m.descr || ' falha')
from (select * from mutations order by ord) as m;                                                -- 8

-- Nada mudou ------------------------------------------------------------------
select tests.reset_role();
select results_eq(
  $$ select (select count(*) from public.evidences where id = tests.fx('ev_p')),
            (select decision::text from public.reviews where id = tests.fx('rev_p')),
            (select count(*) from public.review_item_flags where review_id = tests.fx('rev_p')) $$,
  $$ values (1::bigint, 'rejected'::text, 1::bigint) $$,
  'evidência, revisão e itens reprovados continuam intactos'
);

-- TRUNCATE também é bloqueado (ignoraria os gatilhos de linha)
select throws_ok($$ truncate public.audit_log $$, 'P0001', 'immutable', 'TRUNCATE audit_log falha até para postgres');
select throws_ok($$ truncate public.reviews cascade $$, 'P0001', 'immutable', 'TRUNCATE reviews falha até para postgres');

-- Purga da evidência: só purged_at, uma vez, depois da retenção -----------
-- Foto recebida há 200 dias (retenção da organização: 180)
insert into public.evidences (id, organization_id, store_id, task_id, attempt_id, storage_path, sha256,
                              received_at_server)
select tests.fx('ev_old'), t.organization_id, t.store_id, t.id, tests.fx('att_p'),
       format('%s/%s/%s/%s/%s.jpg', t.organization_id, t.store_id, t.id, tests.fx('att_p'), tests.fx('evfile_old')),
       tests.sha('ev_old'), now() - interval '200 days'
from public.tasks t where t.id = tests.fx('task_p');

select tests.authenticate_service_role();
select throws_ok(
  $$ update public.evidences set purged_at = now(), storage_path = 'outro/caminho.jpg' where id = tests.fx('ev_old') $$,
  'P0001', 'immutable', 'purga não pode mudar outras colunas'
);
select throws_ok(
  $$ update public.evidences set purged_at = now() where id = tests.fx('ev_p') $$,
  'P0001', 'retention_not_reached', 'foto recebida agora não é marcada como removida (retenção de 180 dias)'
);
select lives_ok(
  $$ update public.evidences set purged_at = '1900-01-01' where id = tests.fx('ev_old') $$,
  'job de retenção (chave secreta) preenche purged_at depois do prazo'
);
select tests.reset_role();
select is(
  (select purged_at from public.evidences where id = tests.fx('ev_old')), now(),
  'purged_at é o horário do servidor, não o informado'
);
select tests.authenticate_service_role();
select throws_ok(
  $$ update public.evidences set purged_at = now() + interval '1 day' where id = tests.fx('ev_old') $$,
  'P0001', 'immutable', 'purged_at não muda de novo'
);
select tests.reset_role();
select is(
  (select count(*) from public.audit_log where action = 'evidence_purged' and record_id = tests.fx('ev_old')::text),
  1::bigint,
  'purga registrada no audit_log (evidence_purged)'
);

-- Tentativa enviada e respostas ---------------------------------------------
select throws_ok(
  $$ update public.task_attempts set note = 'reescrita' where id = tests.fx('att_p') $$,
  'P0001', 'immutable', 'tentativa enviada não pode ser alterada'
);
select throws_ok(
  $$ delete from public.task_attempts where id = tests.fx('att_p') $$,
  'P0001', 'immutable', 'tentativa não pode ser apagada'
);
select throws_ok(
  $$ update public.attempt_item_answers set checked = false where attempt_id = tests.fx('att_p') $$,
  'P0001', 'immutable', 'resposta de tentativa enviada não pode ser alterada'
);
select throws_ok(
  $$ delete from public.attempt_item_answers where attempt_id = tests.fx('att_p') $$,
  'P0001', 'immutable', 'resposta de tentativa enviada não pode ser apagada'
);
select throws_ok(
  $$ insert into public.attempt_item_answers (attempt_id, task_item_id, checked)
     values (tests.fx('att_p'), tests.fx('task_p:item1'), true)
     on conflict (attempt_id, task_item_id) do update set checked = excluded.checked $$,
  'P0001', 'immutable', 'resposta nova em tentativa enviada é bloqueada'
);

-- Tentativa aberta: só observação e dados do envio mudam
select tests.create_task('t_aberta', 'store_p', 'sector_p1', 'staff_p1');
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('t_aberta'), tests.fx('cm_aberta'));
select tests.reset_role();

select lives_ok(
  format($$ update public.task_attempts set note = 'rascunho' where id = %L $$, tests.attempt_of('t_aberta', 1)),
  'tentativa aberta aceita observação'
);
select throws_ok(
  format($$ update public.task_attempts set performed_by = %L where id = %L $$, tests.fx('staff_p2'), tests.attempt_of('t_aberta', 1)),
  'P0001', 'immutable', 'tentativa aberta não troca de executor'
);
select throws_ok(
  format($$ update public.task_attempts set started_at = now() - interval '1 day' where id = %L $$, tests.attempt_of('t_aberta', 1)),
  'P0001', 'immutable', 'tentativa aberta não muda o horário de início'
);

select * from finish();
rollback;
