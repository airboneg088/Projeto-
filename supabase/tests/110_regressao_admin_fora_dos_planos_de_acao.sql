-- =============================================================================
-- 110 · Regressão R2-ISO-02: o admin não lê plano de ação (dado operacional,
-- L† na matriz §6) com SELECT direto, nem quando um gerente o indica como
-- responsável: o admin não pode ser responsável por plano e a policy do
-- "responsável lê o seu" não inclui o admin (D15).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(7);

select tests.create_base_fixture();
select tests.create_store_activity('p');

select tests.authenticate_as('admin_a');
select is(tests.count_rows('select count(*) from public.action_plans'), 0::bigint,
  'antes: admin não lê planos de ação');

-- Gerente da loja tenta indicar o admin como responsável
select tests.authenticate_as('manager_p');
select alike(tests.exec_result(format(
  $$ update public.action_plans set owner_id = %L where id = %L $$, tests.fx('admin_a'), tests.fx('ap_p'))),
  '23514:invalid_owner%', 'admin NÃO pode ser responsável por plano (update)');
select alike(tests.exec_result(format(
  $$ insert into public.action_plans (store_id, template_item_id, what, owner_id, status)
     values (%L, %L, 'Conferir o cofre toda noite', %L, 'open') $$,
  tests.fx('store_p'), tests.fx('tpl_p:item2'), tests.fx('admin_a'))),
  '23514:invalid_owner%', 'admin NÃO pode ser responsável por plano (insert)');
-- Controle: proprietária e colaborador da loja podem
select is(tests.exec_result(format(
  $$ update public.action_plans set owner_id = %L where id = %L $$, tests.fx('owner_a'), tests.fx('ap_p'))),
  'ok', 'a proprietária pode ser responsável pelo plano');

-- Mesmo se um plano antigo apontar para o admin (gravado pelo sistema), ele não lê
select tests.reset_role();
alter table public.action_plans disable trigger action_plans_validate;
update public.action_plans set owner_id = tests.fx('admin_a') where id = tests.fx('ap_p');
alter table public.action_plans enable trigger action_plans_validate;

select tests.authenticate_as('admin_a');
select is(tests.count_rows('select count(*) from public.action_plans'), 0::bigint,
  'admin NÃO lê plano de ação direto, mesmo indicado como responsável');
select is(tests.count_rows($$select count(*) from public.action_plans where what like 'Treinar%'$$), 0::bigint,
  'admin NÃO lê o conteúdo (what) do plano');

select tests.authenticate_as('owner_a');
select is(tests.count_rows('select count(*) from public.action_plans'), 1::bigint,
  'controle: a proprietária lê o plano');

select * from finish();
rollback;
