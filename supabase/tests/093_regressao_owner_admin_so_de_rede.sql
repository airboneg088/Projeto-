-- =============================================================================
-- 093 · Regressão R1-ISO-04: owner/admin "de uma loja só" não existe.
--   - CHECK: owner e admin sempre com store_id nulo; gerente e colaborador
--     sempre com loja.
--   - Defesa extra: mesmo que uma linha assim existisse (CHECK removido só
--     dentro deste teste), as funções de acesso não a contam como papel de
--     rede: não lê vínculos/auditoria da loja C nem se dá vínculo lá.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(12);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('c');
select tests.create_user('owner_loja_p', '[TESTE] Proprietária só da loja P');
select tests.create_user('admin_loja_p', '[TESTE] Admin só da loja P');

-- CHECK -------------------------------------------------------------------------
select throws_ok(
  format($$ insert into public.memberships (profile_id, organization_id, store_id, role) values (%L, %L, %L, %L) $$,
         tests.fx(p.who), tests.fx('org_a'), tests.fx('store_p'), p.role),
  '23514', null, format('vínculo %s com loja é recusado (CHECK memberships_store_required)', p.role)
)
from (values ('owner_loja_p', 'owner'), ('admin_loja_p', 'admin')) as p (who, role);           -- 2

-- Defesa extra: linha "owner/admin de loja" gravada sem o CHECK ------------------
alter table public.memberships drop constraint memberships_store_required;
insert into public.memberships (profile_id, organization_id, store_id, role, starts_at)
values (tests.fx('owner_loja_p'), tests.fx('org_a'), tests.fx('store_p'), 'owner', now() - interval '1 day'),
       (tests.fx('admin_loja_p'), tests.fx('org_a'), tests.fx('store_p'), 'admin', now() - interval '1 day');

select tests.authenticate_as('owner_loja_p');
select ok(not (select private.is_owner()), 'owner com loja não conta como proprietária');
select is(tests.count_rows($$ select count(*) from public.memberships where store_id = tests.fx('store_c') $$), 0::bigint,
  'owner só da loja P NÃO lê vínculos da loja C');
select is(tests.count_rows($$ select count(*) from public.audit_log $$), 0::bigint,
  'owner só da loja P NÃO lê a auditoria da organização');
select cmp_ok(
  tests.rows_result(format($$ insert into public.memberships (profile_id, organization_id, store_id, role) values (%L, %L, %L, 'manager') $$,
                        tests.fx('owner_loja_p'), tests.fx('org_a'), tests.fx('store_c'))),
  '<=', 0, 'owner só da loja P NÃO se dá vínculo de gerente na loja C');
select is(tests.count_rows($$ select count(*) from public.tasks where store_id = tests.fx('store_c') $$), 0::bigint,
  'owner só da loja P continua sem ver tarefas da loja C');

select tests.authenticate_as('admin_loja_p');
select ok(not (select private.is_admin()), 'admin com loja não conta como admin');
select is(tests.count_rows($$ select count(*) from public.memberships where store_id = tests.fx('store_c') $$), 0::bigint,
  'admin só da loja P NÃO lê vínculos da loja C');
select cmp_ok(
  tests.rows_result($$ update public.memberships set ends_at = now() + interval '1 hour' where profile_id = tests.fx('manager_c') $$),
  '<=', 0, 'admin só da loja P NÃO encerra o vínculo do gerente da loja C');
select cmp_ok(
  tests.rows_result(format($$ insert into public.memberships (profile_id, organization_id, store_id, role) values (%L, %L, %L, 'manager') $$,
                        tests.fx('admin_loja_p'), tests.fx('org_a'), tests.fx('store_c'))),
  '<=', 0, 'admin só da loja P NÃO se dá vínculo de gerente na loja C');
select is((select private.current_store_ids('{owner,admin}'::public.membership_role[])), '{}'::uuid[],
  'admin com loja não ganha loja nenhuma como owner/admin');

select * from finish();
rollback;
