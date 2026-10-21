-- =============================================================================
-- 135 · Regressão R2-REGRAS-S2 (R1-REGRAS-09): weighted_scores('sector') não
-- devolve linhas indistinguíveis quando lojas diferentes têm setores de mesmo
-- nome (o seed tem "Caixa", "Estoque", "Limpeza" e "Salão de vendas" em cada
-- loja): o nome do setor leva a loja ("Loja · Setor") e a função devolve a loja
-- do grupo (store_id).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(3);

select tests.create_base_fixture();
update public.sectors set name = 'Salão' where id in (tests.fx('sector_p1'), tests.fx('sector_c1'));
select tests.create_task('sp', 'store_p', 'sector_p1', 'staff_p1');
select tests.create_task('sc', 'store_c', 'sector_c1', 'staff_c1');

create temporary table periodo as
  select (now() at time zone 'America/Sao_Paulo')::date - 1 as de,
         (now() at time zone 'America/Sao_Paulo')::date + 2 as ate;
grant select on periodo to public;

select tests.authenticate_as('owner_a');
select is(
  (select count(distinct group_name)::int
   from periodo, public.weighted_scores(periodo.de, periodo.ate, 'sector')),
  2, 'duas lojas com setor "Salão": dois nomes diferentes');
select set_eq(
  $$ select group_id, group_name, store_id, volume
     from periodo, public.weighted_scores(periodo.de, periodo.ate, 'sector') $$,
  format($$ values (%L::uuid, 'Loja P Teste · Salão'::text, %L::uuid, 1),
                   (%L::uuid, 'Loja C Teste · Salão'::text, %L::uuid, 1) $$,
         tests.fx('sector_p1'), tests.fx('store_p'), tests.fx('sector_c1'), tests.fx('store_c')),
  'cada setor vem com a loja no nome e no store_id');
select is(
  (select count(*)::int
   from periodo, public.weighted_scores(periodo.de, periodo.ate, 'person')
   where store_id is not null),
  0, 'por pessoa não há loja do grupo (a pessoa pode ter passado por mais de uma loja)');

select * from finish();
rollback;
