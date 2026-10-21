// Leitor mínimo de TOML (sem dependências) para o subconjunto usado em supabase/config.toml:
// tabelas [a.b.c], chaves simples, strings "..." e '...', booleanos, números e arrays de uma linha.
// Linhas fora desse subconjunto são ignoradas (não precisamos delas na stack local).

function parseString(src, i) {
  const quote = src[i];
  let out = "";
  i++;
  while (i < src.length && src[i] !== quote) {
    if (quote === '"' && src[i] === "\\") {
      const n = src[i + 1];
      const map = { n: "\n", t: "\t", r: "\r", '"': '"', "\\": "\\" };
      if (n === "u") {
        out += String.fromCharCode(parseInt(src.slice(i + 2, i + 6), 16));
        i += 6;
        continue;
      }
      out += map[n] ?? n;
      i += 2;
      continue;
    }
    out += src[i];
    i++;
  }
  return [out, i + 1];
}

function parseValue(raw) {
  const v = raw.trim();
  if (v.startsWith('"') || v.startsWith("'")) return parseString(v, 0)[0];
  if (v === "true") return true;
  if (v === "false") return false;
  if (/^[+-]?\d+(\.\d+)?$/.test(v)) return Number(v);
  if (v.startsWith("[")) {
    const items = [];
    let i = 1;
    while (i < v.length) {
      const c = v[i];
      if (c === '"' || c === "'") {
        const [s, next] = parseString(v, i);
        items.push(s);
        i = next;
      } else if (c === "]") {
        break;
      } else if (/[\d+-]/.test(c)) {
        const m = /^[+-]?\d+(\.\d+)?/.exec(v.slice(i));
        items.push(Number(m[0]));
        i += m[0].length;
      } else if (v.startsWith("true", i)) {
        items.push(true);
        i += 4;
      } else if (v.startsWith("false", i)) {
        items.push(false);
        i += 5;
      } else {
        i++;
      }
    }
    return items;
  }
  return undefined;
}

function stripComment(line) {
  let inStr = null;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inStr) {
      if (c === "\\" && inStr === '"') i++;
      else if (c === inStr) inStr = null;
    } else if (c === '"' || c === "'") inStr = c;
    else if (c === "#") return line.slice(0, i);
  }
  return line;
}

/** Converte o texto TOML em objeto aninhado. */
export function parseToml(text) {
  const root = {};
  let table = root;
  for (const rawLine of text.split(/\r?\n/)) {
    const line = stripComment(rawLine).trim();
    if (!line) continue;
    const header = /^\[([^\[\]]+)\]$/.exec(line);
    if (header) {
      table = root;
      for (const part of header[1].split(".").map((p) => p.trim().replace(/^"|"$/g, ""))) {
        table[part] ??= {};
        table = table[part];
      }
      continue;
    }
    const kv = /^([A-Za-z0-9_\-]+|"[^"]+")\s*=\s*(.+)$/.exec(line);
    if (!kv) continue;
    const key = kv[1].replace(/^"|"$/g, "");
    const value = parseValue(kv[2]);
    if (value !== undefined) table[key] = value;
  }
  return root;
}
