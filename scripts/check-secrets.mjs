#!/usr/bin/env node
// Confere que segredos não vazam para o código do navegador (pnpm check:secrets). Sem dependências
// novas: as importações são lidas pelo parser do TypeScript (devDependency do projeto), não por regex.
//
// Regras (D71):
//  1. Nomes de segredo ("service_role", "secret_key", sem diferenciar maiúsculas, com "_", "-" ou
//     nada no meio: SUPABASE_SERVICE_ROLE_KEY, supabaseSecretKey…) só podem aparecer em
//     src/lib/supabase/admin.ts e src/lib/env.server.ts, e esses dois arquivos têm de começar com
//     `import "server-only"`. Vale para src/ e para next.config.*.
//  2. next.config.* não pode ter bloco `env`: tudo o que entra nele é embutido no código do build,
//     inclusive no do navegador.
//  3. Nenhum arquivo "use client" pode importar admin.ts ou env.server.ts, nem direta nem
//     indiretamente (a busca para em arquivos "use server", que viram referências no cliente).
//  4. Quem pode importar: env.server.ts só por admin.ts; admin.ts só por arquivos `*.server.ts`
//     que começam com `import "server-only"`. Assim um Server Component não recebe o segredo para
//     repassá-lo como prop a um Client Component (o que o mandaria no HTML/RSC).
//     Regras 3 e 4 valem para toda forma de importar (import/export ... from, import(), require,
//     import x = require), lidas pelo parser do TypeScript (D103: um regex deixava passar
//     identificador com $, comentário dentro das chaves e import() com template literal).
//     import() ou require() com argumento que não é texto fixo é erro em src/ (não dá para saber
//     o que ele importa).
//  5. Nenhuma variável NEXT_PUBLIC_* pode ter SECRET ou SERVICE no nome.
//  6. Se existir build (.next), o valor da chave secreta não pode aparecer em nenhum arquivo dele
//     (fora .next/cache) e .next/static não pode citar SUPABASE_SECRET_KEY/SUPABASE_SERVICE_ROLE_KEY.
//     Sem o valor da chave (nem no ambiente nem no .env.local), em CI (CI=true) isso é erro; fora
//     de CI, aviso.
// O HTML e o RSC servidos de verdade são varridos pelo E2E (e2e/segredos.spec.ts).
//
// Uso: node scripts/check-secrets.mjs [--root <pasta>]   (--root é usado pelo autoteste)

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import ts from "typescript";

const args = process.argv.slice(2);
const rootIdx = args.indexOf("--root");
const ROOT =
  rootIdx >= 0 && args[rootIdx + 1]
    ? resolve(args[rootIdx + 1])
    : resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SRC = join(ROOT, "src");
const ADMIN = "src/lib/supabase/admin.ts";
const ENV_SERVER = "src/lib/env.server.ts";
const ALLOWED = new Set([ADMIN, ENV_SERVER]);
const SERVER_ONLY_TARGETS = new Set(["src/lib/supabase/admin", "src/lib/env.server"]);
const SECRET_NAME_RE = /service[_-]?role|secret[_-]?key/gi;
const SECRET_ENV_NAME_RE = /SUPABASE_(?:SECRET|SERVICE_ROLE)_KEY/g;
const CODE_EXTENSIONS = [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"];
const TEXT_EXTENSIONS = new Set([...CODE_EXTENSIONS, ".css", ".json", ".md", ".html", ".svg"]);
const CONFIG_NAMES = ["next.config.ts", "next.config.mts", "next.config.mjs", "next.config.js"];

const problems = [];
const warnings = [];
const rel = (file) => relative(ROOT, file).split(sep).join("/");

function walk(dir, files = [], skip = () => false) {
  if (!existsSync(dir)) return files;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (skip(full)) continue;
    if (entry.isDirectory()) walk(full, files, skip);
    else if (entry.isFile()) files.push(full);
  }
  return files;
}

function lineOf(text, index) {
  return text.slice(0, index).split("\n").length;
}

function stripComments(text) {
  return text.replace(/^﻿/, "").replace(/\/\*[\s\S]*?\*\/|^\s*\/\/.*$/gm, "");
}

/** Primeira instrução do arquivo (ignora linhas vazias e comentários). */
function firstStatement(text) {
  return (
    stripComments(text)
      .split("\n")
      .find((line) => line.trim() !== "")
      ?.trim() ?? ""
  );
}

function hasDirective(text, directive) {
  const first = firstStatement(text);
  return (
    first === `"${directive}";` ||
    first === `'${directive}';` ||
    first === `"${directive}"` ||
    first === `'${directive}'`
  );
}

const startsWithServerOnly = (text) => {
  const first = firstStatement(text);
  return first === `import "server-only";` || first === `import 'server-only';`;
};

// ---------------------------------------------------------------- regra 1

const srcFiles = walk(SRC).filter((file) => TEXT_EXTENSIONS.has(extname(file)));
const contents = new Map(srcFiles.map((file) => [file, readFileSync(file, "utf8")]));
const configFiles = CONFIG_NAMES.map((name) => join(ROOT, name)).filter(existsSync);
for (const file of configFiles) contents.set(file, readFileSync(file, "utf8"));

for (const file of [...srcFiles, ...configFiles]) {
  const name = rel(file);
  if (ALLOWED.has(name)) continue;
  const text = contents.get(file);
  for (const match of text.matchAll(SECRET_NAME_RE)) {
    problems.push(
      `${name}:${lineOf(text, match.index)} contém "${match[0]}" (nome de segredo; permitido só em ${[...ALLOWED].join(" e ")})`,
    );
  }
}

for (const name of ALLOWED) {
  const file = join(ROOT, name);
  if (!existsSync(file)) {
    problems.push(`${name} não existe (esperado como único ponto de acesso à chave secreta)`);
    continue;
  }
  if (!startsWithServerOnly(readFileSync(file, "utf8"))) {
    problems.push(
      `${name} precisa começar com import "server-only"; (começa com: ${firstStatement(readFileSync(file, "utf8")) || "vazio"})`,
    );
  }
}

// ---------------------------------------------------------------- regra 2

for (const file of configFiles) {
  const text = stripComments(contents.get(file));
  const match = /(^|[{,\s])env\s*:/m.exec(text);
  if (match) {
    problems.push(
      `${rel(file)} tem bloco \`env\` (é embutido no build, inclusive no navegador); use variáveis NEXT_PUBLIC_* só para valores públicos`,
    );
  }
}

// ---------------------------------------------------------------- regras 3 e 4

const specifierCache = new Map();

/**
 * Módulos importados pelo arquivo, lidos pela árvore sintática do TypeScript: import/export ...
 * from, import "x", import() e require() com texto fixo, import x = require("x"). `import type` e
 * `export type` não vão para o bundle e ficam de fora. import()/require() com argumento que não é
 * texto fixo vira problema (o destino não pode ser conferido).
 */
function specifiers(file, text) {
  if (specifierCache.has(file)) return specifierCache.get(file);
  const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true);
  const found = [];
  const literal = (node) =>
    node && (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node))
      ? node.text
      : null;
  const visit = (node) => {
    if (ts.isImportDeclaration(node)) {
      if (!node.importClause?.isTypeOnly) {
        const spec = literal(node.moduleSpecifier);
        if (spec) found.push(spec);
      }
    } else if (ts.isExportDeclaration(node)) {
      const spec = node.isTypeOnly ? null : literal(node.moduleSpecifier);
      if (spec) found.push(spec);
    } else if (ts.isImportEqualsDeclaration(node)) {
      if (!node.isTypeOnly && ts.isExternalModuleReference(node.moduleReference)) {
        const spec = literal(node.moduleReference.expression);
        if (spec) found.push(spec);
      }
    } else if (
      ts.isCallExpression(node) &&
      (node.expression.kind === ts.SyntaxKind.ImportKeyword ||
        (ts.isIdentifier(node.expression) && node.expression.text === "require"))
    ) {
      const spec = literal(node.arguments[0]);
      if (spec) found.push(spec);
      else {
        const { line } = source.getLineAndCharacterOfPosition(node.getStart(source));
        problems.push(
          `${rel(file)}:${line + 1} importa com argumento que não é texto fixo (${node.getText(source).slice(0, 80)}); escreva o caminho do módulo`,
        );
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(source);
  specifierCache.set(file, found);
  return found;
}

function resolveSpecifier(fromFile, spec) {
  let base;
  if (spec.startsWith("@/")) base = join(SRC, spec.slice(2));
  else if (spec.startsWith(".")) base = resolve(dirname(fromFile), spec);
  else return null;
  const candidates = [
    base,
    ...CODE_EXTENSIONS.map((ext) => base + ext),
    ...CODE_EXTENSIONS.map((ext) => join(base, `index${ext}`)),
  ];
  return (
    candidates.find((candidate) => existsSync(candidate) && statSync(candidate).isFile()) ?? base
  );
}

const withoutExtension = (name) => name.replace(/\.(?:[cm]?[jt]sx?)$/, "").replace(/\/index$/, "");

const codeFiles = srcFiles.filter((file) => CODE_EXTENSIONS.includes(extname(file)));
const clientFiles = codeFiles.filter((file) =>
  hasDirective(contents.get(file) ?? "", "use client"),
);

for (const entry of clientFiles) {
  const queue = [{ file: entry, chain: [rel(entry)] }];
  const seen = new Set([entry]);
  while (queue.length > 0) {
    const { file, chain } = queue.shift();
    const text = contents.get(file) ?? (existsSync(file) ? readFileSync(file, "utf8") : "");
    for (const spec of specifiers(file, text)) {
      const target = resolveSpecifier(file, spec);
      if (!target) continue;
      const targetName = rel(target);
      if (SERVER_ONLY_TARGETS.has(withoutExtension(targetName))) {
        problems.push(
          `código de cliente importa ${withoutExtension(targetName)}: ${[...chain, targetName].join(" → ")}`,
        );
        continue;
      }
      if (seen.has(target) || !existsSync(target)) continue;
      seen.add(target);
      const targetText = contents.get(target) ?? readFileSync(target, "utf8");
      // Módulos "use server" chegam ao cliente só como referência; o código deles fica no servidor.
      if (hasDirective(targetText, "use server")) continue;
      queue.push({ file: target, chain: [...chain, targetName] });
    }
  }
}

for (const file of codeFiles) {
  const name = rel(file);
  const text = contents.get(file) ?? "";
  for (const spec of specifiers(file, text)) {
    const target = resolveSpecifier(file, spec);
    if (!target) continue;
    const targetName = withoutExtension(rel(target));
    if (targetName === withoutExtension(ENV_SERVER) && name !== ADMIN) {
      problems.push(`${name} importa ${ENV_SERVER} (só ${ADMIN} pode ler os segredos)`);
    }
    if (targetName === withoutExtension(ADMIN)) {
      const okServerModule = /\.server\.[cm]?[jt]sx?$/.test(name) && startsWithServerOnly(text);
      if (!okServerModule) {
        problems.push(
          `${name} importa ${ADMIN} (só módulos *.server.ts com import "server-only" podem, para o cliente admin não chegar a páginas e componentes)`,
        );
      }
    }
  }
}

// ---------------------------------------------------------------- regra 5

const PUBLIC_SECRET_RE = /NEXT_PUBLIC_[A-Z0-9_]*(?:SECRET|SERVICE)[A-Z0-9_]*/g;
const envFiles = readdirSync(ROOT)
  .filter((name) => name.startsWith(".env"))
  .map((name) => join(ROOT, name));

for (const file of [...srcFiles, ...envFiles, ...configFiles]) {
  const text = contents.get(file) ?? readFileSync(file, "utf8");
  for (const match of text.matchAll(PUBLIC_SECRET_RE)) {
    problems.push(
      `${rel(file)}:${lineOf(text, match.index)} variável pública com nome de segredo: ${match[0]}`,
    );
  }
}
for (const name of Object.keys(process.env)) {
  if (/^NEXT_PUBLIC_.*(?:SECRET|SERVICE)/.test(name)) {
    problems.push(`variável de ambiente pública com nome de segredo: ${name}`);
  }
}

// ---------------------------------------------------------------- regra 6

function secretValues() {
  const values = new Set();
  for (const key of ["SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY"]) {
    if (process.env[key]) values.add(process.env[key].trim());
  }
  const envLocal = join(ROOT, ".env.local");
  if (existsSync(envLocal)) {
    for (const line of readFileSync(envLocal, "utf8").split(/\r?\n/)) {
      const match = /^\s*SUPABASE_(?:SECRET|SERVICE_ROLE)_KEY\s*=\s*(.+?)\s*$/.exec(line);
      if (match) values.add(match[1].replace(/^["']|["']$/g, ""));
    }
  }
  return [...values].filter((value) => value.length >= 20);
}

const buildDir = join(ROOT, ".next");
const staticDir = join(buildDir, "static");
const isCi = /^(1|true)$/i.test(process.env.CI ?? "");
let scannedBuild = 0;
if (existsSync(buildDir)) {
  const buildFiles = walk(buildDir, [], (full) => full === join(buildDir, "cache"));
  for (const file of buildFiles) {
    if (!file.startsWith(staticDir + sep)) continue;
    const text = readFileSync(file, "latin1");
    for (const match of text.matchAll(SECRET_ENV_NAME_RE)) {
      problems.push(`${rel(file)} cita ${match[0]} (código do navegador)`);
    }
  }
  const secrets = secretValues();
  if (secrets.length === 0) {
    const message =
      "sem SUPABASE_SECRET_KEY no ambiente nem no .env.local: o valor da chave não foi procurado no build";
    if (isCi) problems.push(`${message} (em CI é obrigatório)`);
    else warnings.push(message);
  } else {
    for (const file of buildFiles) {
      scannedBuild += 1;
      const text = readFileSync(file, "latin1");
      for (const secret of secrets) {
        if (text.includes(secret)) problems.push(`${rel(file)} contém o valor da chave secreta`);
      }
    }
  }
}

// ---------------------------------------------------------------- resultado

for (const warning of warnings) console.warn(`[check:secrets] aviso: ${warning}.`);

if (problems.length > 0) {
  console.error(`[check:secrets] ${problems.length} problema(s):`);
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}

console.log(
  `[check:secrets] ok: ${srcFiles.length} arquivos em src/, ${clientFiles.length} arquivos "use client" ` +
    `verificados, ${existsSync(buildDir) ? `${scannedBuild} arquivos do build (.next, sem cache) varridos` : "sem build para varrer"}.`,
);
