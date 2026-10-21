-- Desfaz 20261021000200_schema_private.sql.
-- Sem CASCADE de propósito: se sobrar algum objeto no schema, o rollback falha
-- e mostra o que ficou para trás.

drop function private.clean_text(text);
drop function private.is_blank(text);
drop function private.is_valid_timezone(text);
drop function private.set_updated_at();
drop schema private;
