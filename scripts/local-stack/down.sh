#!/usr/bin/env bash
# Para a stack local (gateway, SMTP, GoTrue, PostgREST e Postgres). Os dados ficam em .local/.
# Uso: pnpm stack:down

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ensure_dirs
exec 7>"$LOCK_DIR/stack.lock"
flock 7

for svc in gateway smtp auth rest; do
  stop_service "$svc"
done

if [ -s "$PGDATA/PG_VERSION" ] && as_pg "$PG_BIN/pg_ctl" -D "$PGDATA" status >/dev/null 2>&1; then
  as_pg "$PG_BIN/pg_ctl" -D "$PGDATA" -m fast -w -t 60 stop >/dev/null
  log "postgres parado"
fi

log "stack parada"
