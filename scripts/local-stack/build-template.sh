#!/usr/bin/env bash
# Cria (ou recria) o banco-template "ede_template", do qual o `pnpm db:reset` clona os bancos.
# Conteúdo: bootstrap (papéis, schemas, grants do hospedado) + schema auth criado pelas
# migrations do próprio GoTrue + ajustes do auth + shim do storage + pg_cron.
#
# Uso: bash scripts/local-stack/build-template.sh [--force]
# Sem --force, só reconstrói quando o template não existe ou quando os arquivos mudaram.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

ensure_dirs
pg_is_ready || die "Postgres local não está rodando. Rode \`pnpm stack:up\`."
[ -x "$BIN_DIR/auth/auth" ] || die "Binário do GoTrue ausente. Rode \`pnpm stack:up\`."

template_hash() {
  {
    printf 'rev=3 auth=%s\n' "$AUTH_VERSION"
    cat "$STACK_DIR/bootstrap.sql" "$STACK_DIR/post-auth.sql" "$STACK_DIR/storage-shim.sql" "$STACK_DIR/build-template.sh"
  } | sha256sum | cut -c1-16
}

WANT="ede-template:$(template_hash)"
HAVE="$("${PSQL[@]}" -d template1 -Atc "select shobj_description(oid, 'pg_database') from pg_database where datname = '$TEMPLATE_DB'" || true)"

if [ "$FORCE" = "0" ] && [ "$HAVE" = "$WANT" ]; then
  log "template $TEMPLATE_DB atualizado ($WANT)"
  exit 0
fi

# Mesmo lock global do db:reset: ninguém clona o template enquanto ele é refeito.
exec 9>"$LOCAL_DIR/db-reset.lock"
flock 9

log "construindo template $TEMPLATE_DB ($WANT)..."
START=$(date +%s)

# O nome temporário "contrib_regression" é o único (além de cron.database_name) em que o
# pg_cron aceita CREATE EXTENSION. Assim todo banco clonado já nasce com o pg_cron instalado.
BUILD_DB=contrib_regression

"${PSQL[@]}" -d template1 <<SQL
drop database if exists $BUILD_DB with (force);
SQL

"${PSQL[@]}" -d template1 -c "create database $BUILD_DB template template0 encoding 'UTF8'"

PGOPTIONS="-c client_min_messages=warning" "${PSQL[@]}" -d "$BUILD_DB" -f "$STACK_DIR/bootstrap.sql"

# Migrations do próprio GoTrue criam o schema auth (como no hospedado)
envf="$RUN_DIR/auth-$BUILD_DB.env"
node "$STACK_DIR/auth-env.mjs" --db "$BUILD_DB" >"$envf"
(
  set -a
  # shellcheck disable=SC1090
  source "$envf"
  set +a
  cd "$BIN_DIR/auth"
  ./auth migrate >>"$LOG_DIR/auth-migrate.log" 2>&1
) || {
  tail -n 30 "$LOG_DIR/auth-migrate.log" >&2
  die "falha nas migrations do GoTrue (veja .local/logs/auth-migrate.log)"
}
rm -f "$envf"

PGOPTIONS="-c client_min_messages=warning" "${PSQL[@]}" -d "$BUILD_DB" -f "$STACK_DIR/post-auth.sql"
PGOPTIONS="-c client_min_messages=warning" "${PSQL[@]}" -d "$BUILD_DB" -f "$STACK_DIR/storage-shim.sql"
"${PSQL[@]}" -d "$BUILD_DB" -c "create extension if not exists pg_cron"

"${PSQL[@]}" -d template1 <<SQL
do \$\$
begin
  if exists (select 1 from pg_database where datname = '$TEMPLATE_DB') then
    execute 'alter database $TEMPLATE_DB is_template false allow_connections true';
  end if;
end
\$\$;
drop database if exists $TEMPLATE_DB with (force);
alter database $BUILD_DB rename to $TEMPLATE_DB;
alter database $TEMPLATE_DB is_template true allow_connections false;
comment on database $TEMPLATE_DB is '$WANT';
SQL

log "template $TEMPLATE_DB pronto em $(($(date +%s) - START))s"
