#!/usr/bin/env node
// Servidor SMTP "sumidouro" para a stack local (sem dependências).
// Aceita qualquer mensagem e grava em .local/mail/<id>.eml (bruto) e <id>.json
// (assunto, remetente, destinatários, corpo decodificado e links), para testes E2E.
// Nunca entrega nada para fora.
//
// Uso: node scripts/local-stack/smtp-sink.mjs [--port 54325] [--dir .local/mail]

import { mkdirSync, writeFileSync, renameSync } from "node:fs";
import { createServer } from "node:net";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (name, def) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
};
const PORT = Number(opt("--port", "54325"));
const HOST = "127.0.0.1";
const DIR = resolve(opt("--dir", join(here, "../../.local/mail")));
mkdirSync(DIR, { recursive: true });

let seq = 0;

// ---------------------------------------------------------------------------
// Decodificação MIME mínima (quoted-printable, base64, multipart, RFC 2047)
// ---------------------------------------------------------------------------
function decodeQP(text) {
  const bytes = [];
  const src = text.replace(/=\r?\n/g, "");
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === "=" && /^[0-9A-Fa-f]{2}$/.test(src.slice(i + 1, i + 3))) {
      bytes.push(parseInt(src.slice(i + 1, i + 3), 16));
      i += 2;
    } else {
      bytes.push(...Buffer.from(c, "utf8"));
    }
  }
  return Buffer.from(bytes).toString("utf8");
}

function decodeWords(value) {
  return value.replace(/=\?([^?]+)\?([bBqQ])\?([^?]*)\?=/g, (_m, _charset, enc, data) => {
    if (enc.toUpperCase() === "B") return Buffer.from(data, "base64").toString("utf8");
    return decodeQP(data.replace(/_/g, " "));
  });
}

function parseHeaders(block) {
  const headers = {};
  const unfolded = block.replace(/\r?\n[ \t]+/g, " ");
  for (const line of unfolded.split(/\r?\n/)) {
    const i = line.indexOf(":");
    if (i <= 0) continue;
    const key = line.slice(0, i).trim().toLowerCase();
    const value = line.slice(i + 1).trim();
    headers[key] = headers[key] ? `${headers[key]}, ${value}` : value;
  }
  return headers;
}

function splitMessage(raw) {
  const m = /\r?\n\r?\n/.exec(raw);
  if (!m) return { headers: parseHeaders(raw), body: "" };
  return { headers: parseHeaders(raw.slice(0, m.index)), body: raw.slice(m.index + m[0].length) };
}

function decodeBody(body, headers) {
  const enc = (headers["content-transfer-encoding"] || "").toLowerCase();
  if (enc === "quoted-printable") return decodeQP(body);
  if (enc === "base64") return Buffer.from(body.replace(/\s+/g, ""), "base64").toString("utf8");
  return body;
}

function collectParts(raw, out) {
  const { headers, body } = splitMessage(raw);
  const ctype = headers["content-type"] || "text/plain";
  const boundary = /boundary="?([^";]+)"?/i.exec(ctype);
  if (/^multipart\//i.test(ctype) && boundary) {
    const sep = `--${boundary[1]}`;
    for (const chunk of body.split(sep).slice(1)) {
      if (chunk.startsWith("--")) break;
      collectParts(chunk.replace(/^\r?\n/, ""), out);
    }
    return;
  }
  const text = decodeBody(body, headers);
  if (/^text\/html/i.test(ctype)) out.html = (out.html || "") + text;
  else if (/^text\//i.test(ctype)) out.text = (out.text || "") + text;
}

function extractLinks(...texts) {
  const links = new Set();
  for (const t of texts) {
    if (!t) continue;
    for (const m of t.matchAll(/href\s*=\s*"([^"]+)"/gi)) links.add(m[1].replace(/&amp;/g, "&"));
    for (const m of t.matchAll(/https?:\/\/[^\s"'<>]+/g)) links.add(m[0].replace(/&amp;/g, "&"));
  }
  return [...links];
}

function saveMessage(envelope, raw) {
  const id = `${Date.now()}-${process.pid}-${String(++seq).padStart(4, "0")}`;
  const { headers } = splitMessage(raw);
  const parts = {};
  collectParts(raw, parts);
  const meta = {
    id,
    receivedAt: new Date().toISOString(),
    envelope,
    from: decodeWords(headers.from || ""),
    to: decodeWords(headers.to || ""),
    subject: decodeWords(headers.subject || ""),
    date: headers.date || null,
    text: parts.text ?? null,
    html: parts.html ?? null,
    links: extractLinks(parts.html, parts.text),
  };
  // Grava o .json antes e o .eml por último (com rename atômico): quem observa o .eml
  // sempre encontra o .json pronto.
  writeFileSync(join(DIR, `${id}.json`), JSON.stringify(meta, null, 2));
  writeFileSync(join(DIR, `.${id}.eml.tmp`), raw);
  renameSync(join(DIR, `.${id}.eml.tmp`), join(DIR, `${id}.eml`));
  console.log(
    `[smtp] ${meta.receivedAt} para=${envelope.rcptTo.join(",")} assunto="${meta.subject}" -> ${id}.eml`,
  );
  return id;
}

// ---------------------------------------------------------------------------
// Protocolo SMTP (subconjunto suficiente para GoTrue, Resend SDK local, nodemailer etc.)
// ---------------------------------------------------------------------------
const server = createServer((socket) => {
  socket.setEncoding("utf8");
  let buffer = "";
  let mode = "command"; // command | data | auth-login-user | auth-login-pass
  let envelope = { mailFrom: null, rcptTo: [] };
  let dataLines = [];

  const reply = (line) => socket.write(`${line}\r\n`);
  const reset = () => {
    envelope = { mailFrom: null, rcptTo: [] };
    dataLines = [];
  };

  reply("220 ede-smtp-sink ESMTP pronto");

  const handleCommand = (line) => {
    const [verbRaw, ...rest] = line.split(" ");
    const verb = (verbRaw || "").toUpperCase();
    const arg = rest.join(" ");
    switch (verb) {
      case "EHLO":
        socket.write(
          "250-ede-smtp-sink\r\n250-8BITMIME\r\n250-SMTPUTF8\r\n250-PIPELINING\r\n250-AUTH PLAIN LOGIN\r\n250 SIZE 52428800\r\n",
        );
        break;
      case "HELO":
        reply("250 ede-smtp-sink");
        break;
      case "AUTH":
        if (/^LOGIN\b/i.test(arg) && !arg.split(" ")[1]) {
          mode = "auth-login-user";
          reply("334 VXNlcm5hbWU6");
        } else if (/^LOGIN\b/i.test(arg)) {
          mode = "auth-login-pass";
          reply("334 UGFzc3dvcmQ6");
        } else if (/^PLAIN\b/i.test(arg) && !arg.split(" ")[1]) {
          mode = "auth-plain";
          reply("334 ");
        } else {
          reply("235 2.7.0 Autenticado");
        }
        break;
      case "MAIL":
        reset();
        envelope.mailFrom = (/<([^>]*)>/.exec(arg) || [null, arg])[1];
        reply("250 2.1.0 OK");
        break;
      case "RCPT":
        envelope.rcptTo.push((/<([^>]*)>/.exec(arg) || [null, arg])[1]);
        reply("250 2.1.5 OK");
        break;
      case "DATA":
        if (!envelope.rcptTo.length) {
          reply("503 5.5.1 RCPT primeiro");
          break;
        }
        mode = "data";
        dataLines = [];
        reply("354 Envie a mensagem; termine com <CRLF>.<CRLF>");
        break;
      case "RSET":
        reset();
        reply("250 2.0.0 OK");
        break;
      case "NOOP":
        reply("250 2.0.0 OK");
        break;
      case "VRFY":
        reply("252 2.0.0 Não verificado");
        break;
      case "QUIT":
        reply("221 2.0.0 Até logo");
        socket.end();
        break;
      default:
        reply("502 5.5.2 Comando não suportado");
    }
  };

  socket.on("data", (chunk) => {
    buffer += chunk;
    let idx;
    while ((idx = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, idx).replace(/\r$/, "");
      buffer = buffer.slice(idx + 1);
      if (mode === "data") {
        if (line === ".") {
          const raw = dataLines.join("\r\n") + "\r\n";
          let id = "?";
          try {
            id = saveMessage(envelope, raw);
          } catch (err) {
            console.error("[smtp] erro ao gravar mensagem:", err);
          }
          reply(`250 2.0.0 OK: enfileirado como ${id}`);
          mode = "command";
          reset();
        } else {
          dataLines.push(line.startsWith("..") ? line.slice(1) : line);
        }
      } else if (mode === "auth-login-user") {
        mode = "auth-login-pass";
        reply("334 UGFzc3dvcmQ6");
      } else if (mode === "auth-login-pass" || mode === "auth-plain") {
        mode = "command";
        reply("235 2.7.0 Autenticado");
      } else {
        handleCommand(line);
      }
    }
  });
  socket.on("error", () => socket.destroy());
});

server.listen(PORT, HOST, () => {
  console.log(`[smtp] ouvindo em ${HOST}:${PORT}, gravando em ${DIR}`);
});

for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => {
    server.close();
    process.exit(0);
  });
}
