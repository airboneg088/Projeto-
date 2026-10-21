-- =============================================================================
-- 149 · Regressão R3-ISOLAMENTO-05: o slug da organização não muda pela API
-- (D84). Ele é único no banco inteiro: trocar o próprio slug pelo de outra
-- organização respondia 23505 e revelava que ela existe. O admin continua
-- alterando nome e retenção de fotos.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(5);

select tests.create_base_fixture();

select ok(not has_column_privilege('authenticated', 'public.organizations', 'slug', 'UPDATE'),
  'authenticated não tem UPDATE no slug');

select tests.authenticate_as('admin_a');
select throws_ok(
  format($$ update public.organizations set slug = 'teste-b' where id = %L $$, tests.fx('org_a')),
  '42501', null, 'slug de outra organização: mesma recusa de privilégio (sem oráculo 23505)');
select throws_ok(
  format($$ update public.organizations set slug = 'livre-qualquer' where id = %L $$, tests.fx('org_a')),
  '42501', null, 'slug livre: a mesma recusa');
select is(
  tests.affected_rows(format($$ update public.organizations set name = 'Org Teste A (nova)', photo_retention_days = 90 where id = %L $$,
                             tests.fx('org_a'))),
  1, 'admin continua alterando nome e retenção de fotos');

select tests.reset_role();
select is((select slug from public.organizations where id = tests.fx('org_a')), 'teste-a', 'o slug não mudou');

select * from finish();
rollback;
