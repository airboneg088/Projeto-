-- =============================================================================
-- Privilégios das roles da API sobre as tabelas de public.
--
-- No Supabase hospedado, tudo que o postgres cria em public recebe ALL para
-- anon, authenticated e service_role. Aqui fechamos o que a RLS não cobre:
--   - anon: nenhum privilégio em tabela ou sequência de public (não há policy
--     para anon; sem privilégio a chave publicável nem lista as tabelas no
--     OpenAPI do PostgREST).
--   - TRUNCATE ignora a RLS e os gatilhos por linha (auditoria): nenhuma role
--     da API trunca, nem a service_role. REFERENCES e TRIGGER não fazem
--     sentido para a API.
--   - authenticated só tem o comando quando existe policy para ele (sem DELETE
--     em vínculos, lojas, configurações, planos e pedidos LGPD; sem INSERT em
--     organizações e configurações).
--   - Tabelas escritas só por funções RPC/sistema perdem INSERT/UPDATE/DELETE.
--   - Privilégios por coluna: só as colunas que a pessoa pode informar. id
--     (gerado pelo banco: um id escolhido pelo cliente revelaria, pela chave
--     primária, ids que existem em outra organização), created_at, updated_at,
--     created_by, version, contadores do sistema e chaves de escopo (pessoa,
--     organização, loja) não são graváveis depois.
--   - audit_log: ninguém da API insere, nem service_role.
--   - tasks: ninguém da API apaga, nem service_role (cancela-se com motivo).
--
-- Funções: o EXECUTE padrão do Postgres vem de PUBLIC (que anon e
-- authenticated herdam) e só sai com o padrão GLOBAL (sem "in schema"). Daqui
-- em diante, função nova criada pelo postgres nasce sem EXECUTE para PUBLIC:
-- em public fica só para authenticated e service_role (padrão do schema) e em
-- private só para o dono, até um grant explícito. As funções das migrations
-- anteriores já revogam de public e anon uma a uma (o teste 001 confere).
-- =============================================================================

-- anon: nada em tabelas e sequências de public, nem nas futuras
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke all on functions from anon;
-- Global: o EXECUTE de PUBLIC só sai assim (o padrão por schema só acrescenta)
alter default privileges for role postgres revoke execute on functions from public;

revoke truncate, references, trigger on all tables in schema public from authenticated;
revoke truncate on all tables in schema public from service_role;

-- Tabelas futuras criadas pelo postgres em public também nascem sem esses privilégios
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger on tables from authenticated;
alter default privileges for role postgres in schema public
  revoke truncate on tables from service_role;

-- Postgres 17+: MAINTAIN (VACUUM, LOCK TABLE...) também fica fora da API
do $$
begin
  if current_setting('server_version_num')::integer >= 170000 then
    execute 'revoke maintain on all tables in schema public from authenticated';
    execute 'alter default privileges for role postgres in schema public revoke maintain on tables from authenticated';
  end if;
end;
$$;

-- Escrita só pelas funções RPC (SECURITY DEFINER)
revoke insert, update, delete on public.task_attempts from authenticated;
revoke insert, update, delete on public.attempt_item_answers from authenticated;
revoke insert, update, delete on public.evidences from authenticated;
revoke insert, update, delete on public.reviews from authenticated;
revoke insert, update, delete on public.review_item_flags from authenticated;

-- Auditoria: só código SECURITY DEFINER grava; nem a chave secreta insere direto
revoke insert, update, delete on public.audit_log from authenticated, service_role;
revoke all on sequence public.audit_log_id_seq from authenticated, service_role;

-- Perfis: criados pelo gatilho do Auth; a pessoa só altera o próprio nome
revoke insert, update, delete on public.profiles from authenticated;
grant update (full_name) on public.profiles to authenticated;

-- Notificações: geradas pelo sistema; a pessoa só marca como lida
revoke insert, update, delete on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

-- Organização: admin altera dados (sem criar nem apagar pela API)
revoke insert, update, delete on public.organizations from authenticated;
-- slug fica fora (D84): é único no banco inteiro, e trocar o próprio slug pelo de outra
-- organização revelava (23505) que ela existe. É definido por quem cria a organização.
grant update (name, photo_retention_days) on public.organizations to authenticated;

-- Lojas: admin cria e altera (sem apagar; desativa com is_active)
revoke insert, update, delete on public.stores from authenticated;
grant insert (organization_id, name, address, timezone, is_active) on public.stores to authenticated;
grant update (name, address, timezone, is_active) on public.stores to authenticated;

-- Configurações da loja: criadas por gatilho; proprietária/admin só alteram
revoke insert, update, delete on public.store_settings from authenticated;
grant update (
  due_soon_minutes, awaiting_approval_hours, escalate_owner_hours, daily_summary_at, channels
) on public.store_settings to authenticated;

-- Setores (a loja do setor não muda)
revoke insert, update on public.sectors from authenticated;
grant insert (store_id, name, responsible_id, sort_order, is_active) on public.sectors to authenticated;
grant update (name, responsible_id, sort_order, is_active) on public.sectors to authenticated;

-- Vínculos: sem DELETE (encerra com ends_at). No UPDATE só setor e período:
-- pessoa, organização, loja e papel não mudam (troca = encerrar e abrir outro).
revoke insert, update, delete on public.memberships from authenticated;
grant insert (profile_id, organization_id, store_id, sector_id, role, starts_at, ends_at)
  on public.memberships to authenticated;
grant update (sector_id, starts_at, ends_at) on public.memberships to authenticated;

-- Rotinas: version, created_at e created_by são do sistema (versão do snapshot
-- não é adulterável); a organização e a loja da rotina não mudam
revoke insert, update on public.task_templates from authenticated;
grant insert (
  organization_id, store_id, title, instructions, reference_image_path, default_priority,
  requires_photo, requires_note, requires_approval, weight, is_active
) on public.task_templates to authenticated;
grant update (
  title, instructions, reference_image_path, default_priority, requires_photo, requires_note,
  requires_approval, weight, is_active
) on public.task_templates to authenticated;

-- Itens da rotina (o item não troca de rotina)
revoke insert, update on public.template_items from authenticated;
grant insert (template_id, position, text, is_critical, requires_photo, weight, is_active)
  on public.template_items to authenticated;
grant update (position, text, is_critical, requires_photo, weight, is_active)
  on public.template_items to authenticated;

-- Agendamentos (a loja do agendamento não muda)
revoke insert, update on public.schedules from authenticated;
grant insert (
  store_id, template_id, sector_id, assignee_id, frequency, rule, window_start, window_end,
  starts_on, ends_on, is_active
) on public.schedules to authenticated;
grant update (
  template_id, sector_id, assignee_id, frequency, rule, window_start, window_end, starts_on, ends_on,
  is_active
) on public.schedules to authenticated;

-- Tarefas: sem DELETE para ninguém da API, nem service_role (cancelar com motivo);
-- status, tentativas, cancelamento e responsável no prazo só mudam pelas RPCs e
-- gatilhos. Gerente/proprietária gravam apenas estas colunas:
revoke insert, update, delete on public.tasks from authenticated;
revoke delete on public.tasks from service_role;
grant insert (
  organization_id, store_id, sector_id, template_id, template_version, title, instructions,
  reference_image_path, priority, requires_photo, requires_note, requires_approval, weight,
  assignee_id, window_start_at, due_at
) on public.tasks to authenticated;
grant update (
  title, instructions, reference_image_path, priority, assignee_id, window_start_at, due_at
) on public.tasks to authenticated;

-- Itens da tarefa (antes da 1ª tentativa): a linhagem não é trocada depois
revoke insert, update on public.task_items from authenticated;
grant insert (task_id, template_item_id, position, text, is_critical, requires_photo, weight)
  on public.task_items to authenticated;
grant update (position, text, is_critical, requires_photo, weight) on public.task_items to authenticated;

-- Planos de ação: sem DELETE (cancelar com status); trigger_count é do sistema
revoke insert, update, delete on public.action_plans from authenticated;
grant insert (store_id, template_item_id, what, owner_id, due_on, status)
  on public.action_plans to authenticated;
grant update (what, owner_id, due_on, status) on public.action_plans to authenticated;

-- Pedidos do titular: sem DELETE; o titular abre, o admin trata. Quem concluiu e
-- quando (resolved_by, resolved_at) são gravados pelo gatilho, não pelo cliente.
revoke insert, update, delete on public.data_requests from authenticated;
grant insert (organization_id, profile_id, kind, details) on public.data_requests to authenticated;
grant update (status, resolution) on public.data_requests to authenticated;
