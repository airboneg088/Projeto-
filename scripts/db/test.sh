#!/usr/bin/env bash
# Roda os testes pgTAP (supabase/tests/**/*.sql, exceto helpers/) com pg_prove.
# Equivalente local de `supabase test db`.
#
# Uso:
#   pnpm db:test                                   # banco 'postgres'
#   DB_NAME=meu_teste pnpm db:test                 # outro banco (crie com DB_NAME=... pnpm db:reset)
#   pnpm db:test supabase/tests/rls_lojas.sql      # só os arquivos indicados
#
# Cada arquivo de teste é autocontido: begin; select plan(n); ...; select * from finish(); rollback;
# Helpers ficam em supabase/tests/helpers/*.psql e são incluídos com \ir.

source "$(dirname "${BASH_SOURCE[0]}")/../local-stack/lib.sh"

DB_NAME="${DB_NAME:-postgres}"
TESTS_DIR="$ROOT_DIR/supabase/tests"

pg_is_ready || die "Postgres local não está rodando. Rode \`pnpm stack:up\`."
[ "$("${PSQL[@]}" -d template1 -Atc "select 1 from pg_database where datname = '$DB_NAME'")" = "1" ] ||
  die "Banco '$DB_NAME' não existe. Rode \`DB_NAME=$DB_NAME pnpm db:reset\`."

# pgTAP no schema extensions (como no hospedado); o search_path padrão já inclui extensions
PGOPTIONS="-c client_min_messages=warning" "${PSQL[@]}" -d "$DB_NAME" \
  -c "create extension if not exists pgtap with schema extensions" >/dev/null
# Função nova do postgres nasce sem EXECUTE para PUBLIC (20261021002800); os testes
# chamam o pgTAP com os papéis da API, então as funções dele ficam liberadas
"${PSQL[@]}" -d "$DB_NAME" -q >/dev/null <<'SQL'
do $$
declare
  v_fn regprocedure;
begin
  for v_fn in
    select p.oid::regprocedure
    from pg_proc p
    join pg_depend d on d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e'
    join pg_extension e on e.oid = d.refobjid and d.refclassid = 'pg_extension'::regclass
    where e.extname = 'pgtap'
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  loop
    execute format('grant execute on function %s to public', v_fn);
  end loop;
end;
$$;
SQL

files=()
if [ "$#" -gt 0 ]; then
  for f in "$@"; do
    [ -f "$f" ] || die "arquivo de teste não encontrado: $f"
    files+=("$f")
  done
else
  if [ -d "$TESTS_DIR" ]; then
    mapfile -t files < <(find "$TESTS_DIR" -type f -name '*.sql' -not -path "$TESTS_DIR/helpers/*" | LC_ALL=C sort)
  fi
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "[db:test] nenhum teste encontrado em supabase/tests/"
  exit 0
fi

echo "[db:test] banco=$DB_NAME arquivos=${#files[@]}"
# pg_prove roda cada arquivo com `psql -f`, então \ir resolve caminhos relativos ao arquivo.
PGOPTIONS="-c client_min_messages=warning" exec pg_prove \
  --host "$DB_HOST" --port "$DB_PORT" --username "$DB_SUPERUSER" --dbname "$DB_NAME" \
  --failures --comments \
  "${files[@]}"
