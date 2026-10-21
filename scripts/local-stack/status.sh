#!/usr/bin/env bash
# Mostra cada serviço da stack local e se está saudável.
# Saída 0 quando tudo está saudável; 1 caso contrário.
# Uso: pnpm stack:status

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ALL_OK=1
row() {
  # row <serviço> <endereço> <pid> <ok?>
  local state="saudável"
  if [ "$4" != "1" ]; then
    state="FORA DO AR"
    ALL_OK=0
  fi
  printf '  %-10s %-28s %-8s %s\n' "$1" "$2" "${3:--}" "$state"
}

check() { if "$@"; then echo 1; else echo 0; fi; }

pg_pid=""
[ -f "$PGDATA/postmaster.pid" ] && pg_pid="$(head -n1 "$PGDATA/postmaster.pid" 2>/dev/null || true)"

# (larguras +1 nos títulos com Ç/Ú: o printf do bash conta bytes, não caracteres)
printf '\n  %-11s %-29s %-8s %s\n' "SERVIÇO" "ENDEREÇO" "PID" "SAÚDE"
row postgres "127.0.0.1:$DB_PORT" "$pg_pid" "$(check pg_is_ready)"
row rest "127.0.0.1:$REST_PORT" "$(pid_of rest)" "$(check rest_healthy)"
row auth "127.0.0.1:$AUTH_PORT" "$(pid_of auth)" "$(check auth_healthy)"
row gateway "$API_URL" "$(pid_of gateway)" "$(check gateway_healthy)"
row smtp "127.0.0.1:$SMTP_PORT" "$(pid_of smtp)" "$(check smtp_ok)"

if pg_is_ready; then
  tpl="$("${PSQL[@]}" -d template1 -Atc "select coalesce(shobj_description(oid, 'pg_database'), 'sem marca') from pg_database where datname = '$TEMPLATE_DB'" 2>/dev/null || true)"
  dbs="$("${PSQL[@]}" -d template1 -Atc "select string_agg(datname, ', ' order by datname) from pg_database where not datistemplate" 2>/dev/null || true)"
  printf '\n  template: %s\n  bancos:   %s\n' "${tpl:-ausente}" "${dbs:-?}"
fi
printf '  API:      %s   e-mails: .local/mail   logs: .local/logs\n\n' "$API_URL"

[ "$ALL_OK" = "1" ]
