-- =============================================================================
-- Indicadores (docs/modelo-de-dados.md §7). Funções SECURITY INVOKER: a RLS
-- de quem chama filtra os dados (gerente só vê a própria loja, mesmo pedindo
-- outras). Regras comuns:
--   - período por data LOCAL da loja: (due_at at time zone stores.timezone)::date
--   - tarefas cancelled ficam fora de todas as contagens
--   - submitted (aguardando aprovação) nunca conta como aprovada/concluída
--   - percentuais de 0 a 100 com 1 casa decimal; nulos quando o denominador é 0
--   - pessoa da tarefa (nota por pessoa e filtro de pessoa do kpi_summary, a
--     mesma regra nos dois): quem executou a última tentativa (a aprovada, se
--     houver); sem tentativa, o responsável no prazo (assignee_at_due, se a
--     tarefa foi reatribuída depois de vencer) ou o atual; nulo = "Sem
--     responsável". Cada tarefa conta para uma pessoa só.
--   - itens críticos reprovados contam para quem executou a tentativa reprovada
-- =============================================================================

-- -----------------------------------------------------------------------------
-- task_person: a pessoa a quem a tarefa é atribuída nos indicadores
-- SECURITY INVOKER: vê só as tentativas que quem chama pode ver.
-- -----------------------------------------------------------------------------
create function private.task_person(
  p_task_id uuid,
  p_assignee_id uuid,
  p_assignee_at_due uuid,
  p_assignee_at_due_recorded boolean
)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (
      select a.performed_by
      from public.task_attempts a
      where a.task_id = p_task_id
      order by a.attempt_number desc
      limit 1
    ),
    case when p_assignee_at_due_recorded then p_assignee_at_due else p_assignee_id end
  )
$$;

comment on function private.task_person(uuid, uuid, uuid, boolean) is
  'Pessoa da tarefa nos indicadores: executor da última tentativa (a aprovada, quando houver); sem tentativa, o responsável no prazo (se reatribuída depois de vencer) ou o atual; nulo = equipe sem execução ("Sem responsável").';

revoke all on function private.task_person(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function private.task_person(uuid, uuid, uuid, boolean) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- kpi_summary
-- -----------------------------------------------------------------------------
create function public.kpi_summary(
  p_from date,
  p_to date,
  p_store_ids uuid[] default null,
  p_sector_ids uuid[] default null,
  p_profile_ids uuid[] default null
)
returns table (
  previstas integer,
  executadas integer,
  aprovadas integer,
  pendentes integer,
  aguardando_aprovacao integer,
  atrasadas integer,
  pct_aprovadas_na_janela numeric,
  pct_aprovadas_primeira_tentativa numeric,
  media_min_atribuicao_envio numeric,
  media_min_envio_revisao numeric,
  devolvidas integer,
  adocao numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select
      t.id,
      t.status,
      t.requires_approval,
      t.window_start_at,
      t.due_at,
      t.created_at,
      (t.status <> 'approved' and t.due_at < now()) as is_late
    from public.tasks t
    join public.stores s on s.id = t.store_id
    where t.status <> 'cancelled'
      and (t.due_at at time zone s.timezone)::date between p_from and p_to
      and (p_store_ids is null or t.store_id = any (p_store_ids))
      and (p_sector_ids is null or t.sector_id = any (p_sector_ids))
      and (
        p_profile_ids is null
        or private.task_person(t.id, t.assignee_id, t.assignee_at_due, t.assignee_at_due_recorded)
           = any (p_profile_ids)
      )
  ),
  enriched as (
    select
      b.*,
      fs.first_submitted_at,
      ap.approved_submitted_at,
      ap.approved_attempt_number
    from base b
    left join lateral (
      select min(a.submitted_at) as first_submitted_at
      from public.task_attempts a
      where a.task_id = b.id
    ) fs on true
    left join lateral (
      select a.submitted_at as approved_submitted_at, a.attempt_number as approved_attempt_number
      from public.reviews r
      join public.task_attempts a on a.id = r.attempt_id
      where r.task_id = b.id and r.decision = 'approved'
      order by r.reviewed_at desc, r.id
      limit 1
    ) ap on true
  ),
  task_counts as (
    select
      count(*) as n_planned,
      count(*) filter (where e.first_submitted_at is not null) as n_executed,
      count(*) filter (where e.status = 'approved') as n_approved,
      count(*) filter (where e.status <> 'approved' and not e.is_late) as n_pending,
      count(*) filter (where e.status = 'submitted' and not e.is_late) as n_awaiting,
      count(*) filter (where e.is_late) as n_late,
      count(*) filter (
        where e.status = 'approved'
          and e.approved_submitted_at >= coalesce(e.window_start_at, '-infinity'::timestamptz)
          and e.approved_submitted_at <= e.due_at
      ) as n_approved_in_window,
      count(*) filter (where e.status = 'approved' and e.requires_approval) as n_approved_manual,
      count(*) filter (
        where e.status = 'approved' and e.requires_approval and e.approved_attempt_number = 1
      ) as n_approved_first,
      -- greatest(0, ...): duração nunca negativa (envio antes da abertura da janela,
      -- de dados antigos ou gravados pelo sistema, conta como zero)
      avg(greatest(0, extract(epoch from (e.first_submitted_at - greatest(e.created_at, e.window_start_at))) / 60))
        filter (where e.first_submitted_at is not null) as avg_assign_to_submit
    from enriched e
  ),
  review_counts as (
    select
      avg(extract(epoch from (r.reviewed_at - a.submitted_at)) / 60) filter (where not r.is_auto) as avg_submit_to_review,
      count(*) filter (where r.decision = 'rejected') as n_returned
    from public.reviews r
    join public.task_attempts a on a.id = r.attempt_id
    where r.task_id in (select b.id from base b)
  )
  select
    tc.n_planned::integer,
    tc.n_executed::integer,
    tc.n_approved::integer,
    tc.n_pending::integer,
    tc.n_awaiting::integer,
    tc.n_late::integer,
    round(100.0 * tc.n_approved_in_window / nullif(tc.n_planned, 0), 1),
    round(100.0 * tc.n_approved_first / nullif(tc.n_approved_manual, 0), 1),
    round(tc.avg_assign_to_submit, 1),
    round(rc.avg_submit_to_review, 1),
    rc.n_returned::integer,
    round(100.0 * tc.n_executed / nullif(tc.n_planned, 0), 1)
  from task_counts tc
  cross join review_counts rc
$$;

comment on function public.kpi_summary(date, date, uuid[], uuid[], uuid[]) is
  'Indicadores do período (datas locais da loja), sem canceladas. previstas: due_at no período; executadas: com ao menos uma tentativa enviada; aprovadas: status approved; atrasadas: não aprovadas com due_at < now(); pendentes: não aprovadas e não atrasadas; aguardando_aprovacao: submitted e não atrasadas (parte de pendentes); pct_aprovadas_na_janela: aprovadas com a tentativa aprovada enviada entre window_start_at e due_at ÷ previstas; pct_aprovadas_primeira_tentativa: aprovadas com exigência de aprovação na 1ª tentativa ÷ aprovadas com exigência de aprovação; media_min_atribuicao_envio: média de max(0, 1º envio − greatest(created_at, window_start_at)) em minutos; media_min_envio_revisao: média de (revisão − envio) nas revisões manuais; devolvidas: revisões rejected; adocao: executadas ÷ previstas. Filtro de pessoa: a pessoa da tarefa (private.task_person, a mesma da nota por pessoa).';

-- -----------------------------------------------------------------------------
-- weighted_scores
-- -----------------------------------------------------------------------------
create function public.weighted_scores(
  p_from date,
  p_to date,
  p_group text,
  p_store_ids uuid[] default null
)
returns table (
  group_id uuid,
  group_name text,
  volume integer,
  peso_total integer,
  nota numeric,
  criticos_reprovados integer
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_group is null or p_group not in ('store', 'sector', 'person') then
    raise exception 'invalid_group'
      using errcode = '22023', detail = 'Agrupamento deve ser store, sector ou person.';
  end if;

  return query
    with base as (
      select
        t.id as b_task_id,
        t.store_id as b_store_id,
        t.sector_id as b_sector_id,
        private.task_person(t.id, t.assignee_id, t.assignee_at_due, t.assignee_at_due_recorded) as b_person_id,
        t.weight as b_weight,
        t.status as b_status
      from public.tasks t
      join public.stores s on s.id = t.store_id
      where t.status <> 'cancelled'
        and (t.due_at at time zone s.timezone)::date between p_from and p_to
        and (p_store_ids is null or t.store_id = any (p_store_ids))
    ),
    attributed as (
      select
        b.*,
        case p_group
          when 'store' then b.b_store_id
          when 'sector' then b.b_sector_id
          else b.b_person_id
        end as b_group_id
      from base b
    ),
    -- Item crítico reprovado conta para a loja/setor da tarefa ou, por pessoa, para
    -- quem executou a tentativa reprovada (não para quem corrigiu depois)
    critical_flags as (
      select
        case p_group
          when 'store' then b.b_store_id
          when 'sector' then b.b_sector_id
          else a.performed_by
        end as c_group_id,
        count(*) as c_count
      from public.review_item_flags f
      join public.reviews r on r.id = f.review_id
      join public.task_attempts a on a.id = r.attempt_id
      join public.task_items ti on ti.id = f.task_item_id
      join base b on b.b_task_id = r.task_id
      where ti.is_critical
      group by 1
    ),
    volumes as (
      select
        ab.b_group_id as v_id,
        count(*) as v_volume,
        sum(ab.b_weight) as v_weight,
        coalesce(sum(ab.b_weight) filter (where ab.b_status = 'approved'), 0) as v_weight_approved
      from attributed ab
      group by ab.b_group_id
    ),
    -- Quem só tem crítico reprovado (outra pessoa corrigiu) aparece com volume 0
    grouped as (
      select
        coalesce(v.v_id, cf.c_group_id) as g_id,
        coalesce(v.v_volume, 0) as g_volume,
        coalesce(v.v_weight, 0) as g_weight,
        coalesce(v.v_weight_approved, 0) as g_weight_approved,
        coalesce(cf.c_count, 0) as g_critical
      from volumes v
      full join critical_flags cf
        on coalesce(cf.c_group_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = coalesce(v.v_id, '00000000-0000-0000-0000-000000000000'::uuid)
    )
    select
      g.g_id,
      case
        when g.g_id is null then 'Sem responsável'
        when p_group = 'store' then (select s.name from public.stores s where s.id = g.g_id)
        when p_group = 'sector' then (select sc.name from public.sectors sc where sc.id = g.g_id)
        else coalesce((select pr.full_name from public.profiles pr where pr.id = g.g_id), 'Nome indisponível')
      end,
      g.g_volume::integer,
      g.g_weight::integer,
      round(100.0 * g.g_weight_approved / nullif(g.g_weight, 0), 1),
      g.g_critical::integer
    from grouped g
    order by g.g_id is null, 2, 1;
end;
$$;

comment on function public.weighted_scores(date, date, text, uuid[]) is
  'Nota ponderada por loja, setor ou pessoa: 100 × Σ(peso das aprovadas) ÷ Σ(peso), sem canceladas, sempre com o volume e o peso atribuídos. person = private.task_person (executor da última tentativa; sem tentativa, o responsável no prazo ou o atual; nulo = "Sem responsável"), a mesma pessoa do filtro do kpi_summary. criticos_reprovados = marcações de itens críticos em reprovações dessas tarefas, por loja/setor da tarefa ou, por pessoa, para quem executou a tentativa reprovada (pode aparecer com volume 0).';

-- -----------------------------------------------------------------------------
-- top_failed_items
-- -----------------------------------------------------------------------------
create function public.top_failed_items(
  p_from date,
  p_to date,
  p_store_ids uuid[] default null,
  p_limit integer default 10
)
returns table (
  template_item_id uuid,
  item_text text,
  template_title text,
  store_id uuid,
  store_name text,
  reprovacoes integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    ti.template_item_id,
    (array_agg(ti.text order by t.due_at desc, ti.id))[1],
    (array_agg(t.title order by t.due_at desc, t.id))[1],
    t.store_id,
    s.name,
    count(*)::integer
  from public.review_item_flags f
  join public.reviews r on r.id = f.review_id
  join public.task_items ti on ti.id = f.task_item_id
  join public.tasks t on t.id = r.task_id
  join public.stores s on s.id = t.store_id
  where r.decision = 'rejected'
    and t.status <> 'cancelled'
    and ti.template_item_id is not null
    and (t.due_at at time zone s.timezone)::date between p_from and p_to
    and (p_store_ids is null or t.store_id = any (p_store_ids))
  group by ti.template_item_id, t.store_id, s.name
  order by count(*) desc, s.name, 2, 1
  limit greatest(coalesce(p_limit, 10), 0)
$$;

comment on function public.top_failed_items(date, date, uuid[], integer) is
  'Itens mais reprovados (falhas recorrentes) por item da rotina e loja no período, sem canceladas. Texto e título vêm do snapshot mais recente.';

revoke execute on function public.kpi_summary(date, date, uuid[], uuid[], uuid[]) from public, anon;
revoke execute on function public.weighted_scores(date, date, text, uuid[]) from public, anon;
revoke execute on function public.top_failed_items(date, date, uuid[], integer) from public, anon;
grant execute on function public.kpi_summary(date, date, uuid[], uuid[], uuid[]) to authenticated;
grant execute on function public.weighted_scores(date, date, text, uuid[]) to authenticated;
grant execute on function public.top_failed_items(date, date, uuid[], integer) to authenticated;
