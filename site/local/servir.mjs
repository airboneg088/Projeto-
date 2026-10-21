// Abre o site local num endereço (http://localhost:3300) para o navegador de pré-visualização do Claude ou qualquer navegador.
// Gera site/local/ede-gestao.html a partir do index.html e serve esse arquivo. Uso (na raiz do repositório): node site/local/servir.mjs [porta]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const ARQUIVO = path.join(AQUI, 'ede-gestao.html');
const PORTA = Number(process.argv[2] || process.env.PORT || 3300);

execFileSync(process.execPath, [path.join(AQUI, 'montar.mjs')], { stdio: 'inherit' });

http.createServer((req, res) => {
  if (new URL(req.url, 'http://x').pathname !== '/') { res.writeHead(302, { location: '/' }); return res.end(); }
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
  res.end(fs.readFileSync(ARQUIVO));
}).listen(PORTA, () => console.log(`Éde Gestão (local) em http://localhost:${PORTA}`));
