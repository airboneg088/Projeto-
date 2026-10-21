-- =============================================================================
-- 146 · Regressão R3-ISOLAMENTO-02: quem saiu (vínculo encerrado) ou foi
-- desativado continua podendo abrir pedido do titular (LGPD art. 18; D37, D78),
-- na organização dos vínculos que teve, e só lá; só em nome próprio; e lê só os
-- próprios pedidos. Isso não devolve acesso a mais nada.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(9);

select tests.create_base_fixture();
select tests.create_store_activity('p');

-- Colaborador P2 é desligado (vínculo encerrado)
update public.memberships set ends_at = now() - interval '1 minute' where id = tests.fx('m_staff_p2');
select tests.authenticate_as('staff_p2');
select is(
  tests.exec_result(format(
    $$ insert into public.data_requests (organization_id, profile_id, kind, details)
       values (%L, %L, 'correction', 'Meu nome está errado no histórico') $$,
    tests.fx('org_a'), tests.fx('staff_p2'))),
  'ok', 'desligado (vínculo encerrado) abre pedido de correção');
select is(
  tests.exec_result(format(
    $$ insert into public.data_requests (organization_id, profile_id, kind, details)
       values (%L, %L, 'export', 'Quero meus dados') $$,
    tests.fx('org_a'), tests.fx('staff_p2'))),
  'ok', 'desligado abre pedido de exportação');
select is((select count(*)::int from public.data_requests), 2, 'desligado lê os próprios pedidos');

-- Colaborador P1 é desativado (perfil inativo, vínculo ainda vigente)
select tests.reset_role();
update public.profiles set status = 'inactive' where id = tests.fx('staff_p1');
select tests.authenticate_as('staff_p1');
select is(
  tests.exec_result(format(
    $$ insert into public.data_requests (organization_id, profile_id, kind, details)
       values (%L, %L, 'correction', 'Corrigir meu nome') $$,
    tests.fx('org_a'), tests.fx('staff_p1'))),
  'ok', 'desativado abre pedido de correção');

-- Isolamento continua
select tests.authenticate_as('staff_p2');
select ok(
  tests.exec_result(format(
    $$ insert into public.data_requests (organization_id, profile_id, kind, details)
       values (%L, %L, 'export', 'x') $$,
    tests.fx('org_b'), tests.fx('staff_p2'))) like '42501%',
  'desligado não abre pedido em outra organização');
select ok(
  tests.exec_result(format(
    $$ insert into public.data_requests (organization_id, profile_id, kind, details)
       values (%L, %L, 'correction', 'x') $$,
    tests.fx('org_a'), tests.fx('staff_p1'))) like '42501%',
  'ninguém abre pedido em nome de outra pessoa');
select is((select count(*)::int from public.data_requests where profile_id <> tests.fx('staff_p2')), 0,
  'desligado não lê pedidos de outras pessoas');
select is((select count(*)::int from public.tasks), 0,
  'o canal do titular não devolve acesso à operação (desligado não lê tarefas)');

-- Pessoa sem vínculo nenhum (conta criada e nunca vinculada) não abre pedido
select tests.reset_role();
select tests.create_user('sem_vinculo', '[TESTE] Sem vínculo', 'org_a');
select tests.authenticate_as('sem_vinculo');
select ok(
  tests.exec_result(format(
    $$ insert into public.data_requests (organization_id, profile_id, kind, details)
       values (%L, %L, 'export', 'x') $$,
    tests.fx('org_a'), tests.fx('sem_vinculo'))) like '42501%',
  'conta sem nenhum vínculo não abre pedido (não há organização a quem pedir)');

select * from finish();
rollback;
