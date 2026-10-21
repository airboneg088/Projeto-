-- =============================================================================
-- Schema "private": funções internas (SECURITY DEFINER, gatilhos e auxiliares
-- das policies). Não é exposto pela API (o PostgREST só publica "public").
--
-- Regras para tudo que for criado aqui:
--   - set search_path = '' e nomes totalmente qualificados;
--   - revoke all ... from public, anon logo após criar a função;
--   - grant execute to authenticated somente para as funções usadas em policies.
-- =============================================================================

create schema if not exists private;

comment on schema private is
  'Funções internas do Éde Gestão (auxiliares de RLS, gatilhos e geração de tarefas). Não exposto pela API.';

revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Gatilho genérico de updated_at
-- -----------------------------------------------------------------------------
create function private.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function private.set_updated_at() is
  'Gatilho BEFORE UPDATE: preenche updated_at com o horário da transação.';

revoke all on function private.set_updated_at() from public, anon;

-- -----------------------------------------------------------------------------
-- Validação de fuso horário (usada em CHECK de stores.timezone)
-- -----------------------------------------------------------------------------
create function private.is_valid_timezone(p_timezone text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_timezone is null or btrim(p_timezone) = '' then
    return false;
  end if;
  perform now() at time zone p_timezone;
  return true;
exception
  when invalid_parameter_value then
    return false;
end;
$$;

comment on function private.is_valid_timezone(text) is
  'Verdadeiro se o texto é um fuso IANA reconhecido pelo Postgres (ex.: America/Sao_Paulo).';

revoke all on function private.is_valid_timezone(text) from public, anon;
-- CHECK constraints executam com o papel de quem grava a linha
grant execute on function private.is_valid_timezone(text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Texto em branco (usado em CHECK de motivos e nas RPCs)
-- Lista de PERMISSÃO, não de bloqueio: texto "de verdade" tem ao menos uma letra
-- do alfabeto latino (com acentos) ou um número. Uma lista de espaços e
-- caracteres invisíveis nunca fica completa (U+200E, U+00AD, U+2800, U+3164,
-- U+E0020...), e [[:alnum:]] também não serve: o preenchimento hangul U+3164
-- conta como letra. Basta para o português do Brasil.
-- -----------------------------------------------------------------------------
create function private.is_blank(p_text text)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select p_text is null
      or p_text !~ '[0-9A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u024F]'
$$;

comment on function private.is_blank(text) is
  'Verdadeiro se o texto é nulo ou não tem nenhuma letra (alfabeto latino, com acentos) nem número: só espaços, pontuação, quebras de linha ou caracteres invisíveis do Unicode não valem.';

revoke all on function private.is_blank(text) from public, anon;
-- CHECK constraints executam com o papel de quem grava a linha
grant execute on function private.is_blank(text) to authenticated, service_role;

-- Espaços e caracteres invisíveis tirados das pontas: \s, U+0085, U+00A0, hífen suave,
-- marcas de direção, espaços e separadores Unicode, caracteres de largura zero,
-- seletores de variação, braile em branco, preenchimentos hangul, BOM e tags.
create function private.clean_text(p_text text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when private.is_blank(p_text) then null
    else regexp_replace(
      p_text,
      '^[\s\u0085\u00A0\u00AD\u034F\u061C\u115F\u1160\u1680\u17B4\u17B5\u180B-\u180F\u2000-\u200F\u2028-\u202F\u205F-\u206F\u2800\u3000\u3164\uFE00-\uFE0F\uFEFF\uFFA0\uFFF0-\uFFF8\U0001D173-\U0001D17A\U000E0000-\U000E0FFF]+'
      '|[\s\u0085\u00A0\u00AD\u034F\u061C\u115F\u1160\u1680\u17B4\u17B5\u180B-\u180F\u2000-\u200F\u2028-\u202F\u205F-\u206F\u2800\u3000\u3164\uFE00-\uFE0F\uFEFF\uFFA0\uFFF0-\uFFF8\U0001D173-\U0001D17A\U000E0000-\U000E0FFF]+$',
      '',
      'g'
    )
  end
$$;

comment on function private.clean_text(text) is
  'Tira das pontas espaços e caracteres invisíveis do Unicode; devolve nulo se o texto estiver em branco (sem letra nem número).';

revoke all on function private.clean_text(text) from public, anon;
