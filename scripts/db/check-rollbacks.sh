#!/usr/bin/env bash
# Verifica os rollbacks das migrations (supabase/rollbacks/<mesmo nome>.sql).
#
#   1. Toda migration tem rollback com o mesmo nome, e vice-versa.
#   2. Num banco temporário (clone do template, sem migrations), tira uma "foto"
#      do catálogo (extensões, schemas, tabelas, colunas com privilégio, funções,
#      tipos, constraints, policies, gatilhos, privilégios padrão e buckets).
#   3. Aplica as migrations uma a uma (em ordem), tirando a foto depois de cada uma.
#   4. Aplica os rollbacks em ordem inversa e exige, depois de CADA rollback, a
#      foto idêntica à de antes da migration correspondente (cada rollback desfaz
#      exatamente a sua migration). No fim exige também:
#        - nada em public (tabelas, views, sequências, tipos, funções);
#        - schema private removido; buckets e policies de storage removidos.
#   5. Aplica as migrations de novo (foto idêntica à do passo 3) e roda o seed.
#
# Uso:
#   pnpm db:rollback-check
#   ROLLBACK_DB=outro_nome pnpm db:rollback-check   # banco temporário (padrão rollback_check)
#
# O banco temporário é apagado no fim, mesmo em caso de erro. Sai com código != 0 se falhar.

source "$(dirname "${BASH_SOURCE[0]}")/../local-stack/lib.sh"

ROLLBACK_DB="${ROLLBACK_DB:-rollback_check}"
MIGRATIONS_DIR="$ROOT_DIR/supabase/migrations"
ROLLBACKS_DIR="$ROOT_DIR/supabase/rollbacks"
SEED_FILE="$ROOT_DIR/supabase/seed.sql"

[[ "$ROLLBACK_DB" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || die "ROLLBACK_DB inválido: '$ROLLBACK_DB'"
case "$ROLLBACK_DB" in
  postgres | template0 | template1 | "$TEMPLATE_DB" | contrib_regression)
    die "ROLLBACK_DB não pode ser '$ROLLBACK_DB' (o banco é apagado no fim)" ;;
esac

pg_is_ready || die "Postgres local não está rodando. Rode \`pnpm stack:up\`."

say() { printf '[db:rollback-check] %s\n' "$*"; }

WORK_DIR="$(mktemp -d)"
cleanup() {
  local code=$?
  "${PSQL[@]}" -d template1 -c "drop database if exists \"$ROLLBACK_DB\" with (force)" >/dev/null 2>&1 || true
  rm -rf "$WORK_DIR"
  exit "$code"
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# 1. Pareamento migration <-> rollback
# -----------------------------------------------------------------------------
shopt -s nullglob
migrations=("$MIGRATIONS_DIR"/*.sql)
rollbacks=("$ROLLBACKS_DIR"/*.sql)
shopt -u nullglob
[ "${#migrations[@]}" -gt 0 ] || die "nenhuma migration em supabase/migrations"
mapfile -t migrations < <(printf '%s\n' "${migrations[@]}" | LC_ALL=C sort)

missing=0
for f in "${migrations[@]}"; do
  base="$(basename "$f")"
  if [ ! -f "$ROLLBACKS_DIR/$base" ]; then
    printf '  faltando rollback: supabase/rollbacks/%s\n' "$base" >&2
    missing=1
  fi
done
for f in "${rollbacks[@]}"; do
  base="$(basename "$f")"
  if [ ! -f "$MIGRATIONS_DIR/$base" ]; then
    printf '  rollback sem migration: supabase/rollbacks/%s\n' "$base" >&2
    missing=1
  fi
done
[ "$missing" = "0" ] || die "migrations e rollbacks não batem"
say "${#migrations[@]} migrations, todas com rollback"

# -----------------------------------------------------------------------------
# Auxiliares
# -----------------------------------------------------------------------------
apply_file() {
  # apply_file <arquivo>: aplica numa transação, parando no primeiro erro
  PGOPTIONS="-c client_min_messages=warning" "${PSQL[@]}" -d "$ROLLBACK_DB" --single-transaction -f "$1" >/dev/null ||
    die "falhou: ${1#"$ROOT_DIR"/}"
}

apply_migrations() {
  local f
  for f in "${migrations[@]}"; do apply_file "$f"; done
}

snapshot() {
  # snapshot <arquivo de saída>: catálogo em texto, ordenado, sem OIDs
  "${PSQL[@]}" -d "$ROLLBACK_DB" -At >"$1" <<'SQL'
with interesting as (
  select oid, nspname from pg_namespace
  where nspname in ('public', 'private', 'storage', 'auth', 'extensions')
)
select line from (
  select 'extension ' || e.extname || ' @' || e.extnamespace::regnamespace as line
  from pg_extension e
  union all
  select 'schema ' || n.nspname || ' acl=' || coalesce(n.nspacl::text, '')
  from pg_namespace n
  where n.nspname not like 'pg\_%' and n.nspname not in ('information_schema', 'supabase_migrations')
  union all
  select 'relation ' || i.nspname || '.' || c.relname || ' kind=' || c.relkind::text
         || ' rls=' || c.relrowsecurity || ' acl=' || coalesce(c.relacl::text, '')
  from pg_class c join interesting i on i.oid = c.relnamespace
  union all
  select 'column-acl ' || i.nspname || '.' || c.relname || '.' || a.attname || ' ' || a.attacl::text
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join interesting i on i.oid = c.relnamespace
  where a.attacl is not null and not a.attisdropped
  union all
  select 'function ' || p.oid::regprocedure || ' secdef=' || p.prosecdef
         || ' config=' || coalesce(p.proconfig::text, '') || ' acl=' || coalesce(p.proacl::text, '')
  from pg_proc p join interesting i on i.oid = p.pronamespace
  union all
  select 'type ' || t.oid::regtype
  from pg_type t join interesting i on i.oid = t.typnamespace
  where i.nspname in ('public', 'private')
  union all
  select 'constraint ' || i.nspname || '.' || coalesce(c.conrelid::regclass::text, '-') || '.' || c.conname
  from pg_constraint c join interesting i on i.oid = c.connamespace
  union all
  select 'policy ' || p.schemaname || '.' || p.tablename || '.' || p.policyname || ' ' || p.cmd
  from pg_policies p
  union all
  select 'trigger ' || t.tgrelid::regclass || '.' || t.tgname
  from pg_trigger t
  where not t.tgisinternal
  union all
  select 'default-acl ' || d.defaclrole::regrole || ' ' || d.defaclnamespace::regnamespace || ' '
         || d.defaclobjtype::text || ' ' || d.defaclacl::text
  from pg_default_acl d
  union all
  select 'bucket ' || b.id || ' public=' || coalesce(b.public::text, '')
  from storage.buckets b
) all_lines
order by line;
SQL
}

count_leftovers() {
  "${PSQL[@]}" -d "$ROLLBACK_DB" -At <<'SQL'
select concat_ws(' ',
  'relacoes_public=' || (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                         where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'S', 'f')),
  'tipos_public=' || (select count(*) from pg_type t join pg_namespace n on n.oid = t.typnamespace
                      where n.nspname = 'public'),
  'funcoes_public=' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                        where n.nspname = 'public'),
  'schema_private=' || (select count(*) from pg_namespace where nspname = 'private'),
  'buckets=' || (select count(*) from storage.buckets where id in ('evidences', 'references')),
  'policies_storage=' || (select count(*) from pg_policies where schemaname = 'storage'),
  'gatilhos_auth_users=' || (select count(*) from pg_trigger
                             where tgrelid = 'auth.users'::regclass and not tgisinternal)
);
SQL
}

# -----------------------------------------------------------------------------
# 2. Banco temporário limpo (clone do template, sem migrations nem seed)
# -----------------------------------------------------------------------------
mkdir -p "$WORK_DIR/vazio"
DB_NAME="$ROLLBACK_DB" MIGRATIONS_DIR="$WORK_DIR/vazio" SEED_FILE="$WORK_DIR/sem-seed.sql" \
  bash "$ROOT_DIR/scripts/db/reset.sh" >/dev/null
snapshot "$WORK_DIR/snap-0.txt"
say "banco $ROLLBACK_DB criado do template ($(wc -l <"$WORK_DIR/snap-0.txt") objetos no catálogo)"

# -----------------------------------------------------------------------------
# 3. Migrations uma a uma, com foto depois de cada
# -----------------------------------------------------------------------------
for i in "${!migrations[@]}"; do
  apply_file "${migrations[$i]}"
  snapshot "$WORK_DIR/snap-$((i + 1)).txt"
  if cmp -s "$WORK_DIR/snap-$i.txt" "$WORK_DIR/snap-$((i + 1)).txt"; then
    die "a migration $(basename "${migrations[$i]}") não mudou nada no catálogo"
  fi
done
total="${#migrations[@]}"
say "migrations aplicadas uma a uma ($(wc -l <"$WORK_DIR/snap-$total.txt") objetos no catálogo)"

# -----------------------------------------------------------------------------
# 4. Rollbacks em ordem inversa: cada um volta exatamente à foto anterior
# -----------------------------------------------------------------------------
for ((i = total - 1; i >= 0; i--)); do
  base="$(basename "${migrations[$i]}")"
  apply_file "$ROLLBACKS_DIR/$base"
  snapshot "$WORK_DIR/rollback.txt"
  if ! diff -u "$WORK_DIR/snap-$i.txt" "$WORK_DIR/rollback.txt" >"$WORK_DIR/diff.txt"; then
    cat "$WORK_DIR/diff.txt" >&2
    die "supabase/rollbacks/$base não desfaz exatamente a migration (diferenças acima)"
  fi
done

leftovers="$(count_leftovers)"
expected="relacoes_public=0 tipos_public=0 funcoes_public=0 schema_private=0 buckets=0 policies_storage=0 gatilhos_auth_users=0"
if [ "$leftovers" != "$expected" ]; then
  printf '  esperado: %s\n  obtido:   %s\n' "$expected" "$leftovers" >&2
  die "os rollbacks deixaram objetos para trás"
fi
say "rollbacks em ordem inversa: cada um voltou o catálogo exatamente ao estado anterior ($leftovers)"

# -----------------------------------------------------------------------------
# 5. Migrations de novo + seed
# -----------------------------------------------------------------------------
apply_migrations
snapshot "$WORK_DIR/reaplicado.txt"
if ! diff -u "$WORK_DIR/snap-$total.txt" "$WORK_DIR/reaplicado.txt" >"$WORK_DIR/diff.txt"; then
  cat "$WORK_DIR/diff.txt" >&2
  die "reaplicar as migrations não reproduziu o mesmo catálogo"
fi
say "migrations reaplicadas: catálogo idêntico ao da primeira aplicação"

if [ -f "$SEED_FILE" ]; then
  apply_file "$SEED_FILE"
  say "seed aplicado sobre o schema reaplicado"
fi

say "OK"
