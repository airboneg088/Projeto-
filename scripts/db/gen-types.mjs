#!/usr/bin/env node
// Gera os tipos TypeScript do banco (schema public) no mesmo formato do
// `supabase gen types typescript`, sem Docker e sem dependências: lê o catálogo com o `psql`.
//
// Uso:
//   pnpm db:types                         # banco do DATABASE_URL (.env.local) ou 'postgres' local
//   DB_NAME=meu_teste pnpm db:types       # outro banco da stack local
//   pnpm db:types --db-url <url> --schema public --out <arquivo>
//   pnpm db:types --check                 # não grava; sai com erro se o arquivo estiver desatualizado
//
// Diferenças conhecidas em relação à CLI do Supabase (não afetam o uso com supabase-js):
//   - relacionamentos inferidos pelo PostgREST através de views não são listados;
//   - sobrecargas ambíguas de função viram união simples (a CLI emite um tipo de erro);
//   - domínios em argumentos/retorno de função viram o tipo base (a CLI emite `unknown`).

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const DEFAULT_OUT = join(ROOT, "src", "lib", "supabase", "database.types.ts");
const LOCAL_DB = (name) => `postgresql://postgres:postgres@127.0.0.1:54322/${name}`;

// ---------------------------------------------------------------- argumentos e ambiente

function parseArgs(argv) {
  const args = { schema: "public", out: process.env.TYPES_OUT || DEFAULT_OUT, check: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const value = () => {
      const next = argv[i + 1];
      if (next === undefined) fail(`faltou o valor de ${arg}`);
      i += 1;
      return next;
    };
    if (arg === "--db-url") args.dbUrl = value();
    else if (arg === "--schema") args.schema = value();
    else if (arg === "--out") args.out = resolve(value());
    else if (arg === "--check") args.check = true;
    else if (arg === "--help" || arg === "-h") {
      console.log("uso: gen-types.mjs [--db-url URL] [--schema public] [--out arquivo] [--check]");
      process.exit(0);
    } else fail(`argumento desconhecido: ${arg}`);
  }
  if (!/^[a-z_][a-z0-9_]*$/.test(args.schema)) fail(`schema inválido: ${args.schema}`);
  return args;
}

function fail(message) {
  console.error(`[db:types] ${message}`);
  process.exit(1);
}

function readDotEnvLocal(name) {
  const file = join(ROOT, ".env.local");
  if (!existsSync(file)) return undefined;
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    const match = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (match && match[1] === name) return match[2].replace(/^["']|["']$/g, "");
  }
  return undefined;
}

function resolveDbUrl(args) {
  if (args.dbUrl) return args.dbUrl;
  if (process.env.DB_NAME) return LOCAL_DB(process.env.DB_NAME);
  return process.env.DATABASE_URL || readDotEnvLocal("DATABASE_URL") || LOCAL_DB("postgres");
}

function findPsql() {
  const candidates = [
    process.env.PG_BIN && join(process.env.PG_BIN, "psql"),
    "/usr/lib/postgresql/17/bin/psql",
    "/usr/lib/postgresql/16/bin/psql",
  ].filter(Boolean);
  for (const candidate of candidates) if (existsSync(candidate)) return candidate;
  return "psql";
}

// ---------------------------------------------------------------- catálogo

const CATALOG_SQL = String.raw`
with
ext as (select objid from pg_depend where deptype = 'e'),
rels as (
  select c.oid, c.relname, c.relkind,
         case when c.relkind = 'v'
              then (pg_relation_is_updatable(c.oid::regclass, false) & 20) = 20
              else false end as updatable
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = :'schema'
    and c.relkind in ('r', 'p', 'v', 'm', 'f', 'c')
    and not c.relispartition
    and c.oid not in (select objid from ext)
)
select json_build_object(
  'relations', coalesce((
    select json_agg(json_build_object(
      'oid', r.oid, 'name', r.relname, 'kind', r.relkind, 'updatable', r.updatable,
      'columns', coalesce((
        select json_agg(json_build_object(
          'name', a.attname, 'type', a.atttypid, 'notnull', a.attnotnull,
          'hasdef', a.atthasdef, 'identity', a.attidentity, 'generated', a.attgenerated
        ) order by a.attnum)
        from pg_attribute a
        where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
      ), '[]'::json)
    ))
    from rels r
  ), '[]'::json),
  'fks', coalesce((
    select json_agg(json_build_object(
      'name', con.conname,
      'table', con.conrelid,
      'columns', (select json_agg(a.attname order by k.ord)
                  from unnest(con.conkey) with ordinality k(attnum, ord)
                  join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum),
      'refTable', rc.relname,
      'refColumns', (select json_agg(a.attname order by k.ord)
                     from unnest(con.confkey) with ordinality k(attnum, ord)
                     join pg_attribute a on a.attrelid = con.confrelid and a.attnum = k.attnum),
      'oneToOne', exists (
        select 1 from pg_index i
        where i.indrelid = con.conrelid and i.indisunique and i.indpred is null
          and i.indexprs is null
          and (select array_agg(x order by x) from unnest(i.indkey::int2[]) x)
              = (select array_agg(x order by x) from unnest(con.conkey) x)
      )
    ))
    from pg_constraint con
    join rels r on r.oid = con.conrelid
    join pg_class rc on rc.oid = con.confrelid
    join pg_namespace rn on rn.oid = rc.relnamespace
    -- Como a CLI: só chaves estrangeiras para tabelas do próprio schema (ex.: auth.users fica de fora).
    where con.contype = 'f' and rn.nspname = :'schema'
  ), '[]'::json),
  'functions', coalesce((
    select json_agg(json_build_object(
      'name', p.proname, 'retset', p.proretset, 'rettype', p.prorettype,
      'ndefaults', p.pronargdefaults,
      'argtypes', p.proargtypes::oid[],
      'allargtypes', p.proallargtypes,
      'argmodes', p.proargmodes::text[],
      'argnames', p.proargnames
    ) order by p.proname, p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = :'schema'
      and p.prokind = 'f'
      and p.oid not in (select objid from ext)
      and p.prorettype not in (
        'trigger'::regtype, 'event_trigger'::regtype, 'internal'::regtype,
        'language_handler'::regtype, 'fdw_handler'::regtype, 'table_am_handler'::regtype,
        'index_am_handler'::regtype, 'tsm_handler'::regtype
      )
      and not ('internal'::regtype = any (p.proargtypes::oid[]))
  ), '[]'::json),
  'types', (
    select json_agg(json_build_object(
      'oid', t.oid, 'name', t.typname, 'schema', tn.nspname, 'typtype', t.typtype,
      'elem', t.typelem, 'category', t.typcategory, 'base', t.typbasetype, 'relid', t.typrelid
    ))
    from pg_type t
    join pg_namespace tn on tn.oid = t.typnamespace
  ),
  'enums', coalesce((
    select json_agg(json_build_object('type', e.enumtypid, 'label', e.enumlabel)
                    order by e.enumtypid, e.enumsortorder)
    from pg_enum e
  ), '[]'::json),
  'enumTypes', coalesce((
    select json_agg(t.oid)
    from pg_type t
    join pg_namespace tn on tn.oid = t.typnamespace
    where tn.nspname = :'schema' and t.typtype = 'e' and t.oid not in (select objid from ext)
  ), '[]'::json)
)::text;
`;

function readCatalog(dbUrl, schema) {
  const psql = findPsql();
  try {
    const stdout = execFileSync(
      psql,
      ["-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1", "-v", `schema=${schema}`, "-d", dbUrl],
      {
        input: CATALOG_SQL,
        encoding: "utf8",
        stdio: ["pipe", "pipe", "pipe"],
        env: { ...process.env, PGCONNECT_TIMEOUT: "5" },
        maxBuffer: 64 * 1024 * 1024,
      },
    );
    return JSON.parse(stdout.trim());
  } catch (error) {
    const stderr =
      error && typeof error === "object" && "stderr" in error ? String(error.stderr) : "";
    fail(
      `não foi possível ler o catálogo (${redact(dbUrl)}).\n${stderr || String(error)}\n` +
        "A stack local está rodando? `pnpm stack:up`",
    );
  }
}

function redact(url) {
  return url.replace(/\/\/([^:/@]+):[^@]*@/, "//$1:***@");
}

// ---------------------------------------------------------------- tipos TS

const byName = (a, b) => a.localeCompare(b, "en");
const quote = (name) => JSON.stringify(name);

const NUMBER_TYPES = new Set(["int2", "int4", "int8", "float4", "float8", "numeric"]);
const STRING_TYPES = new Set([
  "bytea",
  "bpchar",
  "varchar",
  "date",
  "text",
  "citext",
  "time",
  "timetz",
  "timestamp",
  "timestamptz",
  "uuid",
  "vector",
  "interval",
]);

function createTyper(catalog, schema) {
  const types = new Map(catalog.types.map((t) => [t.oid, t]));
  const relations = new Map(catalog.relations.map((r) => [r.oid, r]));
  const schemaEnums = new Set(catalog.enumTypes);
  const enumLabels = new Map();
  for (const { type, label } of catalog.enums) {
    if (!enumLabels.has(type)) enumLabels.set(type, []);
    enumLabels.get(type).push(label);
  }

  function tsType(oid, depth = 0) {
    const t = types.get(oid);
    if (!t || depth > 10) return "unknown";
    if (t.typtype === "d") return tsType(t.base, depth + 1);
    if (t.category === "A" && t.elem) return `(${tsType(t.elem, depth + 1)})[]`;
    if (t.typtype === "e") {
      if (schemaEnums.has(oid)) return `Database[${quote(schema)}]["Enums"][${quote(t.name)}]`;
      const labels = enumLabels.get(oid) ?? [];
      return labels.length ? labels.map(quote).join(" | ") : "string";
    }
    if (t.typtype === "c") {
      const rel = relations.get(t.relid);
      if (rel && rel.kind === "c" && t.schema === schema) {
        return `Database[${quote(schema)}]["CompositeTypes"][${quote(t.name)}]`;
      }
      return "unknown";
    }
    if (t.name === "bool") return "boolean";
    if (NUMBER_TYPES.has(t.name)) return "number";
    if (STRING_TYPES.has(t.name)) return "string";
    if (t.name === "json" || t.name === "jsonb") return "Json";
    if (t.name === "void") return "undefined";
    if (t.name === "record") return "Record<string, unknown>";
    return "unknown";
  }

  return { tsType, relations, types };
}

/** Tipo de coluna com nulabilidade, como a CLI: `unknown` absorve null; Json NOT NULL vira NonNullable. */
function withNull(type, nullable) {
  if (type === "unknown") return "unknown";
  if (nullable) return `${type} | null`;
  if (type === "Json") return "NonNullable<Json>";
  return type;
}

const EMPTY = "{ [_ in never]: never }";

function objectType(entries) {
  if (entries.length === 0) return "{}";
  return `{\n${entries.join("\n")}\n}`;
}

function relationRow(rel, tsType) {
  const isView = rel.kind === "v" || rel.kind === "m";
  return [...rel.columns]
    .sort((a, b) => byName(a.name, b.name))
    .map((col) => `${quote(col.name)}: ${withNull(tsType(col.type), isView || !col.notnull)}`);
}

function renderTable(rel, fks, tsType) {
  const cols = [...rel.columns].sort((a, b) => byName(a.name, b.name));
  const row = relationRow(rel, tsType);
  const neverWritable = (col) => col.identity === "a" || col.generated !== "";
  const insert = cols.map((col) => {
    if (neverWritable(col)) return `${quote(col.name)}?: never`;
    const optional = !col.notnull || col.hasdef || col.identity === "d";
    return `${quote(col.name)}${optional ? "?" : ""}: ${withNull(tsType(col.type), !col.notnull)}`;
  });
  const update = cols.map((col) => {
    if (neverWritable(col)) return `${quote(col.name)}?: never`;
    return `${quote(col.name)}?: ${withNull(tsType(col.type), !col.notnull)}`;
  });
  const relationships = fks
    .filter((fk) => fk.table === rel.oid)
    .sort((a, b) => byName(a.name, b.name) || byName(a.refTable, b.refTable))
    .map(
      (fk) => `{
        foreignKeyName: ${quote(fk.name)}
        columns: [${fk.columns.map(quote).join(", ")}]
        isOneToOne: ${fk.oneToOne}
        referencedRelation: ${quote(fk.refTable)}
        referencedColumns: [${fk.refColumns.map(quote).join(", ")}]
      }`,
    );
  return `${quote(rel.name)}: {
    Row: ${objectType(row)}
    ComputedFields: never
    Insert: ${objectType(insert)}
    Update: ${objectType(update)}
    Relationships: [${relationships.join(", ")}]
  }`;
}

function renderView(rel, tsType) {
  const row = relationRow(rel, tsType);
  let writable = "";
  if (rel.updatable) {
    const optional = [...rel.columns]
      .sort((a, b) => byName(a.name, b.name))
      .map((col) => `${quote(col.name)}?: ${withNull(tsType(col.type), true)}`);
    writable = `\n    Insert: ${objectType(optional)}\n    Update: ${objectType(optional)}`;
  }
  return `${quote(rel.name)}: {
    Row: ${objectType(row)}
    ComputedFields: never${writable}
    Relationships: []
  }`;
}

function renderFunction(fn, typer) {
  const { tsType, relations, types } = typer;
  const all = fn.allargtypes ?? fn.argtypes;
  const modes = fn.argmodes ?? all.map(() => "i");
  const names = fn.argnames ?? [];

  const inputs = [];
  const tableColumns = [];
  all.forEach((oid, index) => {
    const mode = modes[index] ?? "i";
    const name = names[index] ?? "";
    if (mode === "i" || mode === "b" || mode === "v") inputs.push({ name, oid });
    if (mode === "t") tableColumns.push({ name, oid });
  });
  const firstOptional = inputs.length - (fn.ndefaults ?? 0);
  const args = inputs
    .map((arg, index) => ({ ...arg, optional: index >= firstOptional }))
    .sort((a, b) => byName(a.name, b.name))
    .map((arg) => `${quote(arg.name)}${arg.optional ? "?" : ""}: ${tsType(arg.oid)}`);
  const argsType = args.length ? `{ ${args.join("; ")} }` : "Record<PropertyKey, never>";

  const suffix = fn.retset ? "[]" : "";
  let returns;
  let setofOptions = "";
  if (tableColumns.length) {
    const cols = tableColumns
      .sort((a, b) => byName(a.name, b.name))
      .map((col) => `${quote(col.name)}: ${tsType(col.oid)}`);
    returns = `${objectType(cols)}[]`;
  } else {
    const retType = types.get(fn.rettype);
    const rel = retType ? relations.get(retType.relid) : undefined;
    const tsRet = tsType(fn.rettype);
    if (rel && rel.kind !== "c") {
      returns = `${objectType(relationRow(rel, tsType))}${suffix}`;
      setofOptions = `
      SetofOptions: {
        from: "*"
        to: ${quote(rel.name)}
        isOneToOne: ${!fn.retset}
        isSetofReturn: ${fn.retset}
      }`;
    } else {
      returns = `${tsRet}${suffix}`;
    }
  }
  return `{ Args: ${argsType}; Returns: ${returns}${setofOptions} }`;
}

function render(catalog, schema) {
  const typer = createTyper(catalog, schema);
  const { tsType, types: typesByOid } = typer;

  const rels = [...catalog.relations].sort((a, b) => byName(a.name, b.name));
  const tables = rels
    .filter((r) => r.kind === "r" || r.kind === "p" || r.kind === "f")
    .map((r) => renderTable(r, catalog.fks, tsType));
  const views = rels
    .filter((r) => r.kind === "v" || r.kind === "m")
    .map((r) => renderView(r, tsType));
  const composites = rels
    .filter((r) => r.kind === "c")
    .map((r) => {
      const attrs = [...r.columns]
        .sort((a, b) => byName(a.name, b.name))
        .map((col) => `${quote(col.name)}: ${withNull(tsType(col.type), true)}`);
      return `${quote(r.name)}: ${objectType(attrs)}`;
    });

  const fnGroups = new Map();
  for (const fn of catalog.functions) {
    if (!fnGroups.has(fn.name)) fnGroups.set(fn.name, []);
    fnGroups.get(fn.name).push(fn);
  }
  const functions = [...fnGroups.keys()].sort(byName).map((name) => {
    const variants = fnGroups.get(name).map((fn) => renderFunction(fn, typer));
    return `${quote(name)}: ${variants.join(" | ")}`;
  });

  const enumEntries = catalog.enumTypes
    .map((oid) => typesByOid.get(oid))
    .filter(Boolean)
    .sort((a, b) => byName(a.name, b.name));
  const labelsOf = (oid) => catalog.enums.filter((e) => e.type === oid).map((e) => e.label);
  const enums = enumEntries.map(
    (t) => `${quote(t.name)}: ${labelsOf(t.oid).map(quote).join(" | ")}`,
  );
  const enumConstants = enumEntries.map(
    (t) => `${quote(t.name)}: [${labelsOf(t.oid).map(quote).join(", ")}]`,
  );

  const section = (entries) => (entries.length ? `{\n${entries.join("\n")}\n}` : EMPTY);

  return `// Gerado por \`pnpm db:types\` (scripts/db/gen-types.mjs, schema ${schema}). Não editar à mão.

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  ${quote(schema)}: {
    Tables: ${section(tables)}
    Views: ${section(views)}
    Functions: ${section(functions)}
    Enums: ${section(enums)}
    CompositeTypes: ${section(composites)}
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, ${quote(schema)}>]

${HELPERS}

export const Constants = {
  ${quote(schema)}: {
    Enums: {${enumConstants.join(", ")}},
  },
} as const
`;
}

// Tipos auxiliares idênticos aos da CLI do Supabase.
const HELPERS = `export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never`;

// ---------------------------------------------------------------- formatação e saída

function format(source, outFile) {
  const prettier = join(ROOT, "node_modules", ".bin", "prettier");
  if (!existsSync(prettier)) return source;
  try {
    return execFileSync(prettier, ["--stdin-filepath", outFile], {
      cwd: ROOT,
      input: source,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    });
  } catch (error) {
    const stderr =
      error && typeof error === "object" && "stderr" in error ? String(error.stderr) : "";
    fail(`o Prettier rejeitou o arquivo gerado:\n${stderr}`);
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const dbUrl = resolveDbUrl(args);
  const catalog = readCatalog(dbUrl, args.schema);
  const output = format(render(catalog, args.schema), args.out);
  const shown = relative(ROOT, args.out) || args.out;
  const dbName = (() => {
    try {
      return new URL(dbUrl).pathname.replace(/^\//, "") || "?";
    } catch {
      return "?";
    }
  })();

  if (args.check) {
    const current = existsSync(args.out) ? readFileSync(args.out, "utf8") : "";
    if (current !== output) {
      console.error(
        `[db:types] ${shown} está desatualizado (banco=${dbName}). Rode \`pnpm db:types\`.`,
      );
      process.exit(1);
    }
    console.log(`[db:types] ${shown} está em dia (banco=${dbName}).`);
    return;
  }

  mkdirSync(dirname(args.out), { recursive: true });
  writeFileSync(args.out, output);
  const counts = [
    `${catalog.relations.filter((r) => ["r", "p", "f"].includes(r.kind)).length} tabelas`,
    `${catalog.relations.filter((r) => ["v", "m"].includes(r.kind)).length} views`,
    `${new Set(catalog.functions.map((f) => f.name)).size} funções`,
    `${catalog.enumTypes.length} enums`,
  ].join(", ");
  console.log(`[db:types] banco=${dbName} -> ${shown} (${counts})`);
}

main();
