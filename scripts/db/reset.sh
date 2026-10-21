#!/usr/bin/env bash
# Recria um banco do zero a partir do template (bootstrap + auth + storage), aplica as
# migrations de supabase/migrations/ em ordem e o supabase/seed.sql.
# Equivalente local de `supabase db reset`.
#
# Uso:
#   pnpm db:reset                      # banco principal 'postgres' (reinicia GoTrue e PostgREST)
#   DB_NAME=meu_teste pnpm db:reset    # banco separado, para experimentos e testes em paralelo
#
# Seguro rodar em paralelo para bancos diferentes (flock) e duas vezes seguidas.

source "$(dirname "${BASH_SOURCE[0]}")/../local-stack/lib.sh"

DB_NAME="${DB_NAME:-postgres}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-$ROOT_DIR/supabase/migrations}"
SEED_FILE="${SEED_FILE:-$ROOT_DIR/supabase/seed.sql}"

[[ "$DB_NAME" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || die "DB_NAME inválido: '$DB_NAME' (use minúsculas, números e _)"
case "$DB_NAME" in
  template0 | template1 | "$TEMPLATE_DB" | contrib_regression) die "DB_NAME reservado: $DB_NAME" ;;
esac

ensure_dirs
pg_is_ready || die "Postgres local não está rodando. Rode \`pnpm stack:up\`."
[ "$("${PSQL[@]}" -d template1 -Atc "select 1 from pg_database where datname = '$TEMPLATE_DB'")" = "1" ] ||
  die "Template $TEMPLATE_DB ausente. Rode \`pnpm stack:up\`."

START_NS=$(date +%s%N)

# Lock por banco: dois resets do mesmo banco nunca se sobrepõem
exec 8>"$LOCK_DIR/db-reset-$DB_NAME.lock"
flock 8

restore_services() {
  # Mesmo se uma migration falhar, GoTrue e PostgREST voltam a rodar no banco principal
  local code=$?
  trap - EXIT
  if [ "$code" != "0" ]; then
    log "reset falhou; religando auth e rest"
    (unset PGOPTIONS; rest_healthy || start_rest; auth_healthy || start_auth) || true
  fi
  exit "$code"
}

if [ "$DB_NAME" = "postgres" ]; then
  # GoTrue e PostgREST mantêm conexões no banco principal; param e voltam no fim
  trap restore_services EXIT
  stop_service auth
  stop_service rest
fi

# Lock global só na troca do banco (drop + clone do template)
(
  flock 9
  "${PSQL[@]}" -d template1 -c "drop database if exists \"$DB_NAME\" with (force)" >/dev/null
  "${PSQL[@]}" -d template1 -c "create database \"$DB_NAME\" template $TEMPLATE_DB" >/dev/null
) 9>"$LOCAL_DIR/db-reset.lock"

export PGOPTIONS="-c client_min_messages=warning"

# Histórico de migrations no mesmo formato da CLI do Supabase
"${PSQL[@]}" -d "$DB_NAME" >/dev/null <<'SQL'
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (
  version text not null primary key,
  statements text[],
  name text
);
SQL

applied=0
shopt -s nullglob
files=("$MIGRATIONS_DIR"/*.sql)
shopt -u nullglob
if [ "${#files[@]}" -gt 0 ]; then
  mapfile -t files < <(printf '%s\n' "${files[@]}" | LC_ALL=C sort)
fi
for f in "${files[@]}"; do
  base="$(basename "$f")"
  if [[ ! "$base" =~ ^([0-9]+)_(.*)\.sql$ ]]; then
    log "aviso: ignorando $base (nome deve ser <timestamp>_<descricao>.sql)"
    continue
  fi
  version="${BASH_REMATCH[1]}"
  name="${BASH_REMATCH[2]}"
  # Migration + registro no histórico na mesma transação (o -f - lê o insert do stdin,
  # onde as variáveis do psql são interpoladas com escape seguro)
  if ! "${PSQL[@]}" -d "$DB_NAME" --single-transaction \
    -v "mig_version=$version" -v "mig_name=$name" \
    -f "$f" -f - >/dev/null <<'SQL'; then
insert into supabase_migrations.schema_migrations (version, name) values (:'mig_version', :'mig_name');
SQL
    die "migration falhou: ${f#"$ROOT_DIR"/} (banco $DB_NAME)"
  fi
  applied=$((applied + 1))
done

seeded="não"
if [ -f "$SEED_FILE" ]; then
  "${PSQL[@]}" -d "$DB_NAME" --single-transaction -f "$SEED_FILE" >/dev/null ||
    die "seed falhou: ${SEED_FILE#"$ROOT_DIR"/} (banco $DB_NAME)"
  seeded="sim"
fi

if [ "$DB_NAME" = "postgres" ]; then
  unset PGOPTIONS
  start_rest
  start_auth
  "${PSQL[@]}" -d postgres -c "notify pgrst, 'reload schema'" >/dev/null
fi

ELAPSED_MS=$((($(date +%s%N) - START_NS) / 1000000))
printf '[db:reset] banco=%s migrations=%d seed=%s tempo=%d.%03ds\n' \
  "$DB_NAME" "$applied" "$seeded" "$((ELAPSED_MS / 1000))" "$((ELAPSED_MS % 1000))"
