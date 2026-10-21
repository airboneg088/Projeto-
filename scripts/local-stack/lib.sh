# shellcheck shell=bash
# Funções e variáveis comuns da stack local ("mini Supabase").
# Uso: source "$(dirname "$0")/lib.sh" (ou caminho equivalente).

set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$STACK_DIR/../.." && pwd)"
LOCAL_DIR="$ROOT_DIR/.local"
BIN_DIR="$LOCAL_DIR/bin"
LOG_DIR="$LOCAL_DIR/logs"
RUN_DIR="$LOCAL_DIR/run"
MAIL_DIR="$LOCAL_DIR/mail"
LOCK_DIR="$LOCAL_DIR/locks"
PGDATA="$LOCAL_DIR/pg"

PG_BIN="${PG_BIN:-/usr/lib/postgresql/16/bin}"

# Portas (contrato da stack local)
GATEWAY_PORT=54321
DB_PORT=54322
SMTP_PORT=54325
REST_PORT=54330
AUTH_PORT=54331
REST_ADMIN_PORT=54332

DB_HOST=127.0.0.1
DB_SUPERUSER=postgres
DB_PASSWORD=postgres
TEMPLATE_DB=ede_template

JWT_SECRET="super-secret-jwt-token-with-at-least-32-characters-long"

API_URL="http://127.0.0.1:${GATEWAY_PORT}"

# Versões e checksums fixos dos binários
POSTGREST_VERSION="v13.0.7"
POSTGREST_URL="https://github.com/PostgREST/postgrest/releases/download/${POSTGREST_VERSION}/postgrest-${POSTGREST_VERSION}-linux-static-x86-64.tar.xz"
POSTGREST_SHA256="4153f81ccc40e7b735edc89cd84b49da25ba27eb37d57c7f6a82c9005a0b762b"
AUTH_VERSION="v2.180.0"
AUTH_URL="https://github.com/supabase/auth/releases/download/${AUTH_VERSION}/auth-${AUTH_VERSION}-x86.tar.gz"
AUTH_SHA256="3fe064281f5cf7bda94251a3bd9e87a690d081381d9ea93b1491163735209e2e"

export PGHOST="$DB_HOST" PGPORT="$DB_PORT" PGUSER="$DB_SUPERUSER" PGPASSWORD="$DB_PASSWORD"
export PGCONNECT_TIMEOUT=5
# Sem NOTICEs ("já existe, pulando") poluindo a saída dos scripts
export PGOPTIONS="${PGOPTIONS:--c client_min_messages=warning}"

PSQL=("$PG_BIN/psql" -X -q -v ON_ERROR_STOP=1)

log() { printf '[stack] %s\n' "$*" >&2; }
die() {
  printf '[stack] ERRO: %s\n' "$*" >&2
  exit 1
}

ensure_dirs() {
  mkdir -p "$BIN_DIR" "$LOG_DIR" "$RUN_DIR" "$MAIL_DIR" "$LOCK_DIR"
}

# Executa um comando como o usuário do sistema "postgres" quando estamos como root
# (o Postgres se recusa a rodar como root).
as_pg() {
  if [ "$(id -u)" = "0" ]; then
    runuser -u postgres -- "$@"
  else
    "$@"
  fi
}

pg_is_ready() {
  "$PG_BIN/pg_isready" -q -h "$DB_HOST" -p "$DB_PORT" -U "$DB_SUPERUSER" >/dev/null 2>&1
}

http_ok() {
  # http_ok <url> [header...]: verdadeiro se a resposta for 2xx
  local url="$1"
  shift
  local args=(-s -o /dev/null -w '%{http_code}' --max-time 3 --noproxy '*')
  local h
  for h in "$@"; do args+=(-H "$h"); done
  local code
  code="$(curl "${args[@]}" "$url" 2>/dev/null || true)"
  [[ "$code" =~ ^2 ]]
}

smtp_ok() {
  # Lê o banner 220 do SMTP local
  local banner
  banner="$(timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/${SMTP_PORT}; head -c 3 <&3; printf 'QUIT\r\n' >&3" 2>/dev/null || true)"
  [ "$banner" = "220" ]
}

port_in_use() {
  timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" >/dev/null 2>&1
}

pid_of() {
  local f="$RUN_DIR/$1.pid"
  [ -f "$f" ] && cat "$f" || true
}

pid_alive() {
  local pid
  pid="$(pid_of "$1")"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# wait_for <descrição> <segundos> <comando...>
wait_for() {
  local what="$1" secs="$2"
  shift 2
  local i
  for ((i = 0; i < secs * 5; i++)); do
    if "$@"; then return 0; fi
    sleep 0.2
  done
  return 1
}

# spawn_bg <nome> <arquivo-de-log> <comando...>: inicia em segundo plano, desacoplado do
# terminal, sem herdar os descritores dos locks (7, 8, 9), e grava .local/run/<nome>.pid.
spawn_bg() {
  local name="$1" logfile="$2"
  shift 2
  setsid nohup "$@" >>"$logfile" 2>&1 </dev/null 7>&- 8>&- 9>&- &
  echo $! >"$RUN_DIR/$name.pid"
}

stop_service() {
  # stop_service <nome>: encerra o processo registrado em .local/run/<nome>.pid
  local name="$1" pid
  pid="$(pid_of "$name")"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    local i
    for ((i = 0; i < 50; i++)); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null || true; fi
    log "$name parado (pid $pid)"
  fi
  rm -f "$RUN_DIR/$name.pid"
}

# Chaves JWT (anon e service_role) determinísticas, iguais às da CLI do Supabase.
load_keys() {
  local line
  while IFS= read -r line; do
    case "$line" in
      ANON_KEY=*) ANON_KEY="${line#ANON_KEY=}" ;;
      SERVICE_ROLE_KEY=*) SERVICE_ROLE_KEY="${line#SERVICE_ROLE_KEY=}" ;;
    esac
  done < <(node "$STACK_DIR/gen-keys.mjs" --shell)
  export ANON_KEY SERVICE_ROLE_KEY
}

# Ambiente do GoTrue (supabase/auth). Lê supabase/config.toml via auth-env.mjs.
auth_env_file() {
  local db="${1:-postgres}"
  local f="$RUN_DIR/auth-$db.env"
  node "$STACK_DIR/auth-env.mjs" --db "$db" >"$f"
  printf '%s' "$f"
}

start_auth() {
  ensure_dirs
  local envf
  envf="$(auth_env_file postgres)"
  (
    set -a
    # shellcheck disable=SC1090
    source "$envf"
    set +a
    cd "$BIN_DIR/auth"
    spawn_bg auth "$LOG_DIR/auth.log" ./auth
  )
  if ! wait_for "auth" 60 http_ok "http://127.0.0.1:${AUTH_PORT}/health"; then
    tail -n 30 "$LOG_DIR/auth.log" >&2 || true
    die "GoTrue não ficou saudável (veja .local/logs/auth.log)"
  fi
  log "auth (GoTrue $AUTH_VERSION) ok em 127.0.0.1:${AUTH_PORT}"
}

start_rest() {
  ensure_dirs
  (
    export PGRST_DB_URI="postgres://authenticator:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/postgres"
    export PGRST_DB_SCHEMAS="public"
    export PGRST_DB_EXTRA_SEARCH_PATH="public,extensions"
    export PGRST_DB_ANON_ROLE="anon"
    export PGRST_DB_MAX_ROWS="1000"
    export PGRST_DB_CHANNEL_ENABLED="true"
    export PGRST_DB_POOL="10"
    export PGRST_JWT_SECRET="$JWT_SECRET"
    export PGRST_SERVER_HOST="127.0.0.1"
    export PGRST_SERVER_PORT="$REST_PORT"
    export PGRST_ADMIN_SERVER_HOST="127.0.0.1"
    export PGRST_ADMIN_SERVER_PORT="$REST_ADMIN_PORT"
    export PGRST_LOG_LEVEL="warn"
    unset PGHOST PGPORT PGUSER PGPASSWORD
    spawn_bg rest "$LOG_DIR/rest.log" "$BIN_DIR/postgrest"
  )
  if ! wait_for "rest" 60 http_ok "http://127.0.0.1:${REST_ADMIN_PORT}/ready"; then
    tail -n 30 "$LOG_DIR/rest.log" >&2 || true
    die "PostgREST não ficou saudável (veja .local/logs/rest.log)"
  fi
  log "rest (PostgREST $POSTGREST_VERSION) ok em 127.0.0.1:${REST_PORT}"
}

auth_healthy() { http_ok "http://127.0.0.1:${AUTH_PORT}/health"; }
rest_healthy() { http_ok "http://127.0.0.1:${REST_ADMIN_PORT}/ready"; }
gateway_healthy() { http_ok "http://127.0.0.1:${GATEWAY_PORT}/health"; }
