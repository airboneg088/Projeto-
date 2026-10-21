-- =============================================================================
-- Extensões usadas pelo modelo de dados.
-- - btree_gist: permite a constraint EXCLUDE que impede vínculos sobrepostos
--   (mesma pessoa, mesma loja, mesmo papel, períodos que se cruzam).
-- - pgcrypto (gen_random_uuid, crypt) já vem instalada no schema extensions
--   no Supabase; aqui só garantimos que existe.
-- Compatível com Postgres 16 (stack local) e 17 (hospedado).
-- =============================================================================

create extension if not exists btree_gist with schema extensions;
create extension if not exists pgcrypto with schema extensions;
