// Teste local do site com uma simulação de window.claude (db + user + downloads).
// Uso (na raiz do repositório): node site/teste/run.mjs
// Chromium: CHROME_PATH ou o navegador do Playwright instalado.
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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

// foto de teste
const b = await chromium.launch(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {});
const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', (e) => erros.push('pageerror: ' + e.message));
p.on('console', (m) => { if (m.type() === 'error') erros.push('console: ' + m.text()); });
const shot = async (n) => { await p.waitForTimeout(250); await p.screenshot({ path: `${OUT}/${n}.png`, fullPage: false }); };
const passo = (n) => console.log('✓', n);

await p.goto('file://' + OUT + '/test.html');
await p.waitForSelector('.tabs', { timeout: 8000 });
passo('proprietária carrega com abas: ' + (await p.locator('.tab').allTextContents()).join(' | '));
await shot('01-painel-proprietaria');

// ver como colaborador do salão da Primavera
await p.selectOption('#demoAs', 'demo-salao-primavera');
await p.waitForTimeout(300);
const tarefas = await p.locator('.tarefa').count();
passo('colaborador vê ' + tarefas + ' tarefas');
await shot('02-hoje-colaborador');

// abrir a primeira tarefa disponível (forçar janela aberta: ajusta inicio no store)
await p.evaluate(() => { for (const [k, d] of window.__store) if (k.startsWith('dias/primavera_')) for (const t of Object.values(d.tarefas)) { t.inicio = new Date(Date.now() - 3600e3).toISOString(); t.prazo = new Date(Date.now() + 3600e3).toISOString(); } window.__notify(); });
await p.selectOption('#demoAs', 'demo-gerente-primavera'); await p.waitForTimeout(100);
await p.selectOption('#demoAs', 'demo-salao-primavera'); await p.waitForTimeout(300);
await p.locator('.tarefa', { hasText: 'Precificação' }).first().click();
await p.waitForSelector('#sheet .folha');
await shot('03-tarefa-antes');
await p.click('[data-action="comecar"]'); await p.waitForTimeout(300);
passo('começou a tarefa');
// tentar enviar sem marcar
await p.click('[data-action="enviar"]'); await p.waitForTimeout(200);
passo('mensagem ao enviar incompleto: ' + (await p.locator('[role="status"]').first().textContent().catch(() => '(nenhuma)')));
// marcar itens; um não conforme
const checks = p.locator('#sheet [data-action="marcar"]');
const n = await checks.count();
for (let i = 1; i < n; i++) { await checks.nth(i).click(); await p.waitForTimeout(120); }
await p.locator('#sheet [data-action="naoconforme"]').first().click(); await p.waitForTimeout(200);
await p.locator('#sheet textarea[data-action="obsitem"]').fill('Leitor com defeito, conferi no sistema do caixa');
await p.locator('#sheet h2').first().click(); await p.waitForTimeout(250);
// foto do item que pede foto
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDK+mmyAAAAABJRU5ErkJggg==', 'base64');
const inputs = p.locator('#sheet input[type="file"]');
await inputs.first().setInputFiles({ name: 'foto.png', mimeType: 'image/png', buffer: png });
await p.waitForTimeout(1200);
passo('foto: ' + (await p.locator('[role="status"]').first().textContent().catch(() => '(sem aviso)')));
// mesma foto de novo: deve bloquear
await p.locator('#sheet input[type="file"]').first().setInputFiles({ name: 'foto.png', mimeType: 'image/png', buffer: png });
await p.waitForTimeout(1000);
passo('foto repetida: ' + (await p.locator('[role="status"]').first().textContent().catch(() => '(sem aviso)')));
await shot('04-tarefa-execucao');
await p.click('[data-action="enviar"]'); await p.waitForTimeout(400);
passo('envio: ' + (await p.locator('[role="status"]').first().textContent().catch(() => '(sem aviso)')));
await shot('05-hoje-depois-envio');

// gerente aprova/reprova
await p.selectOption('#demoAs', 'demo-gerente-primavera'); await p.waitForTimeout(400);
passo('abas do gerente: ' + (await p.locator('.tab').allTextContents()).join(' | '));
await shot('06-fila-gerente');
await p.locator('[data-action="reprovar"]').first().click(); await p.waitForTimeout(200);
await p.locator('form.dlg button[type="submit"]').click(); await p.waitForTimeout(200);
passo('reprovar sem motivo: ' + await p.locator('#erroDlg').textContent());
await p.fill('#motivo', 'Refaça a conferência com o leitor consertado');
await p.locator('form.dlg [data-action="itemRep"]').first().check();
await p.locator('form.dlg button[type="submit"]').click(); await p.waitForTimeout(400);
passo('reprovada: ' + (await p.locator('[role="status"]').first().textContent().catch(() => '')));

// colaborador vê correção e refaz
await p.selectOption('#demoAs', 'demo-salao-primavera'); await p.waitForTimeout(300);
await shot('07-hoje-correcao');
await p.locator('.tarefa', { hasText: 'Precificação' }).first().click(); await p.waitForTimeout(200);
await p.click('[data-action="comecar"]'); await p.waitForTimeout(300);
const c2 = p.locator('#sheet [data-action="marcar"]'); const n2 = await c2.count();
for (let i = 0; i < n2; i++) { await c2.nth(i).click(); await p.waitForTimeout(120); }
await p.locator('#sheet input[type="file"]').first().setInputFiles({ name: 'foto2.png', mimeType: 'image/png', buffer: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGNgYPj/n4GBgYGBkYEBAAAN/wP+u+QxvgAAAABJRU5ErkJggg==', 'base64') });
await p.waitForTimeout(1200);
await p.click('[data-action="enviar"]'); await p.waitForTimeout(400);
passo('reenvio: ' + (await p.locator('[role="status"]').first().textContent().catch(() => '')));

// gerente aprova
await p.selectOption('#demoAs', 'demo-gerente-primavera'); await p.waitForTimeout(300);
await p.locator('[data-action="aprovar"]').first().click(); await p.waitForTimeout(400);
passo('aprovação: ' + (await p.locator('[role="status"]').first().textContent().catch(() => '')));

// nova tarefa avulsa
await p.locator('.tab', { hasText: 'Nova tarefa' }).click(); await p.waitForTimeout(200);
await p.fill('input[name="titulo"]', 'Montar ilha de panelas');
const fim = new Date(Date.now() + 2 * 3600e3); const hh = new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' }).format(fim);
await p.fill('input[name="fim"]', hh);
await p.fill('textarea[name="itens"]', 'Ilha montada\nPreços colocados');
await shot('08-nova-tarefa');
await p.click('form[data-action="criar"] button[type="submit"]'); await p.waitForTimeout(400);
passo('avulsa: ' + (await p.locator('[role="status"]').first().textContent().catch(() => '')) + ' | aba: ' + await p.locator('.tab[aria-current="page"]').textContent());

// proprietária: exemplos + painel + csv
await p.selectOption('#demoAs', ''); await p.waitForTimeout(300);
await p.click('[data-action="exemplos"]'); await p.waitForTimeout(1500);
await p.locator('.tab', { hasText: 'Painel' }).click(); await p.waitForTimeout(300);
passo('KPIs: ' + (await p.locator('.kpi .v').allTextContents()).join(' / '));
await shot('09-painel-com-exemplos');
await p.click('[data-action="csv"]'); await p.waitForTimeout(300);
const dl = await p.evaluate(() => window.__download);
passo('CSV: ' + dl?.filename + ' linhas=' + dl?.text.split('\n').length);
await p.click('[data-action="periodo"][data-p="30"]'); await p.waitForTimeout(500);
passo('30 dias KPIs: ' + (await p.locator('.kpi .v').allTextContents()).slice(0, 3).join(' / '));
await p.locator('tr.click').first().click(); await p.waitForTimeout(300);
passo('drill-down: ' + await p.locator('.tarefa').count() + ' tarefas listadas');
// pessoas
await p.locator('.tab', { hasText: 'Pessoas' }).click(); await p.waitForTimeout(200);
await p.click('#busca'); await p.waitForTimeout(200);
await p.locator('[data-action="escolherPessoa"]').first().click();
await p.selectOption('select[name="papel"]', 'colaborador'); await p.selectOption('select[name="loja"]', 'castro');
await p.click('form[data-action="addPessoa"] button[type="submit"]'); await p.waitForTimeout(300);
passo('pessoa: ' + (await p.locator('[role="status"]').first().textContent().catch(() => '')));
await shot('10-pessoas');
// rotinas: editar
await p.locator('.tab', { hasText: 'Rotinas' }).click(); await p.waitForTimeout(200);
await p.locator('[data-action="editarRotina"]').first().click(); await p.waitForTimeout(200);
await p.fill('input[name="peso"]', '9'); await p.click('form.dlg button[type="submit"]'); await p.waitForTimeout(150);
passo('rotina peso 9: ' + await p.locator('#erroDlg').textContent());
await p.fill('input[name="peso"]', '4'); await p.click('form.dlg button[type="submit"]'); await p.waitForTimeout(300);
passo('rotina salva: ' + (await p.locator('[role="status"]').first().textContent().catch(() => '')));
await p.click('[data-action="apagarExemplos"]').catch(() => {});
// desktop + escuro
await ctx.close();
const ctx2 = await b.newContext({ viewport: { width: 1440, height: 900 }, colorScheme: 'dark' });
const p2 = await ctx2.newPage(); p2.on('pageerror', (e) => erros.push('pageerror2: ' + e.message));
await p2.goto('file://' + OUT + '/test.html'); await p2.waitForSelector('.tabs'); await p2.waitForTimeout(400);
await p2.screenshot({ path: `${OUT}/11-desktop-escuro.png` });
const over = await p2.evaluate(() => document.documentElement.scrollWidth - innerWidth);
passo('desktop overflow-x ' + over);
await b.close();
console.log('capturas em', OUT); console.log(erros.length ? 'ERROS:\n' + erros.join('\n') : 'sem erros de página');
