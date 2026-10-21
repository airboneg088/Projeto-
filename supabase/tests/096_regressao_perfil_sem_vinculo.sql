-- =============================================================================
-- 096 · Regressão R1-ISO-07: admin de uma organização não desativa nem enxerga
-- perfis sem vínculo de outra organização.
--   - set_profile_status exige vínculo do alvo na organização do admin (sem a
--     exceção "ainda sem vínculo"); inexistente e alheio dão o mesmo erro.
--   - Perfil sem vínculo só aparece para o admin da organização gravada na
--     conta (auth app_metadata.organization_id, definida por quem cria a conta).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(8);

select tests.create_base_fixture();
select tests.create_user('novo_b', '[TESTE] Pessoa nova da org B');
select tests.create_user('novo_a', '[TESTE] Pessoa nova da org A');
select tests.create_user('novo_sem_org', '[TESTE] Pessoa nova sem organização na conta');
update auth.users
   set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('organization_id', tests.fx('org_b'))
 where id = tests.fx('novo_b');
update auth.users
   set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('organization_id', tests.fx('org_a'))
 where id = tests.fx('novo_a');

select tests.authenticate_as('admin_a');
select throws_ok($$ select public.set_profile_status(tests.fx('novo_b'), 'inactive') $$,
  'P0001', 'forbidden', 'admin da org A NÃO desativa perfil sem vínculo (pode ser de outra organização)');
select throws_ok($$ select public.set_profile_status(tests.fx('novo_a'), 'inactive') $$,
  'P0001', 'forbidden', 'nem perfil sem vínculo da própria organização (só quem tem vínculo)');
select throws_ok($$ select public.set_profile_status(gen_random_uuid(), 'inactive') $$,
  'P0001', 'forbidden', 'perfil inexistente dá o mesmo erro');

select is(tests.count_rows($$ select count(*) from public.profiles where id = tests.fx('novo_b') $$), 0::bigint,
  'admin da org A NÃO vê perfil criado para a org B');
select is(tests.count_rows($$ select count(*) from public.profiles where id = tests.fx('novo_sem_org') $$), 0::bigint,
  'admin da org A NÃO vê perfil sem organização na conta');
select is(tests.count_rows($$ select count(*) from public.profiles where id = tests.fx('novo_a') $$), 1::bigint,
  'admin da org A vê o perfil criado para a org A (para cadastrar o vínculo)');

select tests.reset_role();
select results_eq(
  $$ select status::text from public.profiles where id in (tests.fx('novo_b'), tests.fx('novo_a')) order by 1 $$,
  $$ values ('active'::text), ('active'::text) $$,
  'perfis sem vínculo continuam ativos'
);

-- Com vínculo na organização, o admin passa a poder desativar
insert into public.memberships (profile_id, organization_id, store_id, sector_id, role)
values (tests.fx('novo_a'), tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'staff');
select tests.authenticate_as('admin_a');
select lives_ok($$ select public.set_profile_status(tests.fx('novo_a'), 'inactive') $$,
  'com vínculo na organização, o admin desativa');

select * from finish();
rollback;
