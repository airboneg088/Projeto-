-- =============================================================================
-- 114 · Regressão R2-ISO-06: o admin não lista, não lê e não envia imagens de
-- referência das rotinas (bucket references). A imagem e o caminho
-- ({org}/{loja}/{id da rotina}/...) são conteúdo de rotina, que o admin só lê
-- por funções auditadas (D15); ele também não cria nem edita rotinas.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(7);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('c');
insert into storage.objects (bucket_id, name)
values ('references', format('%s/rede/%s/%s.jpg', tests.fx('org_a'), tests.fx('tpl_rede'), tests.fx('ref_rede')));

select tests.authenticate_as('admin_a');
select is(tests.count_rows($$ select count(*) from public.task_templates $$), 0::bigint,
  'controle: admin não lê rotinas direto');
select is(tests.count_rows($$ select count(*) from storage.objects where bucket_id = 'references' $$), 0::bigint,
  'admin NÃO lista as imagens de referência das rotinas (lojas e rede)');
select is(tests.count_rows(format($$ select count(*) from storage.objects
                                     where bucket_id = 'references' and name like %L $$,
                                   '%/' || tests.fx('tpl_p') || '/%')), 0::bigint,
  'admin NÃO descobre o id da rotina da loja P pelo caminho do arquivo');
select throws_ok(format(
  $$ insert into storage.objects (bucket_id, name) values ('references', %L) $$,
  format('%s/%s/%s/%s.jpg', tests.fx('org_a'), tests.fx('store_p'), tests.fx('tpl_p'), tests.fx('ref_admin'))),
  '42501', null, 'admin NÃO envia imagem de referência de loja');
select throws_ok(format(
  $$ insert into storage.objects (bucket_id, name) values ('references', %L) $$,
  format('%s/rede/%s/%s.jpg', tests.fx('org_a'), tests.fx('tpl_rede'), tests.fx('ref_admin2'))),
  '42501', null, 'admin NÃO envia imagem de referência da rede');

-- Controle: colaborador da loja P lê as imagens da loja P e da rede
select tests.authenticate_as('staff_p1');
select is(tests.count_rows($$ select count(*) from storage.objects where bucket_id = 'references' $$), 2::bigint,
  'colaborador P lê as imagens da loja P e da rede');
select tests.authenticate_as('owner_a');
select is(tests.count_rows($$ select count(*) from storage.objects where bucket_id = 'references' $$), 3::bigint,
  'proprietária lê as imagens de todas as lojas e da rede');

select * from finish();
rollback;
