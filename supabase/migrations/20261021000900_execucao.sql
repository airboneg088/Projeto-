-- =============================================================================
-- Execução: tentativas, respostas do checklist e evidências (fotos).
-- Escrita só pelas funções RPC (start_attempt, answer_item, register_evidence,
-- submit_attempt). Tentativa enviada e evidências são imutáveis (gatilhos).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- task_attempts
-- -----------------------------------------------------------------------------
create table public.task_attempts (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks (id) on delete restrict,
  store_id uuid not null references public.stores (id) on delete restrict,
  attempt_number smallint not null,
  performed_by uuid not null references public.profiles (id) on delete restrict,
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  note text,
  client_mutation_id uuid,
  submit_client_mutation_id uuid,
  constraint task_attempts_attempt_number_positive check (attempt_number >= 1),
  constraint task_attempts_submitted_after_start check (submitted_at is null or submitted_at >= started_at),
  constraint task_attempts_note_length check (note is null or char_length(note) <= 2000),
  constraint task_attempts_task_attempt_number_key unique (task_id, attempt_number),
  constraint task_attempts_client_mutation_id_key unique (client_mutation_id),
  constraint task_attempts_submit_client_mutation_id_key unique (submit_client_mutation_id),
  constraint task_attempts_task_store_fkey foreign key (task_id, store_id)
    references public.tasks (id, store_id) on delete restrict,
  -- Alvo de FKs compostas (evidência e revisão da mesma tarefa)
  constraint task_attempts_id_task_key unique (id, task_id)
);

alter table public.task_attempts enable row level security;

comment on table public.task_attempts is
  'Cada execução de uma tarefa. Nova tentativa após reprovação; todas ficam no histórico. Imutável depois de enviada.';
comment on column public.task_attempts.store_id is 'Loja da tarefa (cópia para as policies de RLS).';
comment on column public.task_attempts.attempt_number is 'Número da tentativa na tarefa (1, 2, 3...).';
comment on column public.task_attempts.performed_by is 'Quem executou (quem iniciou a tentativa).';
comment on column public.task_attempts.started_at is 'Início, pelo horário do servidor.';
comment on column public.task_attempts.submitted_at is 'Envio, pelo horário do servidor. Nulo = tentativa aberta.';
comment on column public.task_attempts.note is 'Observação do colaborador no envio.';
comment on column public.task_attempts.client_mutation_id is
  'Id gerado no aparelho para iniciar a tentativa; reenvio offline com o mesmo id devolve a mesma tentativa.';
comment on column public.task_attempts.submit_client_mutation_id is
  'Id gerado no aparelho para o envio; reenvio offline não duplica.';

-- -----------------------------------------------------------------------------
-- attempt_item_answers
-- -----------------------------------------------------------------------------
create table public.attempt_item_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.task_attempts (id) on delete restrict,
  task_id uuid not null references public.tasks (id) on delete restrict,
  task_item_id uuid not null references public.task_items (id) on delete restrict,
  checked boolean not null default false,
  note text,
  answered_at timestamptz not null default now(),
  constraint attempt_item_answers_attempt_item_key unique (attempt_id, task_item_id),
  constraint attempt_item_answers_note_length check (note is null or char_length(note) <= 1000),
  -- Tentativa e item da MESMA tarefa (nunca item de outra tarefa ou organização)
  constraint attempt_item_answers_attempt_task_fkey foreign key (attempt_id, task_id)
    references public.task_attempts (id, task_id) on delete restrict,
  constraint attempt_item_answers_item_task_fkey foreign key (task_item_id, task_id)
    references public.task_items (id, task_id) on delete restrict
);

alter table public.attempt_item_answers enable row level security;

comment on table public.attempt_item_answers is
  'Resposta de um item do checklist numa tentativa (uma por item). Congelada quando a tentativa é enviada.';
comment on column public.attempt_item_answers.task_id is
  'Tarefa da tentativa (cópia para as FKs compostas: o item respondido é da mesma tarefa da tentativa).';
comment on column public.attempt_item_answers.checked is
  'Verdadeiro = item feito (conforme). Falso com observação = item não conforme (respondido); falso sem observação = ainda não respondido.';
comment on column public.attempt_item_answers.note is
  'Observação do item. Obrigatória para responder "não conforme" (checked falso).';
comment on column public.attempt_item_answers.answered_at is 'Última resposta, pelo horário do servidor.';

-- -----------------------------------------------------------------------------
-- evidences
-- -----------------------------------------------------------------------------
create table public.evidences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  store_id uuid not null references public.stores (id) on delete restrict,
  task_id uuid not null references public.tasks (id) on delete restrict,
  attempt_id uuid not null references public.task_attempts (id) on delete restrict,
  task_item_id uuid references public.task_items (id) on delete restrict,
  storage_path text not null,
  captured_at_device timestamptz,
  received_at_server timestamptz not null default now(),
  latitude numeric(9, 6),
  longitude numeric(9, 6),
  accuracy_m numeric(10, 2),
  sha256 text not null,
  phash bigint,
  size_bytes integer,
  suspicion text[] not null default '{}',
  similar_to_id uuid references public.evidences (id) on delete restrict,
  purged_at timestamptz,
  client_mutation_id uuid,
  constraint evidences_storage_path_key unique (storage_path),
  -- Foto repetida é bloqueada na organização inteira (vale mesmo depois de purged_at)
  constraint evidences_organization_sha256_key unique (organization_id, sha256),
  constraint evidences_client_mutation_id_key unique (client_mutation_id),
  constraint evidences_sha256_format check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint evidences_size_positive check (size_bytes is null or size_bytes > 0),
  constraint evidences_latitude_range check (latitude is null or latitude between -90 and 90),
  constraint evidences_longitude_range check (longitude is null or longitude between -180 and 180),
  constraint evidences_accuracy_non_negative check (accuracy_m is null or accuracy_m >= 0),
  constraint evidences_suspicion_values check (suspicion <@ array['no_exif', 'clock_skew', 'similar']::text[]),
  constraint evidences_similar_consistent check ((similar_to_id is not null) = ('similar' = any (suspicion))),
  constraint evidences_similar_not_self check (similar_to_id is null or similar_to_id <> id),
  constraint evidences_attempt_task_fkey foreign key (attempt_id, task_id)
    references public.task_attempts (id, task_id) on delete restrict,
  constraint evidences_item_task_fkey foreign key (task_item_id, task_id)
    references public.task_items (id, task_id) on delete restrict,
  constraint evidences_task_store_fkey foreign key (task_id, store_id)
    references public.tasks (id, store_id) on delete restrict,
  constraint evidences_store_organization_fkey foreign key (store_id, organization_id)
    references public.stores (id, organization_id) on delete restrict
);

alter table public.evidences enable row level security;

comment on table public.evidences is
  'Foto de evidência de uma tentativa. Nunca apagada nem sobrescrita; o job de retenção só remove o arquivo e preenche purged_at.';
comment on column public.evidences.organization_id is 'Organização (escopo da regra de foto repetida por sha256).';
comment on column public.evidences.store_id is 'Loja da tarefa (cópia para as policies de RLS).';
comment on column public.evidences.task_id is 'Tarefa da tentativa (cópia para consultas e FKs).';
comment on column public.evidences.task_item_id is 'Item fotografado. Nulo = foto geral da tarefa.';
comment on column public.evidences.storage_path is
  'Caminho no bucket evidences: {organization_id}/{store_id}/{task_id}/{attempt_id}/{uuid}.jpg.';
comment on column public.evidences.captured_at_device is 'Horário informado pelo aparelho (pode estar errado).';
comment on column public.evidences.received_at_server is 'Horário do servidor ao registrar a foto. É a verdade.';
comment on column public.evidences.latitude is 'Latitude (GPS), quando a pessoa permitiu.';
comment on column public.evidences.longitude is 'Longitude (GPS), quando a pessoa permitiu.';
comment on column public.evidences.accuracy_m is 'Precisão do GPS em metros.';
comment on column public.evidences.sha256 is 'Hash SHA-256 (hex minúsculo) do arquivo. Igual a outro da organização = foto repetida, bloqueada.';
comment on column public.evidences.phash is 'Hash perceptual de 64 bits. Distância de Hamming <= 10 de outra foto recente = suspeita "similar".';
comment on column public.evidences.size_bytes is 'Tamanho do arquivo em bytes.';
comment on column public.evidences.suspicion is
  'Sinais para o gerente avaliar (não bloqueiam): no_exif (sem EXIF ou sem horário de captura), clock_skew (horário do aparelho difere > 10 min do servidor), similar (parecida com outra foto). Foto com EXIF cujo horário de captura é anterior ao início da tentativa (com 10 min de tolerância) é recusada (photo_before_start).';
comment on column public.evidences.similar_to_id is 'Foto parecida mais próxima, quando há suspeita "similar".';
comment on column public.evidences.purged_at is 'Quando o arquivo foi removido do storage pela retenção. O registro fica.';
comment on column public.evidences.client_mutation_id is 'Id gerado no aparelho; reenvio offline com o mesmo id devolve a mesma evidência.';
