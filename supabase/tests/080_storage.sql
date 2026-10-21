-- =============================================================================
-- 080 · Storage: policies por caminho em cada bucket e papel
--   evidences  {org}/{loja}/{tarefa}/{tentativa}/{uuid}.jpg
--   references {org}/{loja ou "rede"}/{rotina}/{uuid}.{jpg|png|webp}
-- Inclui truques de caminho: org errada, "..", segmentos a mais/a menos,
-- tentativa de outra pessoa, tentativa enviada. Leitura: ninguém lê
-- storage.objects direto (D77); a regra de leitura é public.can_read_evidence /
-- can_read_reference, que o servidor confere antes de assinar a URL de até 5 min.
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(59);

select tests.create_base_fixture();
select tests.create_task('t1', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.create_task('t2', 'store_p', 'sector_p2', 'staff_p2', p_items => 1);
select tests.create_task('t3', 'store_p', 'sector_p1', 'staff_p1', p_items => 1);
select tests.create_task('tc', 'store_c', 'sector_c1', 'staff_c1', p_items => 1);

-- Tentativas abertas: A1 (P1, t1), A2 (P2, t2), Ac (C1, tc); A3 (P1, t3) enviada
select tests.authenticate_as('staff_p1');
select public.start_attempt(tests.fx('t1'), null);
select public.start_attempt(tests.fx('t3'), null);
select public.answer_item(tests.attempt_of('t3', 1), tests.fx('t3:item1'), true);
select public.submit_attempt(tests.attempt_of('t3', 1));
select tests.authenticate_as('staff_p2');
select public.start_attempt(tests.fx('t2'), null);
select tests.authenticate_as('staff_c1');
select public.start_attempt(tests.fx('tc'), null);
select tests.reset_role();

create temporary table paths as
select
  tests.evidence_path('t1', 1, 'e1') as a1,
  tests.evidence_path('t2', 1, 'e2') as a2,
  tests.evidence_path('t3', 1, 'e3') as a3,
  tests.evidence_path('tc', 1, 'ec') as ac,
  tests.fx('org_a')::text as org_a,
  tests.fx('org_b')::text as org_b,
  tests.fx('store_p')::text as store_p,
  tests.fx('store_c')::text as store_c,
  tests.fx('t1')::text as task1,
  tests.attempt_of('t1', 1)::text as att1,
  tests.attempt_of('t2', 1)::text as att2;
grant select on paths to public;

-- =============================================================================
-- evidences: INSERT
-- =============================================================================
select tests.authenticate_as('staff_p1');

select lives_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('evidences', %L) $$, (select a1 from paths)),
  'executor envia foto no caminho exato da tentativa aberta'
);

select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('evidences', %L) $$, p.path),
  '42501', null, 'evidences: ' || p.descr
)
from (
  select v.n, v.descr, v.path
  from paths x
  cross join lateral (
    values
      (1, 'organização errada', replace(x.a1, x.org_a, x.org_b)),
      (2, 'loja errada', replace(x.a1, x.store_p, x.store_c)),
      (3, 'segmento ..', replace(x.a1, '/' || x.task1 || '/', '/../')),
      (4, 'segmento . ', replace(x.a1, '/' || x.task1 || '/', '/./')),
      (5, 'segmento a mais', replace(x.a1, x.att1 || '/', x.att1 || '/extra/')),
      (6, 'segmento a menos', replace(x.a1, x.task1 || '/', '')),
      (7, 'barra dupla', replace(x.a1, x.att1 || '/', x.att1 || '//')),
      (8, 'tentativa de outra pessoa', x.a2),
      (9, 'tarefa trocada (tentativa de t1 com id de t2)', replace(x.a1, x.task1, tests.fx('t2')::text)),
      (10, 'tentativa já enviada', x.a3),
      (11, 'extensão png', replace(x.a1, '.jpg', '.png')),
      (12, 'nome sem uuid', regexp_replace(x.a1, '[^/]+\.jpg$', 'foto.jpg')),
      (13, 'outra loja da rede', x.ac),
      (14, 'barra no início', '/' || x.a1)
  ) as v (n, descr, path)
  order by v.n
) as p;                                                                                          -- 14

select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('references', %L) $$, (select a1 from paths)),
  '42501', null, 'caminho de evidência no bucket references é recusado'
);

select tests.authenticate_as('manager_p');
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('evidences', %L) $$,
         replace((select a1 from paths), 'e1', 'x')),
  '42501', null, 'gerente não envia foto de evidência (só o executor)'
);

select tests.authenticate_as('owner_a');
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('evidences', %L) $$,
         regexp_replace((select a1 from paths), '[^/]+\.jpg$', tests.fx('dono') || '.jpg')),
  '42501', null, 'proprietária não envia foto de evidência'
);

-- Fotos das outras tentativas (gravadas pelo sistema para os testes de leitura)
select tests.reset_role();
insert into storage.objects (bucket_id, name)
select 'evidences', unnest(array[a2, a3, ac]) from paths;

-- =============================================================================
-- evidences: leitura (D77). Ninguém lê storage.objects direto (com SELECT, o próprio
-- usuário assinaria URLs com o prazo que quisesse, válidas depois de perder o acesso);
-- o servidor confere public.can_read_evidence como o usuário e cria a signed URL de
-- até 5 min com a chave secreta.
-- =============================================================================
create function tests.direct_objects(p_who text, p_bucket text)
returns bigint
language plpgsql
as $$
declare
  v_count bigint;
begin
  perform tests.authenticate_as(p_who);
  select count(*) into v_count from storage.objects where bucket_id = p_bucket;
  perform tests.reset_role();
  return v_count;
end;
$$;
grant execute on function tests.direct_objects(text, text) to public;

select is(
  (select sum(tests.direct_objects(w, 'evidences'))
   from unnest(array['staff_p1', 'staff_p2', 'staff_c1', 'manager_p', 'manager_c', 'owner_a', 'admin_a', 'owner_b']) as w),
  0::numeric,
  'evidences: nenhum papel lê storage.objects direto (nem o executor, nem o gerente, nem a proprietária)');

select tests.authenticate_as('staff_p1');
select ok(public.can_read_evidence((select a1 from paths)) and public.can_read_evidence((select a3 from paths)),
  'evidences: executor P1 abre as próprias fotos (tentativa aberta e enviada)');
select ok(not public.can_read_evidence((select a2 from paths)),
  'evidences: executor P1 não abre a foto de outra pessoa');
select tests.authenticate_as('staff_p2');
select ok(public.can_read_evidence((select a2 from paths)) and not public.can_read_evidence((select a1 from paths)),
  'evidences: colaborador P2 abre só a própria foto');
select tests.authenticate_as('staff_c1');
select ok(public.can_read_evidence((select ac from paths)) and not public.can_read_evidence((select a1 from paths)),
  'evidences: colaborador C1 abre só a própria foto');
select tests.authenticate_as('manager_p');
select ok(public.can_read_evidence((select a1 from paths)) and public.can_read_evidence((select a2 from paths))
          and public.can_read_evidence((select a3 from paths)),
  'evidences: gerente P abre as fotos da loja P');
select ok(not public.can_read_evidence((select ac from paths)),
  'evidences: gerente P não abre foto da loja C');
select tests.authenticate_as('manager_c');
select ok(public.can_read_evidence((select ac from paths)) and not public.can_read_evidence((select a1 from paths)),
  'evidences: gerente C abre só a foto da loja C');
select tests.authenticate_as('owner_a');
select ok((select bool_and(public.can_read_evidence(x)) from paths, unnest(array[a1, a2, a3, ac]) as x),
  'evidences: proprietária abre as fotos da organização');
select tests.authenticate_as('admin_a');
select ok((select not bool_or(public.can_read_evidence(x)) from paths, unnest(array[a1, a2, a3, ac]) as x),
  'evidences: admin não abre fotos operacionais');
select tests.authenticate_as('owner_b');
select ok((select not bool_or(public.can_read_evidence(x)) from paths, unnest(array[a1, a2, a3, ac]) as x),
  'evidences: dono de outra organização não abre nada');
select tests.authenticate_anon();
select throws_ok(format($$ select public.can_read_evidence(%L) $$, (select a1 from paths)), '42501', null,
  'evidences: sem login, a conferência nem roda');

select tests.reset_role();
update public.memberships set ends_at = now() where id = tests.fx('m_staff_p1');
select tests.authenticate_as('staff_p1');
select ok(not public.can_read_evidence((select a1 from paths)),
  'evidences: executor com vínculo encerrado não abre mais as fotos');
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('evidences', %L) $$,
         regexp_replace((select a1 from paths), '[^/]+\.jpg$', tests.fx('depois') || '.jpg')),
  '42501', null, 'evidences: executor com vínculo encerrado não envia foto'
);
select tests.reset_role();
update public.memberships set ends_at = null where id = tests.fx('m_staff_p1');

-- =============================================================================
-- references: INSERT
-- =============================================================================
create temporary table refs (ord serial, who text, path text, allowed boolean, descr text);
insert into refs (who, path, allowed, descr)
select v.who, v.path, v.allowed, v.descr
from paths x
cross join lateral (
  values
    ('manager_p', format('%s/%s/%s/%s.jpg', x.org_a, x.store_p, tests.fx('tpl1'), tests.fx('r1')), true, 'gerente P na loja P (jpg)'),
    ('manager_p', format('%s/%s/%s/%s.png', x.org_a, x.store_p, tests.fx('tpl1'), tests.fx('r2')), true, 'gerente P na loja P (png)'),
    ('manager_p', format('%s/%s/%s/%s.webp', x.org_a, x.store_p, tests.fx('tpl1'), tests.fx('r3')), true, 'gerente P na loja P (webp)'),
    ('manager_p', format('%s/%s/%s/%s.gif', x.org_a, x.store_p, tests.fx('tpl1'), tests.fx('r4')), false, 'gerente P com extensão gif'),
    ('manager_p', format('%s/%s/%s/%s.jpg', x.org_a, x.store_c, tests.fx('tpl1'), tests.fx('r5')), false, 'gerente P na loja C'),
    ('manager_p', format('%s/rede/%s/%s.jpg', x.org_a, tests.fx('tpl1'), tests.fx('r6')), false, 'gerente P na pasta rede'),
    ('manager_p', format('%s/%s/%s/%s.jpg', x.org_b, x.store_p, tests.fx('tpl1'), tests.fx('r7')), false, 'gerente P com organização errada'),
    ('manager_p', format('%s/%s/../%s.jpg', x.org_a, x.store_p, tests.fx('r8')), false, 'gerente P com segmento ..'),
    ('manager_p', format('%s/%s/%s/extra/%s.jpg', x.org_a, x.store_p, tests.fx('tpl1'), tests.fx('r9')), false, 'gerente P com segmento a mais'),
    ('manager_p', format('%s/%s/%s.jpg', x.org_a, x.store_p, tests.fx('r10')), false, 'gerente P com segmento a menos'),
    ('owner_a', format('%s/rede/%s/%s.jpg', x.org_a, tests.fx('tpl2'), tests.fx('r11')), true, 'proprietária na pasta rede'),
    ('owner_a', format('%s/%s/%s/%s.jpg', x.org_a, x.store_c, tests.fx('tpl2'), tests.fx('r12')), true, 'proprietária na loja C'),
    ('owner_a', format('%s/Rede/%s/%s.jpg', x.org_a, tests.fx('tpl2'), tests.fx('r13')), false, 'proprietária com "Rede" (maiúscula)'),
    ('admin_a', format('%s/%s/%s/%s.jpg', x.org_a, x.store_p, tests.fx('tpl3'), tests.fx('r14')), false, 'admin na loja P (D15: conteúdo de rotina)'),
    ('admin_a', format('%s/rede/%s/%s.jpg', x.org_a, tests.fx('tpl3'), tests.fx('r15')), false, 'admin na pasta rede'),
    ('staff_p1', format('%s/%s/%s/%s.jpg', x.org_a, x.store_p, tests.fx('tpl4'), tests.fx('r16')), false, 'colaborador na loja P'),
    ('owner_b', format('%s/rede/%s/%s.jpg', x.org_a, tests.fx('tpl5'), tests.fx('r17')), false, 'dono de outra organização na rede da org A')
) as v (who, path, allowed, descr);
grant select on refs to public;

-- Uma asserção por linha; cada uma autentica a pessoa antes de tentar
create function tests.try_reference_insert(p_who text, p_path text)
returns text
language plpgsql
as $$
begin
  perform tests.authenticate_as(p_who);
  insert into storage.objects (bucket_id, name) values ('references', p_path);
  perform tests.reset_role();
  return 'ok';
exception
  when insufficient_privilege then
    perform tests.reset_role();
    return 'negado';
end;
$$;

select is(
  tests.try_reference_insert(r.who, r.path),
  case when r.allowed then 'ok' else 'negado' end,
  'references: ' || r.descr || case when r.allowed then ' é aceito' else ' é recusado' end
)
from (select * from refs order by ord) as r;                                                     -- 17

-- =============================================================================
-- references: leitura (aceitos acima: P x3, rede x1, C x1), também só pelo servidor (D77)
-- =============================================================================
create temporary table ref_paths as
select format('%s/%s/%s/%s.jpg', x.org_a, x.store_p, tests.fx('tpl1'), tests.fx('r1')) as p1,
       format('%s/rede/%s/%s.jpg', x.org_a, tests.fx('tpl2'), tests.fx('r11')) as rede,
       format('%s/%s/%s/%s.jpg', x.org_a, x.store_c, tests.fx('tpl2'), tests.fx('r12')) as c1
from paths x;
grant select on ref_paths to public;

select is(
  (select sum(tests.direct_objects(w, 'references'))
   from unnest(array['staff_p1', 'manager_c', 'owner_a', 'admin_a', 'owner_b']) as w),
  0::numeric,
  'references: nenhum papel lê storage.objects direto');
select tests.authenticate_as('staff_p1');
select ok(public.can_read_reference((select p1 from ref_paths)) and public.can_read_reference((select rede from ref_paths))
          and not public.can_read_reference((select c1 from ref_paths)),
  'references: colaborador P abre as imagens da loja P e da rede (não as da loja C)');
select tests.authenticate_as('manager_c');
select ok(public.can_read_reference((select c1 from ref_paths)) and public.can_read_reference((select rede from ref_paths))
          and not public.can_read_reference((select p1 from ref_paths)),
  'references: gerente C abre as imagens da loja C e da rede (não as da loja P)');
select tests.authenticate_as('admin_a');
select ok((select not bool_or(public.can_read_reference(x)) from ref_paths, unnest(array[p1, rede, c1]) as x),
  'references: admin NÃO abre imagens de referência (D15: conteúdo de rotina só por função auditada)');
select tests.authenticate_as('owner_a');
select ok((select bool_and(public.can_read_reference(x)) from ref_paths, unnest(array[p1, rede, c1]) as x),
  'references: proprietária abre todas as imagens da organização');
select tests.authenticate_as('owner_b');
select ok((select not bool_or(public.can_read_reference(x)) from ref_paths, unnest(array[p1, rede, c1]) as x),
  'references: dono de outra organização não abre nada');

-- =============================================================================
-- Sem UPDATE/DELETE em storage.objects pela API
-- =============================================================================
select tests.authenticate_as('staff_p1');
select is(tests.affected_rows(format($$ update storage.objects set name = name || '.bak' where name = %L $$, (select a1 from paths))), 0,
  'executor não renomeia/sobrescreve a própria foto');
select is(tests.affected_rows(format($$ delete from storage.objects where name = %L $$, (select a1 from paths))), 0,
  'executor não apaga a própria foto');
select tests.authenticate_as('owner_a');
select is(tests.affected_rows($$ delete from storage.objects $$), 0, 'proprietária não apaga fotos pela API');
select is(tests.affected_rows($$ update storage.objects set metadata = '{}' $$), 0, 'proprietária não altera objetos pela API');

select * from finish();
rollback;
