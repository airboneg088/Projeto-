-- =============================================================================
-- Indicadores (docs/modelo-de-dados.md §7). Funções SECURITY INVOKER: a RLS
-- de quem chama filtra os dados (gerente só vê a própria loja, mesmo pedindo
-- outras). Regras comuns:
--   - período por data LOCAL da loja: (due_at at time zone stores.timezone)::date
--   - tarefas cancelled ficam fora de todas as contagens
--   - submitted (aguardando aprovação) nunca conta como aprovada/concluída
--   - atrasada = venceu sem envio (PRODUCT.md §7): não aprovada, prazo vencido e
--     sem envio feito até o prazo que ainda espera revisão ou que só foi revisado
--     depois do prazo (a demora da revisão do gerente não vira atraso de quem
--     executou, nem quando ela reprova depois do prazo; D53, D95)
--   - horário do envio nos prazos = o do aparelho quando veio da fila offline
--     (submitted_at_device, limitado pelo servidor; D94); o tempo envio → revisão
--     usa a chegada ao servidor (o gerente só vê o envio quando ele chega)
--   - percentuais de 0 a 100 com 1 casa decimal; nulos quando o denominador é 0
--   - pessoa da tarefa (nota por pessoa e filtro de pessoa do kpi_summary, a
--     mesma regra nos dois): aprovada = quem executou a tentativa aprovada;
--     vencida e não aprovada = quem estava com a tarefa no prazo (a tentativa
--     iniciada até o prazo e não encerrada antes dele, mesmo que encerrada
--     depois numa reatribuição; sem ela, o responsável no prazo); antes do
--     prazo = quem executou a última tentativa (tentativa encerrada sem envio,
--     de quem passou a tarefa adiante, não conta) ou o responsável atual; nulo =
--     "Sem responsável". Cada tarefa conta para uma pessoa só (D46, D74).
--   - "1ª tentativa" = primeiro ENVIO (tentativa encerrada sem envio, numa
--     passagem da tarefa, não conta; D73); com filtro de pessoa, o primeiro
--     envio DELA na tarefa (quem socorreu uma tarefa reprovada não herda a
--     reprovação de outra pessoa; D96)
--   - itens críticos reprovados, devolvidas e tempo envio → revisão por pessoa
--     contam para quem executou a tentativa revisada (D46, D96)
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
  select case
    -- Vencida e não aprovada: a falha é de quem estava com a tarefa no prazo. Uma
    -- reatribuição depois do prazo (que encerra a tentativa aberta, D52) não tira a falha
    -- dessa pessoa nem a joga em quem só socorreu (D46, D74).
    when t.status <> 'approved' and t.due_at <= now() then coalesce(
      (
        select a.performed_by
        from public.task_attempts a
        where a.task_id = p_task_id
          -- Início pelo aparelho quando veio da fila offline (D72, limitado pelo servidor):
          -- quem abriu a tarefa sem internet antes do prazo estava com ela no prazo (D94)
          and coalesce(a.started_at_device, a.started_at) <= t.due_at
          and (a.abandoned_at is null or a.abandoned_at > t.due_at)
        order by a.attempt_number desc
        limit 1
      ),
      case when p_assignee_at_due_recorded then p_assignee_at_due else p_assignee_id end
    )
    -- Aprovada ou ainda no prazo: quem executou a última tentativa (a aprovada, quando
    -- houver; encerrada sem envio não conta); sem tentativa, o responsável
    else coalesce(
      (
        select a.performed_by
        from public.task_attempts a
        where a.task_id = p_task_id
          and a.abandoned_at is null
        order by a.attempt_number desc
        limit 1
      ),
      case when p_assignee_at_due_recorded then p_assignee_at_due else p_assignee_id end
    )
  end
  from public.tasks t
  where t.id = p_task_id
$$;

comment on function private.task_person(uuid, uuid, uuid, boolean) is
  'Pessoa da tarefa nos indicadores: aprovada = executor da tentativa aprovada; vencida e não aprovada = quem estava com ela no prazo (tentativa iniciada até o prazo, pelo aparelho quando veio da fila offline, e não encerrada antes dele; sem ela, o responsável no prazo, se reatribuída depois de vencer, ou o atual); antes do prazo = executor da última tentativa não encerrada, senão o responsável atual; nulo = equipe sem execução ("Sem responsável").';

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
  -- Tarefas do período e dos filtros de loja e setor (sem o de pessoa)
  with scope as (
    select
      t.id,
      t.status,
      t.requires_approval,
      t.window_start_at,
      t.due_at,
      t.created_at,
      t.assignee_id,
      t.assignee_at_due,
      t.assignee_at_due_recorded
    from public.tasks t
    join public.stores s on s.id = t.store_id
    where t.status <> 'cancelled'
      and (t.due_at at time zone s.timezone)::date between p_from and p_to
      and (p_store_ids is null or t.store_id = any (p_store_ids))
      and (p_sector_ids is null or t.sector_id = any (p_sector_ids))
  ),
  -- Tarefas contadas: com filtro de pessoa, as da pessoa da tarefa (private.task_person)
  base as (
    select sc.id, sc.status, sc.requires_approval, sc.window_start_at, sc.due_at, sc.created_at
    from scope sc
    where p_profile_ids is null
       or private.task_person(sc.id, sc.assignee_id, sc.assignee_at_due, sc.assignee_at_due_recorded)
          = any (p_profile_ids)
  ),
  enriched as (
    select
      b.*,
      fs.first_submitted_at,
      ap.approved_submitted_at,
      ap.approved_first_submission,
      -- Atrasada = venceu sem envio: não aprovada, prazo vencido e sem um envio feito até o
      -- prazo que ainda espera revisão ou que só foi revisado depois do prazo. Enviada a tempo
      -- continua "Aguardando aprovação" mesmo depois do prazo; reprovada depois do prazo fica
      -- em "Pendentes" (Correção solicitada): quem executou não teve como corrigir a tempo
      -- (D95). Enviada depois do prazo, nunca enviada ou reprovada antes do prazo sem novo
      -- envio até ele contam como atrasadas.
      (b.status <> 'approved'
       and b.due_at < now()
       and not exists (
         select 1
         from public.task_attempts a
         left join public.reviews r on r.attempt_id = a.id
         where a.task_id = b.id
           and coalesce(a.submitted_at_device, a.submitted_at) <= b.due_at
           and (r.id is null or r.reviewed_at > b.due_at)
       )) as is_late
    from base b
    left join lateral (
      -- Horário do envio: o do aparelho quando veio da fila offline (D94)
      select min(coalesce(a.submitted_at_device, a.submitted_at)) as first_submitted_at
      from public.task_attempts a
      where a.task_id = b.id
    ) fs on true
    left join lateral (
      select
        coalesce(a.submitted_at_device, a.submitted_at) as approved_submitted_at,
        -- 1ª tentativa = 1º ENVIO: tentativa encerrada sem envio (passagem da tarefa, D52)
        -- continua numerada, mas não é execução de ninguém (D73). Com filtro de pessoa, o 1º
        -- envio DELA na tarefa: quem socorreu uma tarefa reprovada não herda a reprovação de
        -- quem a executou antes (essa conta nas devolvidas de quem executou; D96)
        not exists (
          select 1 from public.task_attempts a2
          where a2.task_id = b.id
            and a2.submitted_at is not null
            and a2.attempt_number < a.attempt_number
            and (p_profile_ids is null or a2.performed_by = a.performed_by)
        ) as approved_first_submission
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
        where e.status = 'approved' and e.requires_approval and e.approved_first_submission
      ) as n_approved_first,
      -- greatest(0, ...): duração nunca negativa (envio antes da abertura da janela,
      -- de dados antigos ou gravados pelo sistema, conta como zero)
      avg(greatest(0, extract(epoch from (e.first_submitted_at - greatest(e.created_at, e.window_start_at))) / 60))
        filter (where e.first_submitted_at is not null) as avg_assign_to_submit
    from enriched e
  ),
  -- Revisões: da loja/setor, das tarefas do período; por pessoa, das tentativas que ELA
  -- executou (a devolvida e a espera pela revisão são de quem enviou, mesmo que outra
  -- pessoa tenha terminado a tarefa; D96). Envio → revisão pela chegada ao servidor: o
  -- gerente só vê o envio quando ele chega.
  review_counts as (
    select
      avg(extract(epoch from (r.reviewed_at - a.submitted_at)) / 60) filter (where not r.is_auto) as avg_submit_to_review,
      count(*) filter (where r.decision = 'rejected') as n_returned
    from public.reviews r
    join public.task_attempts a on a.id = r.attempt_id
    where r.task_id in (select sc.id from scope sc)
      and (p_profile_ids is null or a.performed_by = any (p_profile_ids))
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
  'Indicadores do período (datas locais da loja), sem canceladas. Horário do envio nos prazos = o do aparelho quando veio da fila offline (submitted_at_device, limitado pelo servidor). previstas: due_at no período; executadas: com ao menos uma tentativa enviada; aprovadas: status approved; atrasadas: venceram sem envio = não aprovadas, com due_at < now() e sem envio feito até o prazo que espera revisão ou só foi revisado depois do prazo; pendentes: não aprovadas e não atrasadas (inclui a reprovada depois do prazo); aguardando_aprovacao: submitted e não atrasadas (parte de pendentes); pct_aprovadas_na_janela: aprovadas com a tentativa aprovada enviada entre window_start_at e due_at ÷ previstas; pct_aprovadas_primeira_tentativa: aprovadas com exigência de aprovação no 1º envio (tentativa encerrada sem envio não conta; com filtro de pessoa, o 1º envio dela na tarefa) ÷ aprovadas com exigência de aprovação; media_min_atribuicao_envio: média de max(0, 1º envio − greatest(created_at, window_start_at)) em minutos; media_min_envio_revisao: média de (revisão − chegada do envio ao servidor) nas revisões manuais; devolvidas: revisões rejected; adocao: executadas ÷ previstas. Filtro de pessoa: as tarefas da pessoa da tarefa (private.task_person, a mesma da nota por pessoa); devolvidas e envio → revisão contam as tentativas que a pessoa executou.';

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
  store_id uuid,
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
        -- Setores de mesmo nome existem em todas as lojas: o nome leva a loja
        when p_group = 'sector' then (
          select s.name || ' · ' || sc.name
          from public.sectors sc
          join public.stores s on s.id = sc.store_id
          where sc.id = g.g_id
        )
        else coalesce((select pr.full_name from public.profiles pr where pr.id = g.g_id), 'Nome indisponível')
      end,
      case
        when p_group = 'store' then g.g_id
        when p_group = 'sector' then (select sc.store_id from public.sectors sc where sc.id = g.g_id)
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
  'Nota ponderada por loja, setor ou pessoa: 100 × Σ(peso das aprovadas) ÷ Σ(peso), sem canceladas, sempre com o volume e o peso atribuídos. store_id = loja do grupo (loja ou setor; nulo por pessoa); o nome do setor leva a loja ("Loja · Setor"), porque setores de mesmo nome existem em todas as lojas. person = private.task_person (aprovada: executor da tentativa aprovada; vencida sem aprovação: quem estava com a tarefa no prazo; antes do prazo: executor da última tentativa ou o responsável; nulo = "Sem responsável"), a mesma pessoa do filtro do kpi_summary. criticos_reprovados = marcações de itens críticos em reprovações dessas tarefas, por loja/setor da tarefa ou, por pessoa, para quem executou a tentativa reprovada (pode aparecer com volume 0).';

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
