// Gera site/local/ede-gestao.html: o site em um arquivo só, que abre direto no aparelho (sem o claude.ai).
// Os dados ficam no navegador daquele aparelho (IndexedDB). Uso (na raiz do repositório): node site/local/montar.mjs [pasta-do-site] [arquivo-de-saida]
import fs from 'node:fs';
import path from 'node:path';

const SITE = path.resolve(process.argv[2] || path.join(path.dirname(new URL(import.meta.url).pathname), '..'));
const SEED = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', 'seed');
const ler = (f) => fs.readFileSync(f.startsWith('seed/') ? path.join(SEED, f.slice(5)) : path.join(SITE, f), 'utf8');
const pagina = ler('index.html');
const semente = {
  'config/org': JSON.parse(ler('seed/org.json')),
  'config/rotinas': JSON.parse(ler('seed/rotinas.json')),
  ...Object.fromEntries(Object.entries(JSON.parse(ler('seed/portais.json'))).map(([loja, v]) => ['portais/' + loja, v])),
};
const logo = 'data:image/svg+xml;base64,' + fs.readFileSync(path.join(SITE, 'img/ede-icone-app.svg')).toString('base64');
const corpo = pagina.indexOf('<div id="root">');
if (corpo < 0 || pagina.split('<script>').length !== 2) throw new Error('index.html mudou de forma: confira o gerador');
const cabeca = pagina.slice(0, corpo).replaceAll('img/ede-icone-app.svg', logo);
const resto = pagina.slice(corpo).replaceAll('img/ede-icone-app.svg', logo)
  .replace('<script>', `<script>window.EDE_LOCAL = ${JSON.stringify({ semente }).replace(/</g, '\\u003c')};</script>\n<script>`);
const html = `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<link rel="icon" href="${logo}">
${cabeca}</head>
<body style="margin:0">
${resto}</body>
</html>
`;
const saida = path.resolve(process.argv[3] || path.join(SITE, 'local', 'ede-gestao.html'));
fs.writeFileSync(saida, html);
console.log(`gerado ${path.relative(process.cwd(), saida)} (${Math.round(html.length / 1024)} KB)`);
