#!/usr/bin/env bash
# Gera os tipos TypeScript do banco (schema public) com a CLI do Supabase, a partir do banco
# local. Não precisa de Docker: usa `supabase gen types --db-url`.
#
# Uso:
#   pnpm db:types                      # banco 'postgres'
#   DB_NAME=meu_teste pnpm db:types    # outro banco
# Saída: src/lib/supabase/database.types.ts (ou TYPES_OUT=<arquivo>)

source "$(dirname "${BASH_SOURCE[0]}")/../local-stack/lib.sh"

SUPABASE_CLI_VERSION="2.121.0"
DB_NAME="${DB_NAME:-postgres}"
OUT="${TYPES_OUT:-$ROOT_DIR/src/lib/supabase/database.types.ts}"

ensure_dirs
pg_is_ready || die "Postgres local não está rodando. Rode \`pnpm stack:up\`."

tmp="$RUN_DIR/database.types.$$.ts"
trap 'rm -f "$tmp"' EXIT

if ! npx -y "supabase@${SUPABASE_CLI_VERSION}" gen types typescript \
  --db-url "postgresql://${DB_SUPERUSER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}" \
  --schema public >"$tmp" 2>"$LOG_DIR/gen-types.log"; then
  cat "$LOG_DIR/gen-types.log" >&2
  die "falha ao gerar os tipos (veja .local/logs/gen-types.log)"
fi

mkdir -p "$(dirname "$OUT")"
{
  echo "// Gerado por \`pnpm db:types\` (supabase gen types, schema public). Não editar à mão."
  echo
  cat "$tmp"
} >"$OUT"
(cd "$ROOT_DIR" && npx prettier --log-level warn --write "$OUT")
echo "[db:types] banco=$DB_NAME -> ${OUT#"$ROOT_DIR"/}"
