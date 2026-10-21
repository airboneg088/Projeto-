-- =============================================================================
-- SEED — SOMENTE PARA DESENVOLVIMENTO LOCAL. NUNCA RODE EM PRODUÇÃO.
--
-- Todas as pessoas, e-mails e endereços são EXEMPLOS (marcados [EXEMPLO]).
-- A senha de todos os usuários é Exemplo#2026 (apenas para uso local).
-- Setores e rotinas são provisórios: serão trocados pelos reais da Éde
-- Utilidades quando a cliente confirmar.
--
-- UUIDs fixos e legíveis (o 1º bloco indica o tipo):
--   a0... organização   b0... lojas        c0... setores      d0... pessoas
--   e0... vínculos      f0... rotinas      f1... itens        f2... agendamentos
-- Lojas: ...01 Primavera, ...02 Castro Alves, ...03 Parque América.
-- Tarefas do dia (data local de America/Sao_Paulo) são geradas no fim por
-- private.instantiate_task, então seus ids variam a cada reset.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Organização, lojas e setores
-- -----------------------------------------------------------------------------
insert into public.organizations (id, name, slug, photo_retention_days)
values ('a0000000-0000-0000-0000-000000000001', 'Éde Utilidades', 'ede', 180);

-- store_settings é criada automaticamente (gatilho) com os valores padrão
insert into public.stores (id, organization_id, name, address, timezone)
values
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
   'Primavera', '[EXEMPLO] endereço a confirmar', 'America/Sao_Paulo'),
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001',
   'Castro Alves', '[EXEMPLO] endereço a confirmar', 'America/Sao_Paulo'),
  ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001',
   'Parque América', '[EXEMPLO] endereço a confirmar', 'America/Sao_Paulo');

-- Setores PROVISÓRIOS (até a cliente confirmar os setores reais de cada loja)
insert into public.sectors (id, store_id, name, sort_order)
values
  ('c0000000-0000-0000-0000-000000000011', 'b0000000-0000-0000-0000-000000000001', 'Salão de vendas', 1),
  ('c0000000-0000-0000-0000-000000000012', 'b0000000-0000-0000-0000-000000000001', 'Estoque', 2),
  ('c0000000-0000-0000-0000-000000000013', 'b0000000-0000-0000-0000-000000000001', 'Caixa', 3),
  ('c0000000-0000-0000-0000-000000000014', 'b0000000-0000-0000-0000-000000000001', 'Limpeza', 4),
  ('c0000000-0000-0000-0000-000000000021', 'b0000000-0000-0000-0000-000000000002', 'Salão de vendas', 1),
  ('c0000000-0000-0000-0000-000000000022', 'b0000000-0000-0000-0000-000000000002', 'Estoque', 2),
  ('c0000000-0000-0000-0000-000000000023', 'b0000000-0000-0000-0000-000000000002', 'Caixa', 3),
  ('c0000000-0000-0000-0000-000000000024', 'b0000000-0000-0000-0000-000000000002', 'Limpeza', 4),
  ('c0000000-0000-0000-0000-000000000031', 'b0000000-0000-0000-0000-000000000003', 'Salão de vendas', 1),
  ('c0000000-0000-0000-0000-000000000032', 'b0000000-0000-0000-0000-000000000003', 'Estoque', 2),
  ('c0000000-0000-0000-0000-000000000033', 'b0000000-0000-0000-0000-000000000003', 'Caixa', 3),
  ('c0000000-0000-0000-0000-000000000034', 'b0000000-0000-0000-0000-000000000003', 'Limpeza', 4);

-- -----------------------------------------------------------------------------
-- Usuários do Auth (o perfil em public.profiles nasce pelo gatilho)
-- Os campos de token precisam ser '' (string vazia): NULL quebra o GoTrue.
-- -----------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token,
  is_sso_user, is_anonymous
)
select
  '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
  extensions.crypt('Exemplo#2026', extensions.gen_salt('bf')), now(),
  -- organization_id: a conta é desta organização (D21; só ela pode vincular a pessoa)
  '{"provider": "email", "providers": ["email"], "organization_id": "a0000000-0000-0000-0000-000000000001"}'::jsonb,
  jsonb_build_object('full_name', u.full_name),
  now(), now(),
  '', '', '', '', '', '', '', '',
  false, false
from (
  values
    ('d0000000-0000-0000-0000-000000000001'::uuid, 'proprietaria@exemplo.local', '[EXEMPLO] Proprietária da rede'),
    ('d0000000-0000-0000-0000-000000000002'::uuid, 'admin@exemplo.local', '[EXEMPLO] Admin do suporte'),
    ('d0000000-0000-0000-0000-000000000010'::uuid, 'gerente.primavera@exemplo.local', '[EXEMPLO] Gerente Primavera'),
    ('d0000000-0000-0000-0000-000000000011'::uuid, 'colaborador1.primavera@exemplo.local', '[EXEMPLO] Colaborador 1 Primavera'),
    ('d0000000-0000-0000-0000-000000000012'::uuid, 'colaborador2.primavera@exemplo.local', '[EXEMPLO] Colaborador 2 Primavera'),
    ('d0000000-0000-0000-0000-000000000013'::uuid, 'colaborador3.primavera@exemplo.local', '[EXEMPLO] Colaborador 3 Primavera'),
    ('d0000000-0000-0000-0000-000000000020'::uuid, 'gerente.castroalves@exemplo.local', '[EXEMPLO] Gerente Castro Alves'),
    ('d0000000-0000-0000-0000-000000000021'::uuid, 'colaborador1.castroalves@exemplo.local', '[EXEMPLO] Colaborador 1 Castro Alves'),
    ('d0000000-0000-0000-0000-000000000022'::uuid, 'colaborador2.castroalves@exemplo.local', '[EXEMPLO] Colaborador 2 Castro Alves'),
    ('d0000000-0000-0000-0000-000000000023'::uuid, 'colaborador3.castroalves@exemplo.local', '[EXEMPLO] Colaborador 3 Castro Alves'),
    ('d0000000-0000-0000-0000-000000000030'::uuid, 'gerente.parqueamerica@exemplo.local', '[EXEMPLO] Gerente Parque América'),
    ('d0000000-0000-0000-0000-000000000031'::uuid, 'colaborador1.parqueamerica@exemplo.local', '[EXEMPLO] Colaborador 1 Parque América'),
    ('d0000000-0000-0000-0000-000000000032'::uuid, 'colaborador2.parqueamerica@exemplo.local', '[EXEMPLO] Colaborador 2 Parque América'),
    ('d0000000-0000-0000-0000-000000000033'::uuid, 'colaborador3.parqueamerica@exemplo.local', '[EXEMPLO] Colaborador 3 Parque América')
) as u (id, email, full_name);

-- Identidade "email" de cada usuário (o GoTrue exige para o login com senha)
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select
  u.id, u.id, u.id::text, 'email',
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true, 'phone_verified', false),
  null, now(), now()
from auth.users u
where u.id::text like 'd0000000-0000-0000-0000-0000000000__';

-- -----------------------------------------------------------------------------
-- Vínculos: proprietária e admin na rede; 1 gerente e 3 colaboradores por loja
-- (colaborador 1 = Salão de vendas, 2 = Estoque, 3 = Caixa)
-- -----------------------------------------------------------------------------
insert into public.memberships (id, profile_id, organization_id, store_id, sector_id, role, starts_at)
values
  ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', null, null, 'owner', '2026-01-01 00:00:00-03'),
  ('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', null, null, 'admin', '2026-01-01 00:00:00-03'),
  -- Primavera
  ('e0000000-0000-0000-0000-000000000010', 'd0000000-0000-0000-0000-000000000010', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', null, 'manager', '2026-01-01 00:00:00-03'),
  ('e0000000-0000-0000-0000-000000000011', 'd0000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000011', 'staff', '2026-01-01 00:00:00-03'),
  ('e0000000-0000-0000-0000-000000000012', 'd0000000-0000-0000-0000-000000000012', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000012', 'staff', '2026-01-01 00:00:00-03'),
  ('e0000000-0000-0000-0000-000000000013', 'd0000000-0000-0000-0000-000000000013', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000013', 'staff', '2026-01-01 00:00:00-03'),
  -- Castro Alves
  ('e0000000-0000-0000-0000-000000000020', 'd0000000-0000-0000-0000-000000000020', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', null, 'manager', '2026-01-01 00:00:00-03'),
  ('e0000000-0000-0000-0000-000000000021', 'd0000000-0000-0000-0000-000000000021', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000021', 'staff', '2026-01-01 00:00:00-03'),
  ('e0000000-0000-0000-0000-000000000022', 'd0000000-0000-0000-0000-000000000022', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000022', 'staff', '2026-01-01 00:00:00-03'),
  ('e0000000-0000-0000-0000-000000000023', 'd0000000-0000-0000-0000-000000000023', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000023', 'staff', '2026-01-01 00:00:00-03'),
  -- Parque América
  ('e0000000-0000-0000-0000-000000000030', 'd0000000-0000-0000-0000-000000000030', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', null, 'manager', '2026-01-01 00:00:00-03'),
  ('e0000000-0000-0000-0000-000000000031', 'd0000000-0000-0000-0000-000000000031', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000031', 'staff', '2026-01-01 00:00:00-03'),
  ('e0000000-0000-0000-0000-000000000032', 'd0000000-0000-0000-0000-000000000032', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000032', 'staff', '2026-01-01 00:00:00-03'),
  ('e0000000-0000-0000-0000-000000000033', 'd0000000-0000-0000-0000-000000000033', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000033', 'staff', '2026-01-01 00:00:00-03');

-- -----------------------------------------------------------------------------
-- 8 rotinas-padrão da rede (store_id nulo), adaptadas a utilidades domésticas.
-- PROVISÓRIAS: as rotinas reais da Éde Utilidades vão substituí-las.
-- -----------------------------------------------------------------------------
insert into public.task_templates (
  id, organization_id, store_id, title, instructions, default_priority,
  requires_photo, requires_note, requires_approval, weight
)
values
  ('f0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', null,
   'Abertura da loja',
   'Faça na ordem: alarme, luzes e equipamentos, conferência do salão e abertura das portas. Fotografe os itens indicados.',
   'high', false, false, true, 4),
  ('f0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', null,
   'Salão de vendas',
   'Percorra todos os corredores. Frágeis sempre em altura segura e longe da borda.',
   'normal', false, false, true, 3),
  ('f0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', null,
   'Precificação',
   'Use o leitor para conferir o preço no sistema. Troque na hora a etiqueta que estiver errada.',
   'normal', false, false, true, 3),
  ('f0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', null,
   'Reposição',
   'Reponha a partir do estoque. Pesados embaixo, frágeis com cuidado.',
   'normal', false, false, false, 2),
  ('f0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', null,
   'Estoque',
   'Mantenha o estoque organizado e seguro. Avarias ficam separadas e identificadas.',
   'normal', false, false, true, 3),
  ('f0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', null,
   'Caixa',
   'Confira o fundo de troco antes do primeiro atendimento. Faça a sangria sempre que passar do limite.',
   'high', false, false, true, 5),
  ('f0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001', null,
   'Limpeza',
   'Atenção a cacos de vidro e louça no piso. Envie ao menos uma foto do salão limpo.',
   'normal', true, false, true, 2),
  ('f0000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-000000000001', null,
   'Fechamento da loja',
   'Feche o caixa, desligue os equipamentos, tranque tudo e ative o alarme. Registre na observação qualquer ocorrência do dia.',
   'high', false, true, true, 5);

insert into public.template_items (id, template_id, position, text, is_critical, requires_photo, weight)
values
  -- Abertura da loja
  ('f1000000-0000-0000-0000-000000000011', 'f0000000-0000-0000-0000-000000000001', 1,
   'Desligar o alarme e conferir se não há sinais de arrombamento', true, false, 5),
  ('f1000000-0000-0000-0000-000000000012', 'f0000000-0000-0000-0000-000000000001', 2,
   'Acender as luzes do salão e ligar computadores, PDV e ar-condicionado', false, false, 2),
  ('f1000000-0000-0000-0000-000000000013', 'f0000000-0000-0000-0000-000000000001', 3,
   'Corredores livres, sem caixas ou mercadorias no caminho', true, true, 4),
  ('f1000000-0000-0000-0000-000000000014', 'f0000000-0000-0000-0000-000000000001', 4,
   'Vidros, porcelanas e cerâmicas em altura segura, longe da borda das prateleiras', true, true, 4),
  ('f1000000-0000-0000-0000-000000000015', 'f0000000-0000-0000-0000-000000000001', 5,
   'Portas abertas no horário, com fachada e vitrine limpas', false, true, 2),
  -- Salão de vendas
  ('f1000000-0000-0000-0000-000000000021', 'f0000000-0000-0000-0000-000000000002', 1,
   'Gôndolas alinhadas, abastecidas e com a frente dos produtos virada para o cliente', false, true, 3),
  ('f1000000-0000-0000-0000-000000000022', 'f0000000-0000-0000-0000-000000000002', 2,
   'Produtos frágeis (vidro, porcelana) até 1,50 m de altura e nunca na borda', true, true, 4),
  ('f1000000-0000-0000-0000-000000000023', 'f0000000-0000-0000-0000-000000000002', 3,
   'Corredores e saídas de emergência desobstruídos', true, false, 4),
  ('f1000000-0000-0000-0000-000000000024', 'f0000000-0000-0000-0000-000000000002', 4,
   'Placas de oferta corretas e dentro do prazo da promoção', false, false, 2),
  ('f1000000-0000-0000-0000-000000000025', 'f0000000-0000-0000-0000-000000000002', 5,
   'Carrinhos e cestas limpos e organizados na entrada', false, false, 1),
  ('f1000000-0000-0000-0000-000000000026', 'f0000000-0000-0000-0000-000000000002', 6,
   'Expositores de panelas e utensílios montados, sem peças soltas', false, false, 2),
  -- Precificação
  ('f1000000-0000-0000-0000-000000000031', 'f0000000-0000-0000-0000-000000000003', 1,
   'Conferir 10 produtos por amostragem: preço da etiqueta igual ao do sistema', true, false, 5),
  ('f1000000-0000-0000-0000-000000000032', 'f0000000-0000-0000-0000-000000000003', 2,
   'Toda prateleira com etiqueta de preço visível e legível', false, true, 3),
  ('f1000000-0000-0000-0000-000000000033', 'f0000000-0000-0000-0000-000000000003', 3,
   'Ofertas com preço "de/por" e validade da promoção corretos', false, false, 3),
  ('f1000000-0000-0000-0000-000000000034', 'f0000000-0000-0000-0000-000000000003', 4,
   'Etiquetas rasgadas ou desbotadas trocadas', false, false, 2),
  -- Reposição (sem aprovação: auto-aprovada no envio)
  ('f1000000-0000-0000-0000-000000000041', 'f0000000-0000-0000-0000-000000000004', 1,
   'Itens em falta nas gôndolas repostos a partir do estoque', false, false, 3),
  ('f1000000-0000-0000-0000-000000000042', 'f0000000-0000-0000-0000-000000000004', 2,
   'Produtos mais antigos na frente (primeiro que entra, primeiro que sai)', false, false, 2),
  ('f1000000-0000-0000-0000-000000000043', 'f0000000-0000-0000-0000-000000000004', 3,
   'Itens pesados nas prateleiras de baixo', true, false, 3),
  ('f1000000-0000-0000-0000-000000000044', 'f0000000-0000-0000-0000-000000000004', 4,
   'Caixas vazias e plásticos retirados do salão', false, false, 1),
  -- Estoque
  ('f1000000-0000-0000-0000-000000000051', 'f0000000-0000-0000-0000-000000000005', 1,
   'Corredores do estoque e saída de emergência livres', true, true, 4),
  ('f1000000-0000-0000-0000-000000000052', 'f0000000-0000-0000-0000-000000000005', 2,
   'Itens pesados embaixo; frágeis embalados e identificados', true, false, 4),
  ('f1000000-0000-0000-0000-000000000053', 'f0000000-0000-0000-0000-000000000005', 3,
   'Mercadoria recebida conferida com a nota fiscal', false, false, 3),
  ('f1000000-0000-0000-0000-000000000054', 'f0000000-0000-0000-0000-000000000005', 4,
   'Avarias separadas e registradas para troca com o fornecedor', false, false, 2),
  ('f1000000-0000-0000-0000-000000000055', 'f0000000-0000-0000-0000-000000000005', 5,
   'Contagem de 10 itens de maior giro conferida com o sistema', false, false, 3),
  -- Caixa
  ('f1000000-0000-0000-0000-000000000061', 'f0000000-0000-0000-0000-000000000006', 1,
   'Fundo de troco conferido e assinado antes do primeiro atendimento', true, false, 5),
  ('f1000000-0000-0000-0000-000000000062', 'f0000000-0000-0000-0000-000000000006', 2,
   'Sangria feita sempre que o caixa passar do limite definido', true, false, 5),
  ('f1000000-0000-0000-0000-000000000063', 'f0000000-0000-0000-0000-000000000006', 3,
   'Máquinas de cartão carregadas, com bobina e conectadas', false, false, 2),
  ('f1000000-0000-0000-0000-000000000064', 'f0000000-0000-0000-0000-000000000006', 4,
   'Área do caixa limpa e organizada', false, true, 1),
  ('f1000000-0000-0000-0000-000000000065', 'f0000000-0000-0000-0000-000000000006', 5,
   'Sacolas e papel de presente abastecidos', false, false, 1),
  -- Limpeza (a tarefa exige ao menos uma foto)
  ('f1000000-0000-0000-0000-000000000071', 'f0000000-0000-0000-0000-000000000007', 1,
   'Piso do salão varrido e sem cacos de vidro ou louça', true, true, 4),
  ('f1000000-0000-0000-0000-000000000072', 'f0000000-0000-0000-0000-000000000007', 2,
   'Prateleiras e vitrines sem pó', false, true, 2),
  ('f1000000-0000-0000-0000-000000000073', 'f0000000-0000-0000-0000-000000000007', 3,
   'Banheiro limpo e abastecido (papel e sabonete)', false, false, 2),
  ('f1000000-0000-0000-0000-000000000074', 'f0000000-0000-0000-0000-000000000007', 4,
   'Lixo retirado e recicláveis separados', false, false, 1),
  -- Fechamento da loja (exige observação)
  ('f1000000-0000-0000-0000-000000000081', 'f0000000-0000-0000-0000-000000000008', 1,
   'Caixa fechado e conferido com o sistema; sangria final guardada no cofre', true, false, 5),
  ('f1000000-0000-0000-0000-000000000082', 'f0000000-0000-0000-0000-000000000008', 2,
   'Computadores, PDV e ar-condicionado desligados', false, false, 2),
  ('f1000000-0000-0000-0000-000000000083', 'f0000000-0000-0000-0000-000000000008', 3,
   'Portas e portões trancados e cadeados conferidos', true, true, 5),
  ('f1000000-0000-0000-0000-000000000084', 'f0000000-0000-0000-0000-000000000008', 4,
   'Alarme ativado', true, false, 5),
  ('f1000000-0000-0000-0000-000000000085', 'f0000000-0000-0000-0000-000000000008', 5,
   'Luzes apagadas, exceto a iluminação de segurança', false, true, 1);

-- -----------------------------------------------------------------------------
-- Agendamentos diários por loja (janelas em hora local)
--   rotina           setor             janela         responsável
--   Abertura         Salão de vendas   07:30-08:15    equipe
--   Caixa            Caixa             07:45-08:30    equipe
--   Salão de vendas  Salão de vendas   08:15-10:00    equipe
--   Precificação     Salão de vendas   10:00-12:00    equipe
--   Reposição        Estoque           13:00-15:00    equipe
--   Estoque          Estoque           15:00-17:00    equipe
--   Limpeza          Limpeza           17:00-18:30    colaborador 1 da loja
--   Fechamento       Caixa             21:30-22:00    equipe
-- -----------------------------------------------------------------------------
insert into public.schedules (
  id, store_id, template_id, sector_id, assignee_id, frequency, rule,
  window_start, window_end, starts_on
)
select
  format('f2000000-0000-0000-0000-0000000000%s%s', st.n, r.t)::uuid,
  format('b0000000-0000-0000-0000-00000000000%s', st.n)::uuid,
  format('f0000000-0000-0000-0000-00000000000%s', r.t)::uuid,
  format('c0000000-0000-0000-0000-0000000000%s%s', st.n, r.sector_n)::uuid,
  case when r.staff_n is null then null
       else format('d0000000-0000-0000-0000-0000000000%s%s', st.n, r.staff_n)::uuid end,
  'daily', '{}'::jsonb,
  r.window_start::time, r.window_end::time, date '2026-01-01'
from (values (1), (2), (3)) as st (n)
cross join (
  values
    (1, 1, null::integer, '07:30', '08:15'),
    (2, 1, null, '08:15', '10:00'),
    (3, 1, null, '10:00', '12:00'),
    (4, 2, null, '13:00', '15:00'),
    (5, 2, null, '15:00', '17:00'),
    (6, 3, null, '07:45', '08:30'),
    (7, 4, 1, '17:00', '18:30'),
    (8, 3, null, '21:30', '22:00')
) as r (t, sector_n, staff_n, window_start, window_end);

-- -----------------------------------------------------------------------------
-- Tarefas de hoje (dia local de cada loja), geradas a partir dos agendamentos
-- -----------------------------------------------------------------------------
do $$
declare
  v_schedule record;
  v_today date;
begin
  for v_schedule in
    select sc.id, sc.template_id, sc.store_id, sc.sector_id, sc.assignee_id,
           sc.window_start, sc.window_end, st.timezone
    from public.schedules sc
    join public.stores st on st.id = sc.store_id
    where sc.is_active
    order by sc.id
  loop
    v_today := (now() at time zone v_schedule.timezone)::date;
    perform private.instantiate_task(
      v_schedule.template_id,
      v_schedule.store_id,
      v_schedule.sector_id,
      v_schedule.assignee_id,
      (v_today + v_schedule.window_start) at time zone v_schedule.timezone,
      (v_today + v_schedule.window_end) at time zone v_schedule.timezone,
      v_schedule.id,
      v_today
    );
  end loop;
end;
$$;
