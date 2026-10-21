-- Desfaz 20261021000100_extensoes.sql.
-- pgcrypto não é removida: ela faz parte da instalação padrão do Supabase
-- (o GoTrue e o seed dependem dela) e já existia antes desta migration.

drop extension if exists btree_gist;
