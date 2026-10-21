-- =============================================================================
-- 154 · Regressão R4-ISOLAMENTO-01 / R4-INTEGRIDADE-02: can_read_evidence e
-- can_read_reference conferem o caminho INTEIRO (como o upload), não só o começo.
-- O servidor assina com a chave secreta o mesmo texto conferido, e o storage-js
-- monta a URL por concatenação; o fetch (WHATWG URL) troca "\" por "/" e resolve
-- "..". Um 5º segmento livre ("..\..\..\..\<caminho da org B com \>") passava
-- como "foto da própria tentativa" e a URL assinada era de outra loja,
-- organização ou bucket (D92).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(12);

select tests.create_base_fixture();
select tests.create_store_activity('p');
select tests.create_store_activity('c');
select tests.create_store_activity('b');

create temporary table caminho as
select
  format('%s/%s/%s/%s/%s.jpg', tests.fx('org_a'), tests.fx('store_p'), tests.fx('task_p'), tests.fx('att_p'),
         tests.fx('evfile_p')) as foto_p,
  format('%s/%s/%s/%s/%s.jpg', tests.fx('org_a'), tests.fx('store_c'), tests.fx('task_c'), tests.fx('att_c'),
         tests.fx('evfile_c')) as foto_c,
  format('%s/%s/%s/%s/%s.jpg', tests.fx('org_b'), tests.fx('store_b'), tests.fx('task_b'), tests.fx('att_b'),
         tests.fx('evfile_b')) as foto_b,
  format('%s/%s/%s/%s.png', tests.fx('org_a'), tests.fx('store_p'), tests.fx('tpl_p'), tests.fx('reffile_p')) as ref_p,
  format('%s/rede/%s/%s.webp', tests.fx('org_a'), tests.fx('tpl_p'), tests.fx('reffile_p')) as ref_rede,
  format('%s/%s/%s/%s.jpg', tests.fx('org_b'), tests.fx('store_b'), tests.fx('tpl_b'), tests.fx('reffile_b')) as ref_b;
grant select on caminho to public;

-- Caminhos "da própria tentativa/loja" que a URL resolve para outro objeto
create temporary table atalho as
select
  format('%s/%s/%s/%s/..\..\..\..\%s', tests.fx('org_a'), tests.fx('store_p'), tests.fx('task_p'), tests.fx('att_p'),
         replace(c.foto_c, '/', '\')) as para_loja_c,
  format('%s/%s/%s/%s/..\..\..\..\%s', tests.fx('org_a'), tests.fx('store_p'), tests.fx('task_p'), tests.fx('att_p'),
         replace(c.foto_b, '/', '\')) as para_org_b,
  format('%s/rede/x/..\..\..\%s', tests.fx('org_a'), replace(c.ref_b, '/', '\')) as ref_para_org_b,
  format('%s/rede/x/..\..\..\..\evidences\%s', tests.fx('org_a'), replace(c.foto_b, '/', '\')) as ref_para_evidences,
  format('%s/%s/%s/%s/qualquer?coisa#aqui', tests.fx('org_a'), tests.fx('store_p'), tests.fx('task_p'),
         tests.fx('att_p')) as nome_livre,
  format('%s/%s/%s/%s.jpg', tests.fx('org_a'), tests.fx('store_p'), 'x', tests.fx('reffile_p')) as ref_rotina_livre
from caminho c;
grant select on atalho to public;

-- Colaborador executor da tentativa da loja P
select tests.authenticate_as('staff_p1');
select ok(public.can_read_evidence((select foto_p from caminho)), 'executor lê a foto da própria tentativa');
select ok(not public.can_read_evidence((select foto_c from caminho))
          and not public.can_read_evidence((select foto_b from caminho)),
  'executor não lê a foto da loja C nem a da organização B pelo caminho direto');
select ok(not public.can_read_evidence((select para_loja_c from atalho)),
  'evidências: caminho com "\" e ".." que resolve para a foto da loja C é recusado');
select ok(not public.can_read_evidence((select para_org_b from atalho)),
  'evidências: caminho com "\" e ".." que resolve para a foto da organização B é recusado');
select ok(not public.can_read_evidence((select nome_livre from atalho)),
  'evidências: o nome do arquivo precisa ser {uuid}.jpg (como no upload)');
select ok(public.can_read_reference((select ref_p from caminho))
          and public.can_read_reference((select ref_rede from caminho)),
  'referências: colaborador lê a imagem da loja e da rede pelo caminho exato');
select ok(not public.can_read_reference((select ref_para_org_b from atalho)),
  'referências: caminho da pasta "rede" que resolve para a imagem da organização B é recusado');
select ok(not public.can_read_reference((select ref_para_evidences from atalho)),
  'referências: caminho que sai do bucket references (para evidences da organização B) é recusado');
select ok(not public.can_read_reference((select ref_rotina_livre from atalho)),
  'referências: a rotina do caminho precisa ser um uuid (como no upload)');

-- Gerente da loja P: lê toda foto da loja P, nenhuma da loja C
select tests.authenticate_as('manager_p');
select ok(public.can_read_evidence((select foto_p from caminho)), 'gerente P lê a foto da loja P');
select ok(not public.can_read_evidence((select para_loja_c from atalho)),
  'gerente P não passa na conferência com caminho que resolve para a foto da loja C');
select ok(not public.can_read_evidence((select para_org_b from atalho)),
  'gerente P não passa na conferência com caminho que resolve para a organização B');

select tests.reset_role();
select * from finish();
rollback;
