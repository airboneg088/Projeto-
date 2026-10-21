// Teste ponta a ponta do site com uma simulação local de window.claude (db + user + downloads).
// Uso (na raiz do repositório): node site/teste/run.mjs   (CHROME_PATH=/caminho/do/chrome se precisar)
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import zlib from 'node:zlib';
let semente = 1;
function pngNovo() { // PNG 4x4 com cor diferente a cada chamada (evita o bloqueio de foto repetida)
  semente++; const w = 4, h = 4; const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 3 + 1)] = 0; for (let x = 0; x < w; x++) { const o = y * (w * 3 + 1) + 1 + x * 3; raw[o] = (semente * 37 + x * 50) % 256; raw[o + 1] = (semente * 91 + y * 60) % 256; raw[o + 2] = (semente * 13 + x * y * 20) % 256; } }
  const crc = (buf) => { let c, crcT = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crcT[n] = c >>> 0; } let x = 0xffffffff; for (const b of buf) x = crcT[(x ^ b) & 0xff] ^ (x >>> 8); return (x ^ 0xffffffff) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
async function fotosPendentes(p) { // tira foto em todo item que ainda pede
  for (let i = 0; i < 8; i++) {
    const alvo = p.locator('#sheet .foto-btn:not(.ok) input[type="file"]');
    if (!(await alvo.count())) break;
    const lbl = await alvo.first().evaluate((el) => el.closest('.item')?.querySelector('.tags .obr') ? 1 : 0);
    if (!lbl) break;
    await alvo.first().setInputFiles({ name: 'f.png', mimeType: 'image/png', buffer: pngNovo() }); await p.waitForTimeout(900);
  }
}



const SITE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'ede-site-'));
const page0 = fs.readFileSync(SITE + '/index.html', 'utf8');
const seed = JSON.stringify({
  'config/org': JSON.parse(fs.readFileSync(SITE + '/seed/org.json', 'utf8')),
  'config/rotinas': JSON.parse(fs.readFileSync(SITE + '/seed/rotinas.json', 'utf8')),
  'config/pessoas': JSON.parse(fs.readFileSync(SITE + '/seed/pessoas.json', 'utf8')),
});
const mock = `<script>
(() => {
  const store = new Map(Object.entries(${seed}).map(([k, v]) => [k, JSON.parse(JSON.stringify(v))]));
  const listeners = new Set();
  const clone = (x) => x === undefined ? undefined : JSON.parse(JSON.stringify(x));
  const merge = (a, b) => { for (const [k, v] of Object.entries(b)) { if (v && typeof v === 'object' && !Array.isArray(v) && a[k] && typeof a[k] === 'object' && !Array.isArray(a[k])) merge(a[k], v); else a[k] = clone(v); } return a; };
  const notify = () => setTimeout(() => listeners.forEach((f) => f()), 5);
  const snap = (path) => { const d = store.get(path); return { id: path.split('/').pop(), exists: d !== undefined, data: () => clone(d), metadata: { fromCache: false, hasPendingWrites: false } }; };
  function query(col, filters = [], order = null, lim = 1000) {
    const q = {
      where: (f, op, v) => query(col, [...filters, [f, op, v]], order, lim),
      orderBy: (f, dir = 'asc') => query(col, filters, [f, dir], lim),
      limit: (n) => query(col, filters, order, n),
      get: async () => run(),
      onSnapshot: (next) => { const f = () => next(run()); listeners.add(f); setTimeout(f, 5); return () => listeners.delete(f); },
    };
    function run() {
      let docs = [...store.keys()].filter((k) => k.startsWith(col + '/') && k.split('/').length === col.split('/').length + 1).map(snap);
      for (const [f, op, v] of filters) docs = docs.filter((d) => { const x = d.data()[f]; return op === '==' ? x === v : op === '>=' ? x >= v : op === '<=' ? x <= v : true; });
      if (order) docs.sort((a, b) => (a.data()[order[0]] > b.data()[order[0]] ? 1 : -1) * (order[1] === 'desc' ? -1 : 1));
      docs = docs.slice(0, lim);
      return { docs, size: docs.length, empty: !docs.length, docChanges: () => [], metadata: { fromCache: false, hasPendingWrites: false } };
    }
    return q;
  }
  const docRef = (path) => ({
    id: path.split('/').pop(), path,
    get: async () => snap(path),
    set: async (d) => { store.set(path, clone(d)); notify(); },
    update: async (d) => { if (!store.has(path)) throw { code: 'invalid_argument', message: 'missing' }; merge(store.get(path), d); notify(); },
    delete: async () => { store.delete(path); notify(); },
    acquire: async () => ({ acquired: true }),
    onSnapshot: (next) => { const f = () => next(snap(path)); listeners.add(f); setTimeout(f, 5); return () => listeners.delete(f); },
  });
  const db = { doc: docRef, collection: (c) => Object.assign(query(c), { doc: (id) => docRef(c + '/' + (id || Math.random().toString(36).slice(2))), add: async (d) => { const r = docRef(c + '/' + Math.random().toString(36).slice(2)); await r.set(d); return r; } }) };
  const me = { id: 'u_owner', name: 'Dona Teste', avatarUrl: '', color: '#000', email: null, isOwner: true, canEdit: true };
  const user = { me: async () => me, id: async () => me.id, isOwner: async () => true, canEdit: async () => true,
    profiles: async (ids) => Object.fromEntries([].concat(ids).map((id) => [id, { id, name: id === 'u_owner' ? 'Dona Teste' : id === 'u_ana' ? 'Ana Real' : '', avatarUrl: '', color: '#000', email: null, isMe: id === 'u_owner' }])),
    search: async (q) => [{ id: 'u_ana', name: 'Ana Real', avatarUrl: '', color: '#000', email: null, isMe: false }] };
  const downloads = { save: async ({ filename, data }) => { window.__download = { filename, text: await data.text() }; } };
  window.__store = store; window.__notify = notify;
  window.claude = { use: async (n) => ({ db, user, downloads }[n] || null) };
})();
</script>`;

const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>:root{color-scheme:light}body{margin:0;font:14px system-ui}img{max-width:100%}[hidden]{display:none!important}</style></head><body>${mock}${page0.replace(/src="img\//g, 'src="' + SITE + '/img/')}</body></html>`;
fs.writeFileSync(OUT + '/test.html', html);


const b = await chromium.launch(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {});
const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', (e) => erros.push('pageerror: ' + e.message));
p.on('console', (m) => { if (m.type() === 'error') erros.push('console: ' + m.text()); });
const shot = async (n) => { await p.waitForTimeout(300); await p.screenshot({ path: `${OUT}/v3-${n}.png` }); };
const toast = async () => (await p.locator('#toast p').textContent().catch(() => '(sem aviso)'));
const passo = (n) => console.log('✓', n);
const como = async (id) => { await p.keyboard.press('Escape'); await p.waitForTimeout(100); await p.keyboard.press('Escape'); await p.click('.conta'); await p.waitForTimeout(150); await p.selectOption('#demoAs', id); await p.waitForTimeout(350); };

await p.goto('file://' + OUT + '/test.html');
await p.waitForSelector('.nav', { timeout: 8000 });
passo('proprietária: navegação = ' + (await p.locator('.nav button span:not(.n)').allTextContents()).join(' | '));
await shot('01-painel');
await p.evaluate(() => { for (const [k, d] of window.__store) if (k.startsWith('dias/primavera_')) for (const t of Object.values(d.tarefas)) { if (t.titulo === 'Precificação') { t.inicio = new Date(Date.now() - 3600e3).toISOString(); t.prazo = new Date(Date.now() + 3600e3).toISOString(); } } window.__notify(); });
await como('demo-salao-primavera');
passo('colaborador: título = ' + await p.locator('h1').first().textContent());
passo('cartão agora = ' + await p.locator('.agora h2').textContent() + ' | botão = ' + await p.locator('.agora .btn').textContent());
await shot('02-hoje');
await p.click('.agora .btn'); await p.waitForSelector('#sheet .folha'); await p.waitForTimeout(300);
passo('folha aberta, itens com botões = ' + await p.locator('#sheet .op.feito').count());
await shot('03-execucao-inicio');
await p.click('[data-action="enviar"]'); await p.waitForTimeout(400);
passo('enviar incompleto: ' + await toast() + ' | destaque = ' + await p.locator('.item.falta').count());
const feitos = p.locator('#sheet .op.feito'); const n = await feitos.count();
for (let i = 1; i < n; i++) { await feitos.nth(i).click(); await p.waitForTimeout(120); }
await p.locator('#sheet .op.prob').first().click(); await p.waitForTimeout(200);
await p.locator('#sheet textarea[data-action="obsitem"]').fill('Leitor com defeito, conferi no caixa');
await p.locator('#sheet .cab h2').click(); await p.waitForTimeout(250);
passo('falta = ' + await p.locator('.falta-txt').textContent().catch(() => '(nada)'));
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDK+mmyAAAAABJRU5ErkJggg==', 'base64');
await fotosPendentes(p);
passo('fotos tiradas; falta = ' + await p.locator('.falta-txt').textContent().catch(() => '(nada)'));
await p.locator('#sheet input[type="file"]').first().setInputFiles({ name: 'rep.png', mimeType: 'image/png', buffer: png }); await p.waitForTimeout(900);
await p.locator('#sheet input[type="file"]').first().setInputFiles({ name: 'rep.png', mimeType: 'image/png', buffer: png }); await p.waitForTimeout(900);
passo('foto repetida: ' + await toast());
await shot('04-execucao');
await p.click('[data-action="enviar"]'); await p.waitForTimeout(500);
passo('envio: ' + await toast());
await shot('05-hoje-depois');
await como('demo-gerente-primavera');
passo('gerente: navegação = ' + (await p.locator('.nav button span:not(.n)').allTextContents()).join(' | ') + ' | badge = ' + await p.locator('.nav .n').textContent().catch(() => '0'));
await shot('06-aprovar');
await p.locator('.acao [data-action="reprovar"]').click(); await p.waitForTimeout(200);
await p.locator('form.dlg button[type="submit"]').click(); await p.waitForTimeout(200);
passo('reprovar sem motivo: ' + await p.locator('#erroDlg').textContent());
await p.fill('#motivo', 'Refaça a conferência com o leitor consertado'); await p.locator('form.dlg [data-action="itemRep"]').first().check();
await shot('07-reprovar');
await p.locator('form.dlg button[type="submit"]').click(); await p.waitForTimeout(400);
passo('reprovada: ' + await toast());
await como('demo-salao-primavera');
passo('colaborador vê: ' + await p.locator('.agora .rot').textContent() + ' / ' + await p.locator('.agora .btn').textContent());
await p.click('.agora .btn'); await p.waitForTimeout(400);
const f2 = p.locator('#sheet .op.feito'); const n2 = await f2.count(); for (let i = 0; i < n2; i++) { await f2.nth(i).click(); await p.waitForTimeout(100); }
await fotosPendentes(p);
await p.click('[data-action="enviar"]'); await p.waitForTimeout(400);
passo('reenvio: ' + await toast());
await como('demo-gerente-primavera');
await p.locator('.acao [data-action="aprovar"]').click(); await p.waitForTimeout(400);
passo('aprovação: ' + await toast());
await shot('08-aprovar-vazio');
await p.locator('.nav button', { hasText: 'Nova tarefa' }).click(); await p.waitForTimeout(200);
await p.fill('input[name="titulo"]', 'Montar ilha de panelas'); await shot('09-nova');
await p.click('form[data-action="criar"] button[type="submit"]'); await p.waitForTimeout(400);
passo('avulsa: ' + await toast() + ' | tela = ' + await p.locator('h1').first().textContent());
await shot('10-loja-hoje');
await p.locator('.nav button', { hasText: 'Mais' }).click(); await p.waitForTimeout(200);
await p.locator('[data-action="sub"][data-sub="rotinas"]').click(); await p.waitForTimeout(200);
passo('rotinas: ' + await p.locator('main .cartao').count());
await p.click('.conta'); await p.waitForTimeout(150); await p.selectOption('#demoAs', ''); await p.waitForTimeout(350);
await p.click('[data-action="exemplos"]'); await p.waitForTimeout(1500);
passo('KPIs: ' + (await p.locator('.kpi .v').allTextContents()).slice(0, 4).join(' / '));
await shot('11-painel-exemplos');
await p.locator('.loja-c').first().click(); await p.waitForTimeout(300);
passo('drill-down: ' + await p.locator('.linha-t').count());
await p.click('[data-action="csv"]'); await p.waitForTimeout(300);
passo('CSV: ' + (await p.evaluate(() => window.__download?.filename)));
await p.locator('.nav button', { hasText: 'Mais' }).click(); await p.waitForTimeout(200);
await p.locator('[data-action="sub"][data-sub="pessoas"]').click(); await p.waitForTimeout(200);
await p.click('#busca'); await p.waitForTimeout(200); await p.locator('[data-action="escolherPessoa"]').first().click();
await p.selectOption('select[name="papel"]', 'colaborador'); await p.selectOption('select[name="loja"]', 'castro');
await p.click('form[data-action="addPessoa"] button[type="submit"]'); await p.waitForTimeout(300);
passo('pessoa: ' + await toast());
await shot('12-pessoas');
await p.click('.conta'); await p.waitForTimeout(150); await p.click('.menu [data-action="ajuda"]'); await p.waitForTimeout(200);
await shot('13-ajuda');
const over = await p.evaluate(() => document.documentElement.scrollWidth - innerWidth); passo('mobile overflow-x ' + over);
await ctx.close();
const ctx2 = await b.newContext({ viewport: { width: 1440, height: 900 } });
const p2 = await ctx2.newPage(); p2.on('pageerror', (e) => erros.push('pageerror2: ' + e.message));
await p2.goto('file://' + OUT + '/test.html'); await p2.waitForSelector('.nav'); await p2.waitForTimeout(400);
await p2.evaluate(() => { localStorage.clear(); });
await p2.screenshot({ path: `${OUT}/v3-14-desktop.png` });
await p2.click('.conta'); await p2.selectOption('#demoAs', 'demo-gerente-primavera'); await p2.waitForTimeout(400);
await p2.screenshot({ path: `${OUT}/v3-15-desktop-gerente.png` });
passo('desktop overflow-x ' + await p2.evaluate(() => document.documentElement.scrollWidth - innerWidth));
const ctx3 = await b.newContext({ viewport: { width: 390, height: 844 }, colorScheme: 'dark', isMobile: true, deviceScaleFactor: 2 });
const p3 = await ctx3.newPage(); await p3.goto('file://' + OUT + '/test.html'); await p3.waitForSelector('.nav'); await p3.waitForTimeout(300);
await p3.click('.conta'); await p3.selectOption('#demoAs', 'demo-salao-primavera'); await p3.waitForTimeout(400);
await p3.screenshot({ path: `${OUT}/v3-16-escuro.png` });
await b.close();
console.log('capturas em', OUT); console.log(erros.length ? 'ERROS:\n' + erros.join('\n') : 'sem erros de página');
