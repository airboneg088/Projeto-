-- =============================================================================
-- 010 · Isolamento entre lojas, papéis e organizações (docs §6)
--   1. Gerente da Primavera (loja P) lê 0 linhas da Castro Alves (loja C) em
--      todas as tabelas operacionais e no storage.
--   2. Gerente P não insere, altera, apaga, cancela nem revisa nada da loja C
--      (DML e RPC).
--   3. Storage: select/insert negados entre lojas nos dois buckets.
--   4. Vínculo encerrado e perfil inativo perdem acesso na hora.
--   5. Colaborador não vê tarefa de outro setor nem de outra pessoa.
--   6. anon não vê nada em lugar nenhum (sem privilégio em nenhuma tabela).
--   7. Dono de outra organização não vê nada da nossa.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(195);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('c');
select tests.create_store_activity('b');

-- Sondas: para cada tabela, uma consulta que conta as linhas de uma loja
create temporary table probe (ord serial primary key, store_key text not null, tbl text not null, sql text not null);
insert into probe (store_key, tbl, sql)
select k.key, t.tbl, format(t.tpl, k.key)
from (values ('p'), ('c')) as k (key)
cross join (
  values
    (1, 'stores', $q$select count(*) from public.stores where id = tests.fx('store_%1$s')$q$),
    (2, 'store_settings', $q$select count(*) from public.store_settings where store_id = tests.fx('store_%1$s')$q$),
    (3, 'sectors', $q$select count(*) from public.sectors where store_id = tests.fx('store_%1$s')$q$),
    (4, 'memberships', $q$select count(*) from public.memberships where store_id = tests.fx('store_%1$s')$q$),
    (5, 'profiles', $q$select count(*) from public.profiles where id in (tests.fx('staff_%1$s1'), tests.fx('manager_%1$s'))$q$),
    (6, 'task_templates', $q$select count(*) from public.task_templates where store_id = tests.fx('store_%1$s')$q$),
    (7, 'template_items', $q$select count(*) from public.template_items where template_id = tests.fx('tpl_%1$s')$q$),
    (8, 'schedules', $q$select count(*) from public.schedules where store_id = tests.fx('store_%1$s')$q$),
    (9, 'tasks', $q$select count(*) from public.tasks where store_id = tests.fx('store_%1$s')$q$),
    (10, 'task_items', $q$select count(*) from public.task_items where task_id = tests.fx('task_%1$s')$q$),
    (11, 'task_attempts', $q$select count(*) from public.task_attempts where store_id = tests.fx('store_%1$s')$q$),
    (12, 'attempt_item_answers', $q$select count(*) from public.attempt_item_answers where attempt_id = tests.fx('att_%1$s')$q$),
    (13, 'evidences', $q$select count(*) from public.evidences where store_id = tests.fx('store_%1$s')$q$),
    (14, 'reviews', $q$select count(*) from public.reviews where task_id = tests.fx('task_%1$s')$q$),
    (15, 'review_item_flags', $q$select count(*) from public.review_item_flags where review_id = tests.fx('rev_%1$s')$q$),
    (16, 'action_plans', $q$select count(*) from public.action_plans where store_id = tests.fx('store_%1$s')$q$),
    (17, 'notifications', $q$select count(*) from public.notifications where store_id = tests.fx('store_%1$s')$q$),
    (18, 'data_requests', $q$select count(*) from public.data_requests where profile_id = tests.fx('staff_%1$s1')$q$),
    (19, 'audit_log', $q$select count(*) from public.audit_log where organization_id = tests.fx('org_a') and diff -> 'store_id' ->> 'new' = tests.fx('store_%1$s')::text$q$),
    (20, 'storage.objects (evidences)', $q$select count(*) from storage.objects where bucket_id = 'evidences' and name like tests.fx('org_a') || '/' || tests.fx('store_%1$s') || '/%%'$q$),
    (21, 'storage.objects (references)', $q$select count(*) from storage.objects where bucket_id = 'references' and name like tests.fx('org_a') || '/' || tests.fx('store_%1$s') || '/%%'$q$)
) as t (n, tbl, tpl)
order by k.key, t.n;

grant select on probe to public;

-- As sondas não são vazias: a fixture tem linhas das duas lojas em todas as tabelas
select ok(tests.count_rows(p.sql) > 0, format('fixture: loja %s tem linhas em %s', p.store_key, p.tbl))
from (select * from probe order by ord) as p;                                                   -- 42

-- 1. Gerente P: 0 linhas da loja C em todas as tabelas -------------------------
select tests.authenticate_as('manager_p');

select is(tests.count_rows(p.sql), 0::bigint, format('gerente P vê 0 linhas da loja C em %s', p.tbl))
from (select * from probe where store_key = 'c' order by ord) as p;                             -- 21

select ok(tests.count_rows(p.sql) > 0, format('gerente P vê a própria loja em %s', p.tbl))
from (
  select * from probe
  where store_key = 'p'
    and tbl in ('stores', 'store_settings', 'sectors', 'memberships', 'task_templates', 'schedules',
                'tasks', 'task_items', 'task_attempts', 'attempt_item_answers', 'evidences', 'reviews',
                'review_item_flags', 'action_plans', 'storage.objects (evidences)', 'storage.objects (references)')
  order by ord
) as p;                                                                                          -- 16

-- 2. Gerente P não escreve na loja C (DML e RPC) -------------------------------
select throws_ok(
  $$ insert into public.tasks (organization_id, store_id, sector_id, title, due_at)
     values (tests.fx('org_a'), tests.fx('store_c'), tests.fx('sector_c1'), 'Invasora', now() + interval '1 day') $$,
  '42501', null, 'gerente P não cria tarefa na loja C'
);
select is(tests.affected_rows($$ update public.tasks set title = 'Alterada' where id = tests.fx('task_c') $$), 0,
  'gerente P não altera tarefa da loja C');
select throws_ok($$ delete from public.tasks where id = tests.fx('task_c') $$, '42501', null,
  'gerente P não apaga tarefa (ninguém apaga tarefas pela API)');
select throws_ok($$ select public.cancel_task(tests.fx('task_c'), 'Tentativa indevida') $$, 'P0001', 'forbidden',
  'gerente P não cancela tarefa da loja C');
select throws_ok($$ select public.review_attempt(tests.fx('att_c_sub'), 'approved') $$, 'P0001', 'forbidden',
  'gerente P não aprova tentativa da loja C');
select throws_ok($$ select public.review_attempt(tests.fx('att_c_sub'), 'rejected', 'Errado') $$, 'P0001', 'forbidden',
  'gerente P não reprova tentativa da loja C');
select throws_ok($$ insert into public.sectors (store_id, name) values (tests.fx('store_c'), 'Invasor') $$, '42501', null,
  'gerente P não cria setor na loja C');
select is(tests.affected_rows($$ update public.sectors set name = 'Alterado' where store_id = tests.fx('store_c') $$), 0,
  'gerente P não altera setor da loja C');
select is(tests.affected_rows($$ update public.schedules set is_active = false where store_id = tests.fx('store_c') $$), 0,
  'gerente P não altera agendamento da loja C');
select throws_ok(
  $$ insert into public.schedules (store_id, template_id, sector_id, window_start, window_end)
     values (tests.fx('store_c'), tests.fx('tpl_c'), tests.fx('sector_c1'), '10:00', '11:00') $$,
  '42501', null, 'gerente P não cria agendamento na loja C'
);
select is(tests.affected_rows($$ update public.task_templates set title = 'Alterada' where id = tests.fx('tpl_c') $$), 0,
  'gerente P não altera rotina da loja C');
select throws_ok(
  $$ insert into public.template_items (template_id, position, text) values (tests.fx('tpl_c'), 9, 'Invasor') $$,
  '42501', null, 'gerente P não inclui item em rotina da loja C'
);
select is(tests.affected_rows($$ delete from public.template_items where template_id = tests.fx('tpl_c') $$), 0,
  'gerente P não remove itens de rotina da loja C');
select is(tests.affected_rows($$ update public.store_settings set due_soon_minutes = 5 where store_id = tests.fx('store_c') $$), 0,
  'gerente P não altera configurações da loja C');
select is(tests.affected_rows($$ update public.memberships set ends_at = now() where store_id = tests.fx('store_c') $$), 0,
  'gerente P não altera vínculos da loja C');
select is(tests.affected_rows($$ update public.action_plans set status = 'done' where store_id = tests.fx('store_c') $$), 0,
  'gerente P não altera plano de ação da loja C');
select throws_ok(
  $$ update public.evidences set purged_at = now() where store_id = tests.fx('store_c') $$,
  '42501', null, 'gerente P não altera evidências (nem da própria loja: só via RPC)'
);

-- 3. Storage entre lojas, nos dois buckets -----------------------------------
select throws_ok(
  format(
    $$ insert into storage.objects (bucket_id, name) values ('evidences', '%s/%s/%s/%s/%s.jpg') $$,
    tests.fx('org_a'), tests.fx('store_c'), tests.fx('task_c'), tests.fx('att_c'), tests.fx('arquivo_invasor')
  ),
  '42501', null, 'gerente P não envia foto de evidência na loja C'
);
select throws_ok(
  format(
    $$ insert into storage.objects (bucket_id, name) values ('references', '%s/%s/%s/%s.jpg') $$,
    tests.fx('org_a'), tests.fx('store_c'), tests.fx('tpl_c'), tests.fx('ref_invasora')
  ),
  '42501', null, 'gerente P não envia imagem de referência na loja C'
);
select lives_ok(
  format(
    $$ insert into storage.objects (bucket_id, name) values ('references', '%s/%s/%s/%s.jpg') $$,
    tests.fx('org_a'), tests.fx('store_p'), tests.fx('tpl_p'), tests.fx('ref_ok')
  ),
  'gerente P envia imagem de referência na própria loja'
);

-- 4. Vínculo encerrado e perfil inativo perdem acesso ------------------------
select tests.reset_role();
select tests.create_task('t_inicio', 'store_p', 'sector_p1', 'staff_p1');

select tests.authenticate_as('staff_p1');
select is(tests.count_rows($$ select count(*) from public.tasks where id in (tests.fx('task_p'), tests.fx('t_inicio')) $$), 2::bigint,
  'colaborador P1 com vínculo vigente vê suas tarefas');

select tests.reset_role();
update public.memberships set ends_at = now() where id = tests.fx('m_staff_p1');
select tests.authenticate_as('staff_p1');

select is(tests.count_rows($$ select count(*) from public.tasks $$), 0::bigint, 'vínculo encerrado: não vê tarefas');
select is(tests.count_rows($$ select count(*) from public.task_attempts $$), 0::bigint, 'vínculo encerrado: não vê as próprias tentativas');
select is(tests.count_rows($$ select count(*) from public.evidences $$), 0::bigint, 'vínculo encerrado: não vê evidências');
select is(tests.count_rows($$ select count(*) from public.stores $$), 0::bigint, 'vínculo encerrado: não vê a loja');
select is(tests.count_rows($$ select count(*) from storage.objects $$), 0::bigint, 'vínculo encerrado: não vê fotos no storage');
select throws_ok($$ select public.start_attempt(tests.fx('t_inicio'), gen_random_uuid()) $$, 'P0001', 'forbidden',
  'vínculo encerrado: não inicia tarefa');

select tests.reset_role();
update public.memberships set ends_at = null where id = tests.fx('m_staff_p1');
update public.profiles set status = 'inactive' where id = tests.fx('staff_p1');
select tests.authenticate_as('staff_p1');

select is(tests.count_rows($$ select count(*) from public.tasks $$), 0::bigint, 'perfil inativo: não vê tarefas');
select is(tests.count_rows($$ select count(*) from public.stores $$), 0::bigint, 'perfil inativo: não vê a loja');
select throws_ok($$ select public.start_attempt(tests.fx('t_inicio'), gen_random_uuid()) $$, 'P0001', 'forbidden',
  'perfil inativo: não inicia tarefa');

select tests.reset_role();
update public.profiles set status = 'active' where id = tests.fx('staff_p1');
update public.memberships set ends_at = now() where id = tests.fx('m_manager_p');
select tests.authenticate_as('manager_p');
select is(tests.count_rows($$ select count(*) from public.tasks $$), 0::bigint, 'gerente com vínculo encerrado: não vê tarefas da loja');
select throws_ok($$ select public.review_attempt(tests.fx('att_p_sub'), 'approved') $$, 'P0001', 'forbidden',
  'gerente com vínculo encerrado: não revisa');

select tests.reset_role();
update public.memberships set ends_at = null where id = tests.fx('m_manager_p');

-- 5. Colaborador não vê tarefa de outro setor nem de outra pessoa ------------
select tests.create_task('t_equipe_s1', 'store_p', 'sector_p1', null);
select tests.create_task('t_equipe_s2', 'store_p', 'sector_p2', null);
select tests.create_task('t_s1_de_p2', 'store_p', 'sector_p1', 'staff_p2');

select tests.authenticate_as('staff_p1');
select is(tests.count_rows($$ select count(*) from public.tasks where id = tests.fx('t_equipe_s1') $$), 1::bigint,
  'colaborador P1 vê tarefa da equipe do seu setor');
select is(tests.count_rows($$ select count(*) from public.tasks where id = tests.fx('t_equipe_s2') $$), 0::bigint,
  'colaborador P1 não vê tarefa de equipe de outro setor');
select is(tests.count_rows($$ select count(*) from public.tasks where id = tests.fx('t_s1_de_p2') $$), 0::bigint,
  'colaborador P1 não vê tarefa atribuída a outra pessoa, mesmo no seu setor');
select is(tests.count_rows($$ select count(*) from public.task_items where task_id = tests.fx('t_equipe_s2') $$), 0::bigint,
  'colaborador P1 não vê itens de tarefa de outro setor');
select throws_ok($$ select public.start_attempt(tests.fx('t_equipe_s2'), gen_random_uuid()) $$, 'P0001', 'forbidden',
  'colaborador P1 não inicia tarefa de outro setor');
select throws_ok($$ select public.start_attempt(tests.fx('t_s1_de_p2'), gen_random_uuid()) $$, 'P0001', 'forbidden',
  'colaborador P1 não inicia tarefa de outra pessoa');
select is(tests.count_rows($$ select count(*) from public.profiles where id <> auth.uid() $$), 0::bigint,
  'colaborador P1 só vê o próprio perfil');
select is(tests.count_rows($$ select count(*) from public.memberships where profile_id <> auth.uid() $$), 0::bigint,
  'colaborador P1 só vê os próprios vínculos');
select is(tests.count_rows($$ select count(*) from public.task_templates $$), 0::bigint,
  'colaborador não lê rotinas (só o snapshot da tarefa)');
select is(tests.count_rows($$ select count(*) from public.store_settings $$), 0::bigint,
  'colaborador não lê configurações da loja');

select tests.authenticate_as('staff_p2');
select is(tests.count_rows($$ select count(*) from public.tasks where id in (tests.fx('t_equipe_s2'), tests.fx('t_s1_de_p2')) $$), 2::bigint,
  'colaborador P2 vê a equipe do seu setor e a tarefa atribuída a ele');
select is(tests.count_rows($$ select count(*) from public.tasks where id in (tests.fx('t_equipe_s1'), tests.fx('task_p')) $$), 0::bigint,
  'colaborador P2 não vê a equipe de outro setor nem tarefa de P1');
select is(tests.count_rows($$ select count(*) from public.task_attempts where performed_by = tests.fx('staff_p1') $$), 0::bigint,
  'colaborador P2 não vê tentativas de P1');
select is(tests.count_rows($$ select count(*) from public.evidences where store_id = tests.fx('store_p') $$), 0::bigint,
  'colaborador P2 não vê evidências de P1');

-- 6. anon não vê nada --------------------------------------------------------
select tests.authenticate_anon();

select throws_ok(format('select count(*) from public.%I', t.relname), '42501', null,
                 format('anon não lê %s (sem privilégio na tabela)', t.relname))
from (
  select c.relname
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
  order by c.relname
) as t;                                                                                          -- 20

select is(tests.count_rows($$ select count(*) from storage.objects $$), 0::bigint, 'anon vê 0 objetos no storage');
select throws_ok($$ select public.start_attempt(tests.fx('t_inicio'), gen_random_uuid()) $$, '42501', null,
  'anon não executa RPC');
select throws_ok($$ select * from public.kpi_summary('2000-01-01', '2100-01-01') $$, '42501', null,
  'anon não executa indicadores');
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('references', '%s/rede/%s/%s.jpg') $$,
         tests.fx('org_a'), tests.fx('tpl_p'), tests.fx('ref_anon')),
  '42501', null, 'anon não envia arquivo'
);

-- 7. Dono de outra organização não vê nada da nossa --------------------------
select tests.authenticate_as('owner_b');

select is(tests.count_rows(p.sql), 0::bigint, format('dono da org B vê 0 linhas da loja %s em %s', p.store_key, p.tbl))
from (select * from probe order by ord) as p;                                                   -- 42

select is(tests.count_rows($$ select count(*) from public.organizations where id = tests.fx('org_a') $$), 0::bigint,
  'dono da org B não vê a organização A');
select is(tests.count_rows($$ select count(*) from public.audit_log where organization_id = tests.fx('org_a') $$), 0::bigint,
  'dono da org B não vê a auditoria da organização A');
select ok(tests.count_rows($$ select count(*) from public.tasks where store_id = tests.fx('store_b') $$) > 0,
  'dono da org B vê as tarefas da própria organização');
select throws_ok($$ select public.cancel_task(tests.fx('task_p'), 'Tentativa indevida') $$, 'P0001', 'forbidden',
  'dono da org B não cancela tarefa da organização A');

select * from finish();
rollback;
