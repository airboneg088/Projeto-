#!/usr/bin/env bash
# Sobe a stack local ("mini Supabase") sem Docker. Idempotente: só inicia o que não está
# rodando e espera cada serviço ficar saudável.
#
#   Postgres 16  127.0.0.1:54322   (cluster em .local/pg)
#   PostgREST    127.0.0.1:54330   (admin/health em :54332)
#   GoTrue       127.0.0.1:54331
#   Gateway      127.0.0.1:54321   (/auth/v1, /rest/v1, /storage/v1 -> 501)
#   SMTP sink    127.0.0.1:54325   (e-mails em .local/mail)
#
# Uso:
#   pnpm stack:up                       # sobe o que estiver parado
#   pnpm stack:up --restart auth        # reinicia serviços (auth, rest, gateway, smtp; vírgulas)
#                                       # ex.: depois de mudar [auth] no supabase/config.toml

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

RESTART=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --restart) RESTART="${2:-}" && shift 2 ;;
    --restart=*) RESTART="${1#--restart=}" && shift ;;
    *) die "opção desconhecida: $1 (use --restart auth,rest,gateway,smtp)" ;;
  esac
done

command -v node >/dev/null || die "Node.js não encontrado"
[ -x "$PG_BIN/postgres" ] || die "Postgres 16 não encontrado em $PG_BIN (defina PG_BIN)"

ensure_dirs
exec 7>"$LOCK_DIR/stack.lock"
flock 7

STARTED_AT=$(date +%s)

# -----------------------------------------------------------------------------
# 1. Binários (PostgREST e GoTrue) com checksum fixo
# -----------------------------------------------------------------------------
download() {
  # download <url> <sha256> <destino>
  local url="$1" sum="$2" dest="$3"
  log "baixando $(basename "$url")..."
  curl -fsSL --retry 3 -o "$dest" "$url" || die "falha ao baixar $url"
  echo "$sum  $dest" | sha256sum -c --status || die "checksum inválido para $(basename "$url")"
}

if [ "$(cat "$BIN_DIR/postgrest.version" 2>/dev/null || true)" != "$POSTGREST_VERSION" ] || [ ! -x "$BIN_DIR/postgrest" ]; then
  tmp="$RUN_DIR/dl-postgrest"
  rm -rf "$tmp" && mkdir -p "$tmp"
  download "$POSTGREST_URL" "$POSTGREST_SHA256" "$tmp/postgrest.tar.xz"
  tar -xJf "$tmp/postgrest.tar.xz" -C "$tmp"
  install -m 0755 "$tmp/postgrest" "$BIN_DIR/postgrest"
  echo "$POSTGREST_VERSION" >"$BIN_DIR/postgrest.version"
  rm -rf "$tmp"
fi

if [ "$(cat "$BIN_DIR/auth.version" 2>/dev/null || true)" != "$AUTH_VERSION" ] || [ ! -x "$BIN_DIR/auth/auth" ]; then
  tmp="$RUN_DIR/dl-auth"
  rm -rf "$tmp" && mkdir -p "$tmp/x"
  download "$AUTH_URL" "$AUTH_SHA256" "$tmp/auth.tar.gz"
  tar -xzf "$tmp/auth.tar.gz" -C "$tmp/x"
  [ -x "$tmp/x/auth" ] && [ -d "$tmp/x/migrations" ] || die "layout inesperado no tarball do GoTrue"
  rm -rf "$BIN_DIR/auth"
  mkdir -p "$BIN_DIR/auth"
  install -m 0755 "$tmp/x/auth" "$BIN_DIR/auth/auth"
  cp -r "$tmp/x/migrations" "$BIN_DIR/auth/migrations"
  echo "$AUTH_VERSION" >"$BIN_DIR/auth.version"
  rm -rf "$tmp"
fi

# -----------------------------------------------------------------------------
# 2. Postgres
# -----------------------------------------------------------------------------
FRESH_CLUSTER=0
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  log "criando cluster Postgres em .local/pg..."
  mkdir -p "$PGDATA"
  pwfile="$RUN_DIR/pg-pwfile"
  printf '%s\n' "$DB_PASSWORD" >"$pwfile"
  if [ "$(id -u)" = "0" ]; then
    chown postgres:postgres "$PGDATA" "$pwfile"
  fi
  chmod 700 "$PGDATA"
  as_pg "$PG_BIN/initdb" -D "$PGDATA" -U "$DB_SUPERUSER" --encoding=UTF8 --locale=C.UTF-8 \
    --auth-local=trust --auth-host=scram-sha-256 --pwfile="$pwfile" >"$LOG_DIR/initdb.log" 2>&1 ||
    {
      rm -f "$pwfile"
      cat "$LOG_DIR/initdb.log" >&2
      die "initdb falhou"
    }
  rm -f "$pwfile"
  as_pg tee "$PGDATA/ede-local.conf" >/dev/null <<CONF
# Configuração da stack local (gerada por scripts/local-stack/up.sh)
listen_addresses = '127.0.0.1'
port = $DB_PORT
unix_socket_directories = ''
max_connections = 200
timezone = 'UTC'
log_timezone = 'UTC'
search_path = '"\$user", public, extensions'
shared_preload_libraries = 'pg_cron'
cron.database_name = 'postgres'
cron.use_background_workers = on
max_worker_processes = 24
synchronous_commit = off
log_min_messages = warning
log_line_prefix = '%m [%p] %q%u@%d '
CONF
  echo "include 'ede-local.conf'" | as_pg tee -a "$PGDATA/postgresql.conf" >/dev/null
  FRESH_CLUSTER=1
fi

if ! pg_is_ready; then
  touch "$LOG_DIR/postgres.log"
  [ "$(id -u)" = "0" ] && chown postgres:postgres "$LOG_DIR/postgres.log"
  log "iniciando Postgres..."
  # 7>&- etc.: o postmaster não pode herdar os descritores dos locks da stack
  as_pg "$PG_BIN/pg_ctl" -D "$PGDATA" -l "$LOG_DIR/postgres.log" -w -t 60 start >/dev/null 7>&- 8>&- 9>&- ||
    {
      tail -n 30 "$LOG_DIR/postgres.log" >&2
      die "Postgres não subiu (veja .local/logs/postgres.log)"
    }
fi
wait_for "postgres" 30 pg_is_ready || die "Postgres não respondeu em 127.0.0.1:$DB_PORT"
log "postgres ok em 127.0.0.1:$DB_PORT"

# Papéis do bootstrap (globais do cluster). Aplicado ao banco 'postgres' na primeira vez;
# depois o 'postgres' é recriado a partir do template.
if [ "$("${PSQL[@]}" -d template1 -Atc "select count(*) from pg_roles where rolname in ('anon','authenticated','service_role','authenticator','supabase_auth_admin','supabase_storage_admin')")" != "6" ]; then
  log "aplicando bootstrap (papéis do Supabase)..."
  PGOPTIONS="-c client_min_messages=warning" "${PSQL[@]}" -d postgres -f "$STACK_DIR/bootstrap.sql" >/dev/null
fi

# -----------------------------------------------------------------------------
# 3. Template e banco principal
# -----------------------------------------------------------------------------
bash "$STACK_DIR/build-template.sh"

MAIN_READY="$("${PSQL[@]}" -d template1 -Atc "select 1 from pg_database where datname = 'postgres'" || true)"
if [ "$MAIN_READY" = "1" ]; then
  MAIN_READY="$("${PSQL[@]}" -d postgres -Atc "select (to_regclass('auth.schema_migrations') is not null and to_regclass('storage.objects') is not null)::int" || true)"
fi
if [ "$FRESH_CLUSTER" = "1" ] || [ "$MAIN_READY" != "1" ]; then
  log "preparando o banco 'postgres' a partir do template (migrations + seed)..."
  DB_NAME=postgres bash "$ROOT_DIR/scripts/db/reset.sh"
fi

# -----------------------------------------------------------------------------
# 4. Serviços
# -----------------------------------------------------------------------------
if [ -n "$RESTART" ]; then
  IFS=',' read -r -a to_restart <<<"$RESTART"
  for svc in "${to_restart[@]}"; do
    case "$svc" in
      auth | rest | gateway | smtp) stop_service "$svc" ;;
      *) die "serviço desconhecido em --restart: $svc" ;;
    esac
  done
fi

if rest_healthy; then
  log "rest já está rodando"
else
  stop_service rest
  port_in_use "$REST_PORT" && die "porta $REST_PORT ocupada por outro processo"
  start_rest
fi

if auth_healthy; then
  log "auth já está rodando"
else
  stop_service auth
  port_in_use "$AUTH_PORT" && die "porta $AUTH_PORT ocupada por outro processo"
  start_auth
fi

if smtp_ok; then
  log "smtp já está rodando"
else
  stop_service smtp
  port_in_use "$SMTP_PORT" && die "porta $SMTP_PORT ocupada por outro processo"
  spawn_bg smtp "$LOG_DIR/smtp.log" node "$STACK_DIR/smtp-sink.mjs" --port "$SMTP_PORT" --dir "$MAIL_DIR"
  wait_for "smtp" 20 smtp_ok || die "SMTP sink não subiu (veja .local/logs/smtp.log)"
  log "smtp ok em 127.0.0.1:$SMTP_PORT (e-mails em .local/mail)"
fi

if gateway_healthy; then
  log "gateway já está rodando"
else
  stop_service gateway
  port_in_use "$GATEWAY_PORT" && die "porta $GATEWAY_PORT ocupada por outro processo"
  spawn_bg gateway "$LOG_DIR/gateway.log" node "$STACK_DIR/gateway.mjs"
  wait_for "gateway" 20 gateway_healthy || die "gateway não subiu (veja .local/logs/gateway.log)"
  log "gateway ok em $API_URL"
fi

# -----------------------------------------------------------------------------
# 5. .env.local para o Next.js
# -----------------------------------------------------------------------------
node "$STACK_DIR/gen-keys.mjs" --write-env "$ROOT_DIR/.env.local"
log ".env.local atualizado"

log "stack pronta em $(($(date +%s) - STARTED_AT))s"
bash "$STACK_DIR/status.sh"
