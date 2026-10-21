// Teste ponta a ponta do site (portais, quadro, equipe, foto/vídeo, aprovação, Início e arquivo local) com uma simulação de window.claude.
// Uso (na raiz do repositório): node site/teste/run.mjs [pasta-das-capturas]
// Precisa do ffmpeg (gera os vídeos de teste). CHROME_PATH=/caminho/do/chrome se o Playwright não achar o navegador.
import { chromium } from '@playwright/test';
import os from 'node:os';
import fs from 'node:fs';
import http from 'node:http';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const SITE = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const SEED = path.join(SITE, 'seed');
const MONTAR = path.join(SITE, 'local', 'montar.mjs');
const OUT = process.argv[2] || fs.mkdtempSync(path.join(os.tmpdir(), 'ede-site-capturas-'));
const AQUI = fs.mkdtempSync(path.join(os.tmpdir(), 'ede-site-videos-'));
const ff = (...a) => execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', ...a]);
ff('-i', 'testsrc2=size=320x240:rate=24', '-t', '2', '-c:v', 'libvpx', '-b:v', '300k', path.join(AQUI, 'pequeno.webm'));
ff('-i', 'mandelbrot=size=320x240:rate=24', '-t', '2', '-c:v', 'libvpx', '-b:v', '300k', path.join(AQUI, 'outro.webm'));
ff('-i', 'testsrc2=size=320x240:rate=24', '-t', '40', '-c:v', 'libvpx', '-b:v', '50k', path.join(AQUI, 'longo.webm'));
ff('-i', 'nullsrc=s=1280x720:r=24,geq=random(1)*255:128:128', '-t', '3', '-c:v', 'libvpx', '-b:v', '12M', '-minrate', '12M', '-maxrate', '12M', '-bufsize', '2M', path.join(AQUI, 'grande.webm'));

let semente = 1;
function pngNovo() { // PNG 4x4 com cor diferente a cada chamada (evita o bloqueio de foto repetida)
  semente++; const w = 4, h = 4; const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 3 + 1)] = 0; for (let x = 0; x < w; x++) { const o = y * (w * 3 + 1) + 1 + x * 3; raw[o] = (semente * 37 + x * 50) % 256; raw[o + 1] = (semente * 91 + y * 60) % 256; raw[o + 2] = (semente * 13 + x * y * 20) % 256; } }
  const crcT = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crcT[n] = c >>> 0; }
  const crc = (buf) => { let x = 0xffffffff; for (const b of buf) x = crcT[(x ^ b) & 0xff] ^ (x >>> 8); return (x ^ 0xffffffff) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

const seed = {
  'config/org': JSON.parse(fs.readFileSync(SEED + '/org.json', 'utf8')),
  'config/rotinas': JSON.parse(fs.readFileSync(SEED + '/rotinas.json', 'utf8')),
  ...Object.fromEntries(Object.entries(JSON.parse(fs.readFileSync(SEED + '/portais.json', 'utf8'))).map(([k, v]) => ['portais/' + k, v])),
};
// Histórico de exemplo (28 dias) da Primavera: Ana rápida, Bruno lento; fechamento parado; limpeza nunca aos sábados;
// caixa costuma atrasar; banheiro com problema 3 vezes; mercadorias de cima limpas há 12 dias; estoque organizado há 3 dias.
function historico(loja) {
  const docs = {}; const rot = seed['config/rotinas'].rotinas; const padrao = seed['portais/' + loja].padrao; const ids = Object.keys(seed['portais/' + loja].funcionarios).sort();
  const tz = (d) => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(d);
  const iso = (data, hhmm, add = 0) => new Date(new Date(`${data}T${hhmm}:00-03:00`).getTime() + add * 60000).toISOString();
  const fator = { [ids[0]]: 0.4, [ids[1]]: 1.15, [ids[2]]: 0.7 }; let sem = 7; const rnd = () => { sem = (sem * 9301 + 49297) % 233280; return sem / 233280; };
  for (let k = 28; k >= 1; k--) {
    const data = tz(new Date(Date.now() - k * 864e5)); const w = ((new Date(data + 'T12:00:00-03:00').getUTCDay() + 6) % 7) + 1; const tarefas = {};
    for (const [rid, r] of Object.entries(rot)) {
      const tipo = r.tipo || 'diaria'; if (tipo === 'mensal') continue;
      if (tipo === 'periodica' && !((rid === 'limpeza_alto' && k === 12) || (rid === 'organizar_estoque' && k === 3))) continue;
      const feito = tipo === 'periodica' || (!(rid === 'fechamento' && k <= 4) && !(rid === 'limpeza' && w === 6) && !(rid === 'precificacao' && k % 5 === 0));
      const resp = [].concat(padrao[rid] || []).filter(Boolean);
      const inicio = iso(data, r.inicio || '08:00'), prazo = iso(data, r.fim || '18:00');
      const t = { rotina: rid, titulo: r.titulo, instrucoes: r.instrucoes, setor: r.setor, responsaveis: resp, responsavel: resp[0] || null, inicio, prazo, exigeMidia: true, exigeAprovacao: true, peso: r.peso || 1, itens: r.itens, status: 'pendente', n: 0, tentativas: {} };
      if (feito && resp.length) {
        const quem = resp[0]; const janela = (Date.parse(prazo) - Date.parse(inicio)) / 60000; const ini = iso(data, r.inicio || '08:00', 5);
        let envio = new Date(Date.parse(ini) + Math.round(janela * (fator[quem] || 0.7) * (0.85 + rnd() * 0.3)) * 60000).toISOString();
        if (rid === 'caixa' && k % 3 !== 0) envio = new Date(Date.parse(prazo) + 20 * 60000).toISOString();
        const respostas = Object.fromEntries(Object.keys(r.itens).map((iid) => [iid, { ok: true, obs: '' }]));
        if (rid === 'limpeza' && [2, 5, 9].includes(k)) respostas.i3 = { ok: false, obs: 'Faltou sabonete no banheiro' };
        Object.assign(t, { status: 'aprovada', n: 1, tentativas: { 1: { por: quem, participantes: { [quem]: ini }, inicio: ini, respostas, midias: {}, obs: '', envio, revisao: { decisao: 'aprovada', em: envio } } } });
      }
      tarefas[`r_${rid}`] = t;
    }
    docs[`diarias/${loja}_${data}`] = { loja, data, criadoEm: iso(data, '07:00'), tarefas };
  }
  return docs;
}
const HIST = historico('primavera');
const PIN_HASH = crypto.createHash('sha256').update('primavera:1234').digest('hex');

const mock = `<script>
(() => {
  const qs = new URLSearchParams(location.search);
  const semente = ${JSON.stringify(seed)};
  if (qs.get('pin')) semente['portais/primavera'].pinHash = ${JSON.stringify(PIN_HASH)};
  if (qs.get('padraoLista')) semente['portais/castro'].padrao.abertura = ['f_cas1', 'f_cas2'];
  if (qs.get('hist')) Object.assign(semente, ${JSON.stringify(HIST)});
  const store = new Map(Object.entries(semente).map(([k, v]) => [k, JSON.parse(JSON.stringify(v))]));
  const listeners = new Set();
  const clone = (x) => x === undefined ? undefined : JSON.parse(JSON.stringify(x));
  const merge = (a, b) => { for (const [k, v] of Object.entries(b)) { if (v && typeof v === 'object' && !Array.isArray(v) && a[k] && typeof a[k] === 'object' && !Array.isArray(a[k])) merge(a[k], v); else a[k] = clone(v); } return a; };
  const notify = () => setTimeout(() => listeners.forEach((f) => f()), 5);
  const snap = (p) => { const d = store.get(p); return { id: p.split('/').pop(), exists: d !== undefined, data: () => clone(d), metadata: { fromCache: false, hasPendingWrites: false } }; };
  const tamanho = (d) => new Blob([JSON.stringify(d)]).size;
  function query(col, filters = [], order = null, lim = 1000) {
    const run = () => {
      let docs = [...store.keys()].filter((k) => k.startsWith(col + '/') && k.split('/').length === col.split('/').length + 1).map(snap);
      for (const [f, op, v] of filters) docs = docs.filter((d) => { const x = d.data()[f]; return op === '==' ? x === v : op === '>=' ? x >= v : op === '<=' ? x <= v : op === '!=' ? (x !== undefined && x !== v) : true; });
      if (order) docs.sort((a, b) => (a.data()[order[0]] > b.data()[order[0]] ? 1 : -1) * (order[1] === 'desc' ? -1 : 1));
      docs = docs.slice(0, lim);
      return { docs, size: docs.length, empty: !docs.length, docChanges: () => [], metadata: { fromCache: false, hasPendingWrites: false } };
    };
    return {
      where: (f, op, v) => query(col, [...filters, [f, op, v]], order, lim),
      orderBy: (f, dir = 'asc') => query(col, filters, [f, dir], lim),
      limit: (n) => query(col, filters, order, n),
      get: async () => run(),
      onSnapshot: (next) => { const f = () => next(run()); listeners.add(f); setTimeout(f, 5); return () => listeners.delete(f); },
    };
  }
  window.__escritas = 0;
  const docRef = (p) => ({
    id: p.split('/').pop(), path: p,
    get: async () => snap(p),
    set: async (d) => { if (tamanho(d) > 262144) throw { code: 'invalid_argument', message: 'doc > 256 KiB' }; window.__escritas++; store.set(p, clone(d)); notify(); },
    update: async (d) => { if (!store.has(p)) throw { code: 'invalid_argument', message: 'missing' }; const novo = merge(clone(store.get(p)), d); if (tamanho(novo) > 262144) throw { code: 'invalid_argument', message: 'doc > 256 KiB' }; window.__escritas++; store.set(p, novo); notify(); },
    delete: async () => { store.delete(p); notify(); },
    acquire: async () => ({ acquired: true }),
    onSnapshot: (next) => { const f = () => next(snap(p)); listeners.add(f); setTimeout(f, 5); return () => listeners.delete(f); },
    collection: (c) => db.collection(p + '/' + c),
  });
  const db = { doc: docRef, collection: (c) => Object.assign(query(c), { path: c, doc: (id) => docRef(c + '/' + (id || Math.random().toString(36).slice(2))), add: async (d) => { const r = docRef(c + '/' + Math.random().toString(36).slice(2)); await r.set(d); return r; } }) };
  const dono = qs.get('dono') !== '0';
  const me = { id: dono ? 'u_owner' : 'u_loja', name: dono ? 'Dona Teste' : 'Celular da loja', avatarUrl: '', color: '#000', email: null, isOwner: dono, canEdit: dono };
  const user = { me: async () => me, id: async () => me.id, isOwner: async () => dono, canEdit: async () => dono, can: async () => true, profiles: async () => ({}), search: async () => [] };
  const downloads = { save: async ({ filename, data }) => { window.__download = { filename, text: await data.text() }; } };
  const assets = qs.get('semAssets') ? null : { upload: async (blob, opt = {}) => { const id = Array.from(crypto.getRandomValues(new Uint8Array(16))).map((b) => b.toString(16).padStart(2, '0')).join(''); const tipo = opt.type || blob.type; if (!['image/jpeg', 'image/png', 'video/mp4', 'video/webm'].includes(tipo)) throw { code: 'unsupported_type', message: tipo }; if (blob.size > 20 * 1024 * 1024) throw { code: 'too_large', message: 'grande' }; await fetch('/_blob/' + id, { method: 'PUT', body: blob, headers: { 'content-type': tipo } }); window.__uploads = (window.__uploads || 0) + 1; return { id, url: '/_blob/' + id, sizeBytes: blob.size, contentType: tipo }; }, list: async () => ({ assets: [], usage: {} }), delete: async () => ({ deleted: true }) };
  window.__store = store; window.__notify = notify;
  window.__avisos = []; document.addEventListener('DOMContentLoaded', () => new MutationObserver(() => { const t = document.querySelector('#toast p')?.textContent; if (t) window.__avisos.push(t); }).observe(document.getElementById('toast'), { childList: true }));
  window.claude = { use: async (n) => ({ db, user, downloads, assets }[n] || null) };
})();
</script>`;

const pagina = fs.readFileSync(SITE + '/index.html', 'utf8');
const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>body{margin:0;font:14px system-ui}img{max-width:100%}[hidden]{display:none!important}</style></head><body>${mock}${pagina}</body></html>`;

// Servidor local: a página, as imagens e o "/_blob/" dos arquivos enviados.
const blobs = new Map();
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname.startsWith('/_blob/')) {
    if (req.method === 'PUT') { const partes = []; req.on('data', (c) => partes.push(c)); req.on('end', () => { blobs.set(u.pathname, { tipo: req.headers['content-type'], dados: Buffer.concat(partes) }); res.end('ok'); }); return; }
    const b = blobs.get(u.pathname); if (!b) { res.statusCode = 404; return res.end(); }
    const r = req.headers.range?.match(/bytes=(\d*)-(\d*)/);
    if (r) { const ini = Number(r[1] || 0), fim = r[2] ? Number(r[2]) : b.dados.length - 1; res.writeHead(206, { 'content-type': b.tipo, 'content-range': `bytes ${ini}-${fim}/${b.dados.length}`, 'accept-ranges': 'bytes', 'content-length': fim - ini + 1 }); return res.end(b.dados.subarray(ini, fim + 1)); }
    res.writeHead(200, { 'content-type': b.tipo, 'accept-ranges': 'bytes', 'content-length': b.dados.length }); return res.end(b.dados);
  }
  if (u.pathname.startsWith('/img/')) { const f = path.join(SITE, u.pathname); if (fs.existsSync(f)) { res.writeHead(200, { 'content-type': 'image/svg+xml' }); return res.end(fs.readFileSync(f)); } res.statusCode = 404; return res.end(); }
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); res.end(html);
});
await new Promise((ok) => srv.listen(0, '127.0.0.1', ok));
const BASE = `http://127.0.0.1:${srv.address().port}/`;
if (process.env.SO_SERVIR) { console.log(BASE); await new Promise(() => {}); }

const b = await chromium.launch({ ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}), args: ['--autoplay-policy=no-user-gesture-required'] });
const erros = []; const falhas = [];
const passo = (n) => console.log('✓', n);
const confere = (cond, msg) => { if (cond) passo(msg); else { falhas.push(msg); console.log('✗', msg); } };
const vigia = (p, rot) => { p.on('pageerror', (e) => erros.push(`${rot} pageerror: ${e.message}`)); p.on('console', (m) => { if (m.type() === 'error' && !/favicon/.test(m.text())) erros.push(`${rot} console: ${m.text()}`); }); };
const shot = async (p, n) => { await p.waitForTimeout(350); await p.screenshot({ path: `${OUT}/v4-${n}.png` }); };
const toast = async (p) => (await p.locator('#toast p').textContent({ timeout: 500 }).catch(() => '(sem aviso)'));
const esperaToast = async (p, re, ms = 20000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { const t = await toast(p); if (re.test(t)) return t; await p.waitForTimeout(200); } return await toast(p); };
const overflow = (p) => p.evaluate(() => document.documentElement.scrollWidth - innerWidth);
const tarefa = (p, loja, titulo) => p.evaluate(([loja, titulo]) => { const hj = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date()); const atual = [`diarias/${loja}_${hj}`, `mensais/${loja}_${hj.slice(0, 7)}`]; for (const k of atual) { const d = window.__store.get(k); for (const [id, t] of Object.entries(d?.tarefas || {})) if (t.titulo === titulo) return { ...t, id, doc: k }; } return null; }, [loja, titulo]); // só hoje e o mês atual
const video = (n) => ({ name: n + '.webm', mimeType: 'video/webm', buffer: fs.readFileSync(path.join(AQUI, n + '.webm')) }); // data do arquivo = agora
const equipe = (t) => JSON.stringify(Array.isArray(t?.responsaveis) ? t.responsaveis : t?.responsavel ? [t.responsavel] : []);
async function arrastarMouse(q, card, colAlvo) {
  await card.hover(); await q.mouse.down(); const alvo = await q.locator(`.col[data-col="${colAlvo}"]`).boundingBox(); const a = await card.boundingBox();
  for (let i = 1; i <= 10; i++) await q.mouse.move(a.x + a.width / 2 + ((alvo.x + alvo.width / 2) - (a.x + a.width / 2)) * (i / 10), alvo.y + 80, { steps: 2 });
  await q.waitForTimeout(100);
}
const trocarPessoa = async (p, id) => { await p.keyboard.press('Escape'); await p.click('.chip-top'); await p.click('.menu [data-action="trocarPessoa"]'); await p.click(`.pessoa[data-id="${id}"]`); await p.waitForTimeout(250); };
async function arrastarToque(p, de, colAlvo) { // segura o cartão, leva até a borda (o quadro rola) e solta quando a coluna certa acende
  const cdp = await p.context().newCDPSession(p);
  await de.evaluate((el) => el.scrollIntoView({ block: 'center' })); await p.waitForTimeout(200);
  const a = await de.boundingBox(); const x0 = a.x + a.width / 2, y0 = a.y + a.height / 2;
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x0, y: y0 }] });
  await p.waitForTimeout(450);
  const vw = p.viewportSize().width; const sel = `.col[data-col="${colAlvo}"]`;
  const visivel = async () => { const z = await p.locator(sel).boundingBox(); return z && z.x + 40 < vw && z.x + z.width > 40 ? z : null; };
  let z = await visivel(); const x1 = z ? z.x + Math.min(z.width / 2, (vw - z.x) / 2) : vw - 12; const y1 = Math.min(y0 + 30, p.viewportSize().height - 140);
  for (let i = 1; i <= 10; i++) { await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x0 + ((x1 - x0) * i) / 10, y: y0 + ((y1 - y0) * i) / 10 }] }); await p.waitForTimeout(30); }
  for (let i = 0; i < 80 && !(await p.locator(sel + '.alvo').count()); i++) await p.waitForTimeout(25);
  if (x1 >= vw - 12) { // soltou na borda: volta o dedo para o meio da coluna acesa
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: vw / 2, y: y1 }] }); await p.waitForTimeout(60);
    for (let i = 0; i < 40 && !(await p.locator(sel + '.alvo').count()); i++) { await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: vw / 2 + (i % 2), y: y1 }] }); await p.waitForTimeout(40); }
  }
  if (process.env.DBG) { console.log('DBG', x0, y0, x1, y1, await p.evaluate(([x, y]) => { const e = document.elementFromPoint(x, y); return e?.className + ' / ' + e?.closest('[data-col]')?.dataset.col + ' / alvo=' + document.querySelector('.col.alvo')?.dataset.col + ' scroll=' + document.querySelector('.board').scrollLeft; }, [x1, y1])); await p.screenshot({ path: OUT + '/dbg-' + colAlvo + '.png' }); }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await p.waitForTimeout(400);
}

// ---------------------------------------------------------------------------
// 1) Celular, proprietária, com armazenamento de arquivos
// ---------------------------------------------------------------------------
const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const p = await ctx.newPage(); vigia(p, 'celular');
await p.goto(BASE + '?hist=1');
await p.waitForSelector('.portal', { timeout: 8000 });
confere((await p.locator('.portal').count()) === 3, 'portais: 3 lojas = ' + (await p.locator('.portal h2').allTextContents()).join(' | '));
await p.waitForTimeout(400);
confere(await p.locator('.kpi').count() > 0, 'proprietária vê a visão das 3 lojas');
await shot(p, '01-portais');
await p.click('.portal[data-loja="primavera"]');
await p.waitForSelector('.pessoa');
confere((await p.locator('.pessoa b').allTextContents()).join('|') === 'Ana (exemplo)|Bruno (exemplo)|Carla (exemplo)|Gerência', 'quem está usando: ' + (await p.locator('.pessoa b').allTextContents()).join(', '));
await shot(p, '02-quem');
await p.click('.pessoa[data-id="gerencia"]');
await p.waitForSelector('.alr', { timeout: 8000 });
confere(/Início/.test(await p.locator('h1').first().textContent()), 'gerência abre no Início');
if (await p.locator('[data-action="todosAlertas"]').count()) { await p.click('[data-action="todosAlertas"]'); await p.waitForTimeout(200); }
const alertas = await p.locator('.alr').allInnerTexts(); passo('alertas:\n    ' + alertas.map((a) => a.replace(/\n/g, ' | ')).join('\n    '));
confere(alertas.some((a) => /Faz 12 dias que não fazem “Limpeza das mercadorias de cima”/.test(a) && /a cada 7 dias/.test(a)), 'análise: mercadorias de cima há 12 dias');
confere(alertas.some((a) => /ninguém faz “Fechamento da loja”/.test(a) && /^URGENTE/i.test(a)), 'análise: fechamento parado (urgente)');
confere(alertas.some((a) => /Aos sábados, “Limpeza” quase nunca é feita/.test(a)), 'análise: limpeza falha aos sábados');
confere(alertas.some((a) => /“Banheiro limpo e abastecido \(papel e sabonete\)” teve problema 3 vezes/.test(a) && /Faltou sabonete/.test(a)), 'análise: item com problema repetido');
confere(alertas.some((a) => /“Caixa” costuma ser enviada depois do horário/.test(a)), 'análise: caixa costuma atrasar');
confere(!alertas.some((a) => /Organização geral do estoque/.test(a)), 'análise: estoque organizado há 3 dias não gera alerta');
const hojeDoc = await p.evaluate(() => { for (const [k, d] of window.__store) if (k.startsWith('diarias/primavera_') && d.data === new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date())) return Object.keys(d.tarefas); return []; });
confere(hojeDoc.includes('r_limpeza_alto') && !hojeDoc.includes('r_organizar_estoque'), 'rotina a cada 7 dias: entra hoje só a que passou do prazo');
const selos = await p.locator('.pd').evaluateAll((els) => els.map((e) => e.querySelector('b').textContent + ': ' + [...e.querySelectorAll('.selo')].map((x) => x.textContent).join(', ')));
passo('selos: ' + selos.join(' / '));
confere(selos.some((x) => /^Ana.*Termina rápido/.test(x)) && selos.some((x) => /^Bruno.*Demora para terminar/.test(x)), 'desempenho: Ana termina rápido, Bruno demora');
confere(await p.locator('.dest').count() >= 3, 'destaques da equipe: ' + (await p.locator('.dest').allInnerTexts()).map((x) => x.replace(/\n/g, ' ')).join(' | '));
await shot(p, '03a-inicio');
await p.locator('.pd').first().scrollIntoViewIfNeeded(); await shot(p, '03b-inicio-equipe');
await p.click('[data-action="periodoEq"][data-p="30"]'); await p.waitForTimeout(300);
confere(/Aprovadas em 30 dias/.test(await p.locator('.pd').first().textContent()), 'desempenho em 30 dias');
await p.click('[data-action="novaCom"]'); await p.waitForSelector('form[data-action="criar"]');
confere(/^Resolver: Banheiro/.test(await p.inputValue('input[name="titulo"]')), 'criar tarefa a partir do alerta: ' + await p.inputValue('input[name="titulo"]'));
await p.click('.nav [data-tela="inicio"]'); await p.waitForSelector('.alr');
// tira a tarefa de hoje e põe de novo pelo alerta
await p.evaluate(() => { for (const [k, d] of window.__store) if (k.startsWith('diarias/primavera_') && d.tarefas.r_limpeza_alto) { if (d.data === new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date())) delete d.tarefas.r_limpeza_alto; } window.__notify(); });
await p.waitForTimeout(300);
await p.locator('.alr', { hasText: 'Limpeza das mercadorias de cima' }).locator('[data-action="porHoje"]').click(); await p.waitForTimeout(400);
confere(/está no quadro de hoje/.test(await p.evaluate(() => window.__avisos.at(-1))), 'pôr no quadro de hoje: ' + await p.evaluate(() => window.__avisos.at(-1)));
await p.click('.nav [data-tela="quadro"]'); await p.waitForSelector('.board');
const colunas = await p.locator('.col .ch b').allTextContents();
confere(colunas.length === 4, 'quadro: colunas = ' + colunas.join(' | '));
const porCol = await p.evaluate(() => [...document.querySelectorAll('.col')].map((c) => c.dataset.col + ':' + c.querySelectorAll('[data-kcard]').length).join(' '));
passo('cartões por coluna (diárias de hoje): ' + porCol);
await shot(p, '03-quadro');
// nova tarefa avulsa sem responsável
await p.click('[data-tela="nova"]'); await p.waitForSelector('form[data-action="criar"]');
await p.click('form[data-action="criar"] button[type="submit"]');
confere(/Escreva/.test(await p.locator('#erroNova').textContent()), 'nova tarefa sem título: ' + await p.locator('#erroNova').textContent());
await p.fill('input[name="titulo"]', 'Montar ilha de panelas na entrada');
await p.fill('textarea[name="itens"]', 'Ilha montada no lugar combinado\nPreços colocados');
await shot(p, '04-nova');
await p.click('form[data-action="criar"] button[type="submit"]'); await p.waitForTimeout(400);
confere(/criada/.test(await toast(p)), 'avulsa criada: ' + await toast(p));
const card = p.locator('.col[data-col=""] [data-kcard]', { hasText: 'Montar ilha' });
confere(await card.count() === 1, 'avulsa está em A distribuir');
// arrastar com o dedo (segurar e arrastar) para a Ana
await p.click('[data-action="fecharDica"]').catch(() => {});
await arrastarToque(p, card, 'f_pri1');
let t = await tarefa(p, 'primavera', 'Montar ilha de panelas na entrada');
confere(equipe(t) === '["f_pri1"]', 'arrastar com o dedo: equipe = ' + equipe(t) + ' | aviso: ' + await toast(p));
await shot(p, '05-quadro-arrastado');
// tocar no cartão e montar uma equipe: Ana + Bruno
await p.locator('[data-kcard]', { hasText: 'Montar ilha' }).first().click(); await p.waitForSelector('#sheet .folha');
await p.click('#sheet [data-action="alternarResp"][data-id="f_pri2"]'); await p.waitForTimeout(300);
t = await tarefa(p, 'primavera', 'Montar ilha de panelas na entrada');
confere(equipe(t) === '["f_pri1","f_pri2"]', 'equipe pelo cartão (Ana + Bruno): ' + equipe(t) + ' | ' + await toast(p));
confere(await p.locator('#sheet [data-action="alternarResp"][aria-pressed="true"]').count() === 2, 'dois chips marcados');
await shot(p, '06-folha-gerencia');
await p.click('#sheet .voltar');
confere(await p.locator('[data-kcard]', { hasText: 'Montar ilha' }).count() === 2, 'cartão aparece na coluna da Ana e na do Bruno');
confere(/Com Bruno/.test(await p.locator('.col[data-col="f_pri1"] [data-kcard]', { hasText: 'Montar ilha' }).textContent()), 'cartão da Ana mostra "Com Bruno"');
// arrastar para quem já está na equipe não duplica
await p.click('.irpara [data-col-id="f_pri1"]'); await p.waitForTimeout(600);
await arrastarToque(p, p.locator('.col[data-col="f_pri1"] [data-kcard]', { hasText: 'Montar ilha' }), 'f_pri2');
passo('equipe depois de arrastar para o Bruno: ' + equipe(await tarefa(p, 'primavera', 'Montar ilha de panelas na entrada')));
const ultimoAviso = await p.evaluate(() => window.__avisos.at(-1));
confere(/já está nesta tarefa/.test(ultimoAviso), 'arrastar para quem já está: ' + ultimoAviso);
// rotina: tornar padrão com duas pessoas
await p.locator('[data-kcard]', { hasText: 'Precificação' }).first().click(); await p.waitForSelector('#sheet .folha');
await p.click('#sheet [data-action="alternarResp"][data-id="f_pri3"]'); await p.waitForTimeout(300);
await p.click('#sheet [data-action="tornarPadrao"]'); await p.waitForTimeout(300);
confere(JSON.stringify(await p.evaluate(() => window.__store.get('portais/primavera').padrao.precificacao)) === '["f_pri1","f_pri3"]', 'tornar padrão: precificação → Ana e Carla');
confere(/já fazem esta rotina/.test(await p.locator('#sheet .quem').textContent()), 'folha diz que já fazem por padrão');
// tirar a Ana: Carla continua
await p.click('#sheet [data-action="alternarResp"][data-id="f_pri1"]'); await p.waitForTimeout(300);
confere(equipe(await tarefa(p, 'primavera', 'Precificação')) === '["f_pri3"]', 'tirar uma pessoa da equipe: ' + equipe(await tarefa(p, 'primavera', 'Precificação')));
await p.click('#sheet .voltar');
// nova tarefa já com duas pessoas
await p.click('[data-tela="nova"]'); await p.waitForSelector('form[data-action="criar"]');
await p.fill('input[name="titulo"]', 'Limpar a vitrine externa');
await p.click('form[data-action="criar"] label.chip:has(input[name="resp"][value="f_pri1"])'); await p.click('form[data-action="criar"] label.chip:has(input[name="resp"][value="f_pri3"])');
await shot(p, '04b-nova-equipe');
await p.click('form[data-action="criar"] button[type="submit"]'); await p.waitForTimeout(400);
confere(equipe(await tarefa(p, 'primavera', 'Limpar a vitrine externa')) === '["f_pri1","f_pri3"]', 'nova tarefa com Ana e Carla');
// do mês
await p.click('.seg [data-e="mes"]'); await p.waitForTimeout(300);
const mensais = [...new Set(await p.locator('[data-kcard] .kt').allTextContents())];
confere(mensais.length === 4, 'do mês: ' + mensais.join(' | '));
const prazosMes = await p.evaluate(() => { const o = {}; for (const [k, d] of window.__store) if (k.startsWith('mensais/primavera_')) for (const t of Object.values(d.tarefas)) o[t.titulo] = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date(t.prazo)); return o; });
passo('prazos do mês: ' + JSON.stringify(prazosMes));
await p.click('.irpara [data-col-id="f_pri3"]'); await p.waitForTimeout(700);
const carlaX = await p.locator('.col[data-col="f_pri3"]').boundingBox();
confere(carlaX && carlaX.x >= 0 && carlaX.x + carlaX.width <= 390, 'atalho de coluna mostra a coluna da Carla inteira (x=' + Math.round(carlaX?.x) + ')');
await shot(p, '07-quadro-mes');
// equipe
await p.click('.nav [data-tela="equipe"]'); await p.waitForSelector('form[data-action="addFunc"]');
await p.fill('form[data-action="addFunc"] input[name="nome"]', 'Joana (exemplo)'); await p.click('form[data-action="addFunc"] button[type="submit"]'); await p.waitForTimeout(300);
confere(/cadastrado/.test(await toast(p)), 'cadastrar funcionário: ' + await toast(p));
await p.fill('input[name="novoPin"]', '12'); await p.click('form[data-action="salvarPin"] button[type="submit"]'); await p.waitForTimeout(200);
confere(/4 a 8/.test(await p.locator('#erroPinCfg').textContent()), 'PIN curto recusado');
await shot(p, '08-equipe');
// rotinas: padrão com várias pessoas
await p.click('.nav [data-tela="mais"]'); await p.click('main [data-tela="rotinas"]'); await p.waitForTimeout(300);
await p.click('[data-action="padraoAlt"][data-rot="abertura"][data-id="f_pri2"]'); await p.waitForTimeout(300);
confere(JSON.stringify(await p.evaluate(() => window.__store.get('portais/primavera').padrao.abertura)) === '["f_pri1","f_pri2"]', 'rotina com padrão Ana e Bruno');
confere(/há 12 dias/.test(await p.locator('.cartao', { hasText: 'Limpeza das mercadorias de cima' }).textContent()), 'rotinas mostram a última vez (há 12 dias)');
await shot(p, '17-rotinas');
// equipe Ana + Bruno: Ana começa, Bruno ajuda, um envio só
await trocarPessoa(p, 'f_pri1');
confere(/Olá, Ana/.test(await p.locator('h1').first().textContent()), 'tela da Ana: ' + await p.locator('h1').first().textContent());
confere(/Com Bruno/.test(await p.locator('.lt', { hasText: 'Montar ilha' }).textContent()), 'Ana vê que a tarefa é com o Bruno');
await shot(p, '09-ana-hoje');
await p.locator('.lt', { hasText: 'Montar ilha' }).click(); await p.waitForSelector('#sheet [data-action="comecar"]');
await p.click('#sheet [data-action="comecar"]'); await p.waitForSelector('#sheet [data-action="enviar"]');
await p.click('#sheet [data-action="enviar"]'); await p.waitForTimeout(300);
confere(/Marque/.test(await toast(p)), 'enviar incompleto: ' + await toast(p));
await p.locator('#sheet .op.feito').first().click(); await p.waitForTimeout(200);
await p.locator('#sheet input[data-action="foto"]').setInputFiles({ name: 'f.png', mimeType: 'image/png', buffer: pngNovo() });
confere(/Foto enviada/.test(await esperaToast(p, /Foto enviada|Não|grande/)), 'Ana manda foto: ' + await toast(p));
await trocarPessoa(p, 'f_pri2');
confere(/Ana já começou/.test(await p.locator('.lt', { hasText: 'Montar ilha' }).textContent()), 'Bruno vê que a Ana já começou');
await p.locator('.lt', { hasText: 'Montar ilha' }).click(); await p.waitForSelector('#sheet [data-action="ajudar"]');
await shot(p, '09b-bruno-ajudar');
await p.click('#sheet [data-action="ajudar"]'); await p.waitForSelector('#sheet [data-action="enviar"]');
confere(await p.locator('#sheet .op.feito[aria-pressed="true"]').count() === 1, 'Bruno vê o item que a Ana marcou');
await p.locator('#sheet .op.feito[aria-pressed="false"]').first().click(); await p.waitForTimeout(200);
await p.locator('#sheet input[data-action="video"]').setInputFiles(video('pequeno'));
confere(/Vídeo enviado/.test(await esperaToast(p, /Vídeo enviado|Não|grande|Grave/)), 'Bruno manda vídeo (arquivo do site): ' + await toast(p));
await p.waitForTimeout(400);
confere(await p.locator('#sheet .midias .mid').count() === 2, 'foto da Ana e vídeo do Bruno no mesmo envio');
await shot(p, '10-ana-execucao');
await p.locator('#sheet .midias .x').first().click(); await p.waitForTimeout(400);
confere(await p.locator('#sheet .midias .mid').count() === 1, 'remover mídia: sobra 1 | ' + await toast(p));
await p.locator('#sheet input[data-action="video"]').setInputFiles(video('pequeno'));
confere(/já foi enviada/.test(await esperaToast(p, /já foi|enviado/)), 'vídeo repetido bloqueado: ' + await toast(p));
await p.click('#sheet [data-action="enviar"]'); await p.waitForTimeout(400);
confere(/Enviada/.test(await toast(p)), 'Bruno envia pela equipe: ' + await toast(p));
t = await tarefa(p, 'primavera', 'Montar ilha de panelas na entrada');
confere(t.n === 1 && t.tentativas[1].por === 'f_pri1' && t.tentativas[1].participantes?.f_pri2, 'um envio só, com Ana e Bruno');
// gerência aprova / pede correção
await trocarPessoa(p, 'gerencia');
await p.click('.nav [data-tela="aprovar"]'); await p.waitForTimeout(500);
confere((await p.locator('.galeria .mid').count()) === 1, 'aprovar: 1 mídia na galeria');
confere(/Ana \(exemplo\) e Bruno \(exemplo\)/.test(await p.locator('main article p.soft').first().textContent()), 'aprovar mostra a equipe: ' + await p.locator('main article p.soft').first().textContent());
await shot(p, '11-aprovar');
await p.locator('.galeria [data-action="ver"]').click(); await p.waitForSelector('#modal video', { timeout: 5000 });
const pronto = await p.waitForFunction(() => document.querySelector('#modal video')?.readyState >= 2, null, { timeout: 8000 }).then(() => true).catch(() => false);
confere(pronto, 'vídeo abre no player');
await shot(p, '12-player');
await p.click('#modal [data-action="fecharModal"].btn');
await p.click('.acao [data-action="reprovar"]'); await p.click('form.dlg button[type="submit"]');
confere(/Escreva/.test(await p.locator('#erroDlg').textContent()), 'correção sem motivo recusada');
await p.fill('#motivo', 'Grave mostrando os preços de perto'); await p.click('form.dlg button[type="submit"]'); await p.waitForTimeout(300);
confere(/Correção pedida/.test(await toast(p)), 'correção: ' + await toast(p));
await trocarPessoa(p, 'f_pri1');
confere(/Corrigir: Grave/.test(await p.locator('.lt', { hasText: 'Montar ilha' }).textContent()), 'Ana vê o motivo');
await p.locator('.lt', { hasText: 'Montar ilha' }).click(); await p.click('#sheet [data-action="comecar"]'); await p.waitForSelector('#sheet [data-action="enviar"]');
for (const b2 of await p.locator('#sheet .op.feito').all()) { await b2.click(); await p.waitForTimeout(150); }
await p.locator('#sheet input[data-action="video"]').setInputFiles(video('outro'));
await esperaToast(p, /Vídeo enviado|Não|Grave/);
await p.click('#sheet [data-action="enviar"]'); await p.waitForTimeout(400);
await trocarPessoa(p, 'gerencia');
await p.click('.nav [data-tela="aprovar"]'); await p.waitForTimeout(400);
await p.click('.acao [data-action="aprovar"]'); await p.waitForTimeout(400);
confere(/Aprovada/.test(await toast(p)), 'aprovação: ' + await toast(p));
t = await tarefa(p, 'primavera', 'Montar ilha de panelas na entrada');
confere(t.status === 'aprovada' && t.n === 2 && t.tentativas[1].revisao.decisao === 'reprovada', 'histórico: envio 1 reprovado, envio 2 aprovado');
await shot(p, '13-aprovar-vazio');
// tarefa do mês com item com problema
await trocarPessoa(p, 'f_pri1');
await p.click('.seg [data-e="mes"]'); await p.waitForTimeout(200);
await shot(p, '14-ana-mes');
await p.locator('.lt', { hasText: 'Troca da vitrine' }).click(); await p.click('#sheet [data-action="comecar"]'); await p.waitForSelector('#sheet [data-action="enviar"]');
const feitos = await p.locator('#sheet .op.feito').all(); for (let i = 0; i < feitos.length - 1; i++) { await feitos[i].click(); await p.waitForTimeout(120); }
await p.locator('#sheet .op.prob').last().click(); await p.waitForTimeout(200);
await p.locator('#sheet input[data-action="foto"]').setInputFiles({ name: 'f.png', mimeType: 'image/png', buffer: pngNovo() }); await esperaToast(p, /Foto enviada|Não/);
await p.click('#sheet [data-action="enviar"]'); await p.waitForTimeout(300);
confere(/Escreva o que está errado/.test(await toast(p)), 'problema sem explicação: ' + await toast(p));
await p.locator('#sheet textarea[data-action="obsitem"]').fill('Vidro com risco no canto, avisei a gerente');
await p.locator('#sheet .cab h2').click(); await p.waitForTimeout(300);
await p.click('#sheet [data-action="enviar"]'); await p.waitForTimeout(400);
confere(/Enviada/.test(await toast(p)), 'envio do mês: ' + await toast(p));
await trocarPessoa(p, 'gerencia');
await p.click('.nav [data-tela="aprovar"]'); await p.waitForTimeout(400);
confere(/1 item com problema/.test(await p.locator('.box-prob').textContent()), 'gerência vê o item com problema');
await shot(p, '15-aprovar-mes');
await p.click('.nav [data-tela="mais"]'); await p.click('[data-tela="painel"]'); await p.waitForTimeout(400);
passo('painel: ' + (await p.locator('.kpi').allInnerTexts()).slice(0, 4).map((s) => s.replace(/\n/g, ' ')).join(' / '));
await shot(p, '16-painel');
await p.click('[data-action="csv"]'); await p.waitForTimeout(300);
confere(/ede-gestao/.test(await p.evaluate(() => window.__download?.filename || '')), 'CSV baixado');
await p.click('[data-action="ajuda"]').catch(() => {});
confere(await overflow(p) <= 0, 'celular sem rolagem lateral: ' + await overflow(p));
passo('arquivos enviados ao armazenamento: ' + await p.evaluate(() => window.__uploads));
await ctx.close();

// ---------------------------------------------------------------------------
// 2) Computador, aparelho da loja (não é a proprietária), sem armazenamento de arquivos, PIN
// ---------------------------------------------------------------------------
const ctx2 = await b.newContext({ viewport: { width: 1440, height: 900 } });
const q = await ctx2.newPage(); vigia(q, 'computador');
await q.goto(BASE + '?dono=0&semAssets=1&pin=1');
await q.waitForSelector('.portal');
confere(await q.locator('.kpi').count() === 0, 'aparelho da loja não vê a visão das 3 lojas');
await q.click('.portal[data-loja="primavera"]'); await q.click('.pessoa[data-id="gerencia"]');
await q.waitForSelector('#pinEntrada');
await q.fill('#pinEntrada', '9999'); await q.click('form[data-action="pin"] button[type="submit"]'); await q.waitForTimeout(200);
confere(/PIN errado/.test(await q.locator('#erroPin').textContent()), 'PIN errado recusado');
await shot(q, '18-pin');
await q.fill('#pinEntrada', '1234'); await q.click('form[data-action="pin"] button[type="submit"]');
await q.waitForSelector('.nav'); await q.click('.nav [data-tela="quadro"]'); await q.waitForSelector('.board');
await shot(q, '19-quadro-desktop');
// dados antigos (só "responsavel", envio sem participantes) continuam funcionando
await q.evaluate(() => { for (const [k, d] of window.__store) if (k.startsWith('diarias/primavera_')) for (const t of Object.values(d.tarefas)) { delete t.responsaveis; if (t.titulo === 'Reposição') { t.status = 'andamento'; t.n = 1; t.tentativas = { 1: { por: 'f_pri2', inicio: new Date().toISOString(), respostas: {}, midias: {}, obs: '' } }; } } window.__notify(); });
await q.waitForTimeout(300);
const porColLegado = await q.evaluate(() => [...document.querySelectorAll('.col')].map((c) => c.dataset.col + ':' + c.querySelectorAll('[data-kcard]').length).join(' '));
confere(/f_pri1:[1-9]/.test(porColLegado) && /f_pri2:[1-9]/.test(porColLegado), 'dados antigos aparecem nas colunas: ' + porColLegado);
// arrastar com o mouse para outra pessoa: escolhe "fazem juntos"
const c2 = q.locator('.col[data-col="f_pri1"] [data-kcard]').first(); const tit = await c2.locator('.kt').textContent();
await arrastarMouse(q, c2, 'f_pri2'); await shot(q, '20-arrastando'); await q.mouse.up(); await q.waitForTimeout(300);
confere(await q.locator('#modal [data-action="moverJuntos"]').count() === 1, 'soltar em outra pessoa pergunta: juntos ou trocar');
await shot(q, '20b-juntos-ou-trocar');
await q.click('#modal [data-action="moverJuntos"]'); await q.waitForTimeout(300);
t = await tarefa(q, 'primavera', tit);
confere(equipe(t) === '["f_pri1","f_pri2"]', `arrastar e "fazem juntos": "${tit}" → ${equipe(t)}`);
confere(await q.locator('#sheet .folha').count() === 0, 'soltar não abre a tarefa');
// tirar a Ana arrastando o cartão dela para A distribuir: Bruno continua
await arrastarMouse(q, q.locator('.col[data-col="f_pri1"] [data-kcard]', { hasText: tit }), ''); await q.mouse.up(); await q.waitForTimeout(300);
confere(equipe(await tarefa(q, 'primavera', tit)) === '["f_pri2"]', 'arrastar para A distribuir tira só aquela pessoa: ' + await toast(q));
// trocar: outra tarefa da Ana vai para a Carla
const c3 = q.locator('.col[data-col="f_pri1"] [data-kcard]').first(); const tit3 = await c3.locator('.kt').textContent();
await arrastarMouse(q, c3, 'f_pri3'); await q.mouse.up(); await q.waitForTimeout(300);
await q.click('#modal [data-action="moverTrocar"]'); await q.waitForTimeout(300);
confere(equipe(await tarefa(q, 'primavera', tit3)) === '["f_pri3"]', `arrastar e "trocar": "${tit3}" → Carla`);
// Bruno: vídeo grande sem armazenamento → reduz e guarda em partes
await trocarPessoa(q, 'f_pri2');
await q.locator('.lt', { hasText: 'Reposição' }).click(); await q.waitForTimeout(300);
confere(await q.locator('#sheet [data-action="enviar"]').count() === 1, 'envio antigo do Bruno continua editável');
await q.click('#sheet .voltar');
await q.click('.seg [data-e="mes"]'); await q.waitForTimeout(200);
await q.locator('.lt', { hasText: 'Limpeza pesada' }).click(); await q.click('#sheet [data-action="comecar"]'); await q.waitForSelector('#sheet [data-action="enviar"]');
await q.locator('#sheet input[data-action="video"]').setInputFiles(video('longo'));
confere(/até 30 segundos/.test(await esperaToast(q, /segundos|enviado|Não/)), 'vídeo longo recusado: ' + await toast(q));
await q.locator('#sheet input[data-action="video"]').setInputFiles(video('grande'));
await q.waitForTimeout(600); await shot(q, '21-preparando-video');
const tv = await esperaToast(q, /Vídeo enviado|Não|grande|celular/, 40000);
confere(/Vídeo enviado/.test(tv), 'vídeo grande reduzido e enviado em partes: ' + tv);
const partes = await q.evaluate(() => { const m = [...window.__store.entries()].find(([k, d]) => k.startsWith('midias/') && k.split('/').length === 2 && d.tipo === 'video'); return m ? { partes: m[1].partes, mime: m[1].mime, docs: [...window.__store.keys()].filter((k) => k.startsWith(m[0] + '/partes/')).length } : null; });
passo('partes do vídeo: ' + JSON.stringify(partes));
await q.locator('#sheet .midias [data-action="ver"]').click(); await q.waitForSelector('#modal video', { timeout: 8000 });
const pronto2 = await q.waitForFunction(() => document.querySelector('#modal video')?.readyState >= 1, null, { timeout: 8000 }).then(() => true).catch(() => false);
confere(pronto2, 'vídeo em partes abre no player');
await q.click('#modal [data-action="fecharModal"].btn');
await shot(q, '22-bruno-execucao-desktop');
confere(await overflow(q) <= 0, 'computador sem rolagem lateral');
await ctx2.close();

// ---------------------------------------------------------------------------
// 3) Celular no tema escuro
// ---------------------------------------------------------------------------
const ctx3 = await b.newContext({ viewport: { width: 390, height: 844 }, colorScheme: 'dark', isMobile: true, hasTouch: true, deviceScaleFactor: 2 });
const r = await ctx3.newPage(); vigia(r, 'escuro');
await r.goto(BASE + '?padraoLista=1'); await r.waitForSelector('.portal'); await r.click('.portal[data-loja="castro"]'); await r.click('.pessoa[data-id="gerencia"]'); await r.waitForSelector('.nav'); await r.click('.nav [data-tela="quadro"]'); await r.waitForSelector('.board');
confere(await r.locator('[data-kcard]', { hasText: 'Abertura da loja' }).count() === 2, 'rotina com padrão de duas pessoas nasce nas duas colunas');
await shot(r, '23-escuro-quadro');
await ctx3.close();

// ---------------------------------------------------------------------------
// 4) Arquivo local (sem o claude.ai): dados no aparelho, cópia e restauração
// ---------------------------------------------------------------------------
const ARQ = path.join(OUT, 'ede-gestao-local.html');
execFileSync('node', [MONTAR, SITE, ARQ]);
const ctx4 = await b.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2, acceptDownloads: true });
const l = await ctx4.newPage(); vigia(l, 'local'); l.on('dialog', (d) => d.accept());
await l.goto('file://' + ARQ); await l.waitForSelector('.portal', { timeout: 8000 });
confere(await l.locator('.aviso-local').count() === 1, 'arquivo local abre e avisa que os dados ficam no aparelho');
await shot(l, '24-local-portais');
await l.click('.portal[data-loja="primavera"]'); await l.click('.pessoa[data-id="gerencia"]'); await l.waitForSelector('.nav');
await l.waitForSelector('.alr, .vazio', { timeout: 8000 });
confere(/Início/.test(await l.locator('h1').first().textContent()), 'local: Início abre');
await l.click('.nav [data-tela="quadro"]'); await l.click('[data-tela="nova"]'); await l.fill('input[name="titulo"]', 'Teste do arquivo local');
await l.click('form[data-action="criar"] button[type="submit"]'); await l.waitForTimeout(400);
await l.reload(); await l.waitForSelector('.nav'); await l.click('.nav [data-tela="quadro"]'); await l.waitForTimeout(300);
confere(await l.locator('[data-kcard]', { hasText: 'Teste do arquivo local' }).count() === 1, 'local: tarefa continua depois de recarregar');
// funcionária no arquivo local: foto e envio
await l.keyboard.press('Escape'); await l.click('.chip-top'); await l.click('.menu [data-action="trocarPessoa"]'); await l.click('.pessoa[data-id="f_pri1"]');
await l.locator('.lt', { hasText: 'Teste do arquivo local' }).click(); await l.click('#sheet [data-action="comecar"]'); await l.waitForSelector('#sheet [data-action="enviar"]');
const fotoLocal = pngNovo();
await l.locator('#sheet input[data-action="foto"]').setInputFiles({ name: 'f.png', mimeType: 'image/png', buffer: fotoLocal }); await l.waitForTimeout(1200);
await l.locator('#sheet input[data-action="foto"]').setInputFiles({ name: 'f.png', mimeType: 'image/png', buffer: fotoLocal }); await l.waitForTimeout(1200);
confere(/já foi enviada/.test(await l.evaluate(() => document.querySelector('#toast p')?.textContent || '')), 'local: foto repetida bloqueada');
await l.click('#sheet [data-action="enviar"]'); await l.waitForTimeout(500);
await l.keyboard.press('Escape'); await l.click('.chip-top'); await l.click('.menu [data-action="trocarPessoa"]'); await l.click('.pessoa[data-id="gerencia"]');
await l.click('.nav [data-tela="aprovar"]'); await l.waitForTimeout(500);
confere(await l.locator('.galeria .mid img').count() === 1, 'local: gerência vê a foto para aprovar');
// cópia e restauração
await l.click('.nav [data-tela="mais"]');
const [dl] = await Promise.all([l.waitForEvent('download'), l.click('[data-action="exportarLocal"]')]);
const COPIA = path.join(OUT, 'copia-local.json'); await dl.saveAs(COPIA);
const copia = JSON.parse(fs.readFileSync(COPIA, 'utf8'));
confere(copia.app === 'ede-gestao' && Object.keys(copia.docs).some((k) => k.startsWith('midias/')), 'local: cópia salva com as tarefas e a foto (' + Object.keys(copia.docs).length + ' registros)');
await l.click('.nav [data-tela="quadro"]'); await l.click('[data-tela="nova"]'); await l.fill('input[name="titulo"]', 'Depois da cópia');
await l.click('form[data-action="criar"] button[type="submit"]'); await l.waitForTimeout(400);
await l.click('.nav [data-tela="mais"]');
await Promise.all([l.waitForEvent('load'), l.locator('input[data-action="importarLocal"]').setInputFiles(COPIA)]);
await l.waitForSelector('.nav'); await l.click('.nav [data-tela="quadro"]'); await l.waitForTimeout(400);
confere(await l.locator('[data-kcard]', { hasText: 'Depois da cópia' }).count() === 0 && await l.locator('[data-kcard]', { hasText: 'Teste do arquivo local' }).count() === 1, 'local: restaurar a cópia volta os dados');
await shot(l, '25-local-quadro');
await ctx4.close();

await b.close(); srv.close();
console.log(erros.length ? 'ERROS:\n' + erros.join('\n') : 'sem erros de página');
console.log(falhas.length ? `FALHAS (${falhas.length}):\n` + falhas.join('\n') : 'todas as verificações passaram');
console.log('capturas em ' + OUT);
process.exit(falhas.length || erros.length ? 1 : 0);
