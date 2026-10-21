-- =============================================================================
-- 020 · Máquina de estados da tarefa (docs §2)
-- Todos os 7×7 pares de status: os do grafo passam, os demais levantam
-- invalid_transition — para postgres e service_role. INSERT só como pending.
-- Tarefa aprovada/cancelada não muda mais nenhuma coluna (task_closed).
-- =============================================================================
begin;
\ir helpers/auth.psql
\ir helpers/fixtures.psql

select plan(63);

select tests.create_base_fixture();

-- Grafo exato (função) --------------------------------------------------------
select set_eq(
  $$
    select o::text || ' -> ' || n::text
    from unnest(enum_range(null::public.task_status)) as o
    cross join unnest(enum_range(null::public.task_status)) as n
    where private.task_status_transition_allowed(o, n)
  $$,
  array[
    'pending -> in_progress', 'pending -> overdue', 'pending -> cancelled',
    'in_progress -> submitted', 'in_progress -> overdue', 'in_progress -> cancelled',
    'submitted -> approved', 'submitted -> rejected', 'submitted -> cancelled',
    'rejected -> in_progress', 'rejected -> cancelled',
    'overdue -> in_progress', 'overdue -> submitted', 'overdue -> cancelled'
  ],
  'task_status_transition_allowed: exatamente as 14 transições do grafo (dos 49 pares)'
);

-- Os 42 pares com mudança de status, via UPDATE como postgres ------------------
select case
  when private.task_status_transition_allowed(pairs.f, pairs.t) then
    lives_ok(
      format('update public.tasks set status = %L, cancel_reason = %L where id = %L',
             pairs.t, 'Motivo do teste', tests.task_in_status(pairs.f)),
      format('%s -> %s é permitida', pairs.f, pairs.t)
    )
  else
    throws_ok(
      format('update public.tasks set status = %L, cancel_reason = %L where id = %L',
             pairs.t, 'Motivo do teste', tests.task_in_status(pairs.f)),
      'P0001',
      'invalid_transition',
      format('%s -> %s é bloqueada', pairs.f, pairs.t)
    )
  end
from (
  select a.f, b.t
  from unnest(enum_range(null::public.task_status)) with ordinality as a (f, i)
  cross join unnest(enum_range(null::public.task_status)) with ordinality as b (t, j)
  where a.f <> b.t
  order by a.i, b.j
) as pairs;                                                                                      -- 42

-- Permanecer no mesmo status não é transição (ex.: ajustar o título)
select lives_ok(
  format(
    $$ update public.tasks set status = status, title = 'Título ajustado' where id = any (%L::uuid[]) $$,
    (select array_agg(tests.task_in_status(s))
     from unnest(enum_range(null::public.task_status)) as s
     where s not in ('approved', 'cancelled'))
  ),
  'UPDATE sem mudar o status é aceito em qualquer estado não terminal'
);

-- Terminal é terminal: tarefa aprovada ou cancelada não muda mais nada
select throws_ok(
  format($$ update public.tasks set title = 'Título ajustado' where id = %L $$, tests.task_in_status(s.status)),
  'P0001',
  'task_closed',
  format('tarefa %s não muda mais (nem para postgres)', s.status)
)
from (values ('approved'::public.task_status), ('cancelled')) as s (status);                    -- 2

-- INSERT só como pending ------------------------------------------------------
select lives_ok(
  $$ insert into public.tasks (organization_id, store_id, sector_id, title, due_at, status)
     values (tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Nova', now() + interval '1 day', 'pending') $$,
  'INSERT com status pending é aceito'
);

select throws_ok(
  format(
    $$ insert into public.tasks (organization_id, store_id, sector_id, title, due_at, status, cancel_reason)
       values (%L, %L, %L, 'Nova', now() + interval '1 day', %L, 'Motivo') $$,
    tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), s.status
  ),
  'P0001',
  'invalid_transition',
  format('INSERT direto como %s é bloqueado', s.status)
)
from (
  select st as status
  from unnest(enum_range(null::public.task_status)) with ordinality as e (st, i)
  where st <> 'pending'
  order by i
) as s;                                                                                          -- 6

-- Também para service_role (ignora RLS, mas não o gatilho) --------------------
select tests.authenticate_service_role();

select throws_ok(
  format($$ update public.tasks set status = 'approved' where id = %L $$, tests.task_in_status('pending')),
  'P0001', 'invalid_transition', 'service_role: pending -> approved é bloqueada'
);
select throws_ok(
  format($$ update public.tasks set status = 'in_progress' where id = %L $$, tests.task_in_status('approved')),
  'P0001', 'invalid_transition', 'service_role: approved é terminal'
);
select throws_ok(
  format($$ update public.tasks set status = 'pending', cancel_reason = null where id = %L $$, tests.task_in_status('cancelled')),
  'P0001', 'invalid_transition', 'service_role: cancelled é terminal'
);
select lives_ok(
  format($$ update public.tasks set status = 'overdue' where id = %L $$, tests.task_in_status('in_progress')),
  'service_role: in_progress -> overdue (job de atraso) é permitida'
);
select throws_ok(
  $$ insert into public.tasks (organization_id, store_id, sector_id, title, due_at, status)
     values (tests.fx('org_a'), tests.fx('store_p'), tests.fx('sector_p1'), 'Nova', now() + interval '1 day', 'approved') $$,
  'P0001', 'invalid_transition', 'service_role: INSERT como approved é bloqueado'
);

-- Gerente não muda status direto (só pelas RPCs) ------------------------------
select tests.reset_role();
select tests.create_task('t_gerente', 'store_p', 'sector_p1', 'staff_p1');
select tests.authenticate_as('manager_p');

select throws_ok(
  $$ update public.tasks set status = 'approved' where id = tests.fx('t_gerente') $$,
  '42501', null, 'gerente não altera status com UPDATE direto (privilégio de coluna)'
);
select throws_ok(
  $$ update public.tasks set status = 'cancelled', cancel_reason = 'x' where id = tests.fx('t_gerente') $$,
  '42501', null, 'gerente não cancela com UPDATE direto (usa cancel_task)'
);

-- Cancelamento exige motivo e registra quem/quando -----------------------------
select tests.reset_role();

select throws_ok(
  format($$ update public.tasks set status = 'cancelled', cancel_reason = null where id = %L $$, tests.task_in_status('pending')),
  '23514', null, 'cancelled sem cancel_reason viola a constraint'
);
select throws_ok(
  format($$ update public.tasks set status = 'cancelled', cancel_reason = '   ' where id = %L $$, tests.task_in_status('pending')),
  '23514', null, 'cancelled com motivo em branco viola a constraint'
);

select tests.authenticate_as('manager_p');
select public.cancel_task(tests.fx('t_gerente'), 'Loja fechada para inventário');
select tests.reset_role();

select results_eq(
  $$ select status::text, cancel_reason, cancelled_by, cancelled_at = now() from public.tasks where id = tests.fx('t_gerente') $$,
  $$ values ('cancelled'::text, 'Loja fechada para inventário'::text, tests.fx('manager_p'), true) $$,
  'cancel_task grava status, motivo, quem e quando'
);

select * from finish();
rollback;
