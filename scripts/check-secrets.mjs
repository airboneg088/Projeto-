#!/usr/bin/env node
// Confere que segredos não vazam para o código do navegador (pnpm check:secrets). Sem dependências.
//
// Regras:
//  1. "SUPABASE_SECRET_KEY" e "service_role" só podem aparecer em src/lib/supabase/admin.ts e
//     src/lib/env.server.ts, e esses dois arquivos têm de começar com `import "server-only"`.
//  2. Nenhum arquivo "use client" pode importar admin.ts ou env.server.ts, nem direta nem
//     indiretamente (a busca para em arquivos "use server", que viram referências no cliente).
//  3. Nenhuma variável NEXT_PUBLIC_* pode ter SECRET ou SERVICE no nome.
//  4. Se existir .next/static (build feito), o valor da chave secreta não pode aparecer nele.

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SRC = join(ROOT, "src");
const ALLOWED = new Set(["src/lib/supabase/admin.ts", "src/lib/env.server.ts"]);
const SERVER_ONLY_TARGETS = new Set(["src/lib/supabase/admin", "src/lib/env.server"]);
const FORBIDDEN_WORDS = ["SUPABASE_SECRET_KEY", "service_role"];
const CODE_EXTENSIONS = [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"];
const TEXT_EXTENSIONS = new Set([...CODE_EXTENSIONS, ".css", ".json", ".md", ".html", ".svg"]);

const problems = [];
const rel = (file) => relative(ROOT, file).split(sep).join("/");

function walk(dir, files = []) {
  if (!existsSync(dir)) return files;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, files);
    else if (entry.isFile()) files.push(full);
  }
  return files;
}

function lineOf(text, index) {
  return text.slice(0, index).split("\n").length;
}

/** Primeira instrução do arquivo (ignora linhas vazias e comentários). */
function firstStatement(text) {
  const withoutComments = text.replace(/^﻿/, "").replace(/\/\*[\s\S]*?\*\/|^\s*\/\/.*$/gm, "");
  return (
    withoutComments
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

// ---------------------------------------------------------------- regra 1

const srcFiles = walk(SRC).filter((file) => TEXT_EXTENSIONS.has(extname(file)));
const contents = new Map(srcFiles.map((file) => [file, readFileSync(file, "utf8")]));

for (const [file, text] of contents) {
  const name = rel(file);
  if (ALLOWED.has(name)) continue;
  for (const word of FORBIDDEN_WORDS) {
    let index = text.indexOf(word);
    while (index !== -1) {
      problems.push(
        `${name}:${lineOf(text, index)} contém "${word}" (permitido só em ${[...ALLOWED].join(" e ")})`,
      );
      index = text.indexOf(word, index + word.length);
    }
  }
}

for (const name of ALLOWED) {
  const file = join(ROOT, name);
  if (!existsSync(file)) {
    problems.push(`${name} não existe (esperado como único ponto de acesso à chave secreta)`);
    continue;
  }
  const first = firstStatement(readFileSync(file, "utf8"));
  if (first !== `import "server-only";` && first !== `import 'server-only';`) {
    problems.push(
      `${name} precisa começar com import "server-only"; (começa com: ${first || "vazio"})`,
    );
  }
}

// ---------------------------------------------------------------- regra 2

const IMPORT_RE =
  /(?:import|export)\s+(?:type\s+)?(?:[\w*{}\s,]+\s+from\s+)?["']([^"']+)["']|import\(\s*["']([^"']+)["']\s*\)|require\(\s*["']([^"']+)["']\s*\)/g;

function specifiers(text) {
  const found = [];
  for (const match of text.matchAll(IMPORT_RE)) {
    // `import type` não vai para o bundle.
    if (/^(?:import|export)\s+type\s/.test(match[0])) continue;
    const spec = match[1] ?? match[2] ?? match[3];
    if (spec) found.push(spec);
  }
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
    for (const spec of specifiers(text)) {
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

// ---------------------------------------------------------------- regra 3

const PUBLIC_SECRET_RE = /NEXT_PUBLIC_[A-Z0-9_]*(?:SECRET|SERVICE)[A-Z0-9_]*/g;
const envFiles = readdirSync(ROOT)
  .filter((name) => name.startsWith(".env"))
  .map((name) => join(ROOT, name));
const configFiles = ["next.config.ts", "next.config.mjs", "next.config.js"]
  .map((name) => join(ROOT, name))
  .filter(existsSync);

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

// ---------------------------------------------------------------- regra 4

function secretValues() {
  const values = new Set();
  if (process.env.SUPABASE_SECRET_KEY) values.add(process.env.SUPABASE_SECRET_KEY.trim());
  const envLocal = join(ROOT, ".env.local");
  if (existsSync(envLocal)) {
    for (const line of readFileSync(envLocal, "utf8").split(/\r?\n/)) {
      const match = /^\s*SUPABASE_SECRET_KEY\s*=\s*(.+?)\s*$/.exec(line);
      if (match) values.add(match[1].replace(/^["']|["']$/g, ""));
    }
  }
  return [...values].filter((value) => value.length >= 20);
}

const staticDir = join(ROOT, ".next", "static");
let scannedStatic = 0;
if (existsSync(staticDir)) {
  const secrets = secretValues();
  if (secrets.length === 0) {
    console.warn(
      "[check:secrets] aviso: sem SUPABASE_SECRET_KEY no ambiente nem no .env.local; o build não foi varrido.",
    );
  } else {
    for (const file of walk(staticDir)) {
      scannedStatic += 1;
      const text = readFileSync(file, "latin1");
      for (const secret of secrets) {
        if (text.includes(secret)) problems.push(`${rel(file)} contém o valor da chave secreta`);
      }
    }
  }
}

// ---------------------------------------------------------------- resultado

if (problems.length > 0) {
  console.error(`[check:secrets] ${problems.length} problema(s):`);
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}

console.log(
  `[check:secrets] ok: ${srcFiles.length} arquivos em src/, ${clientFiles.length} arquivos "use client" ` +
    `verificados, ${existsSync(staticDir) ? `${scannedStatic} arquivos em .next/static varridos` : "sem build para varrer"}.`,
);
