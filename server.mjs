// Loopback only. Writes require a same-origin request carrying the app header.
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Worker } from 'node:worker_threads';
import { bare, readInventory, readItemFile, roots } from './core/inventory.mjs';
import { addAgent, addHook, addSkill, clearOldDownloads, copyToOther, history, installSource, previewSource, removeDeadHooks, removeItem, undo, UserError } from './core/mutate.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 4328);
const HOST = '127.0.0.1';
const BODY_LIMIT = 256 * 1024;
const WEEKS = 26;
const WEEK_MS = 7 * 24 * 3600 * 1000;
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' };
const CSP = "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'";

const r = roots();
let usage = { state: 'scanning', done: 0, total: 0, totals: null, sessions: null };

function startScan() {
  const worker = new Worker(join(HERE, 'core/usage.mjs'), { workerData: { usageScan: true, env: { ...process.env } } });
  worker.on('message', (m) => {
    if (m.type === 'progress') usage = { ...usage, done: m.done, total: m.total };
    if (m.type === 'done') usage = { state: 'ready', done: m.result.files, total: m.result.files, totals: m.result.totals, sessions: m.result.sessions };
    if (m.type === 'error') usage = { ...usage, state: 'failed' };
  });
  worker.on('error', () => { usage = { ...usage, state: 'failed' }; });
}

function weekIndex(day, now) {
  const age = Math.floor((now - Date.parse(`${day}T00:00:00Z`)) / WEEK_MS);
  return age >= 0 && age < WEEKS ? WEEKS - 1 - age : -1;
}

function withUsage(inv) {
  const now = Date.now();
  const t = usage.totals;
  const items = inv.items.map((it) => {
    const u = t?.[it.cli]?.[it.kind]?.[bare(it.name)];
    const weeks = Array(WEEKS).fill(0);
    for (const d of u?.days ?? []) { const i = weekIndex(d, now); if (i >= 0) weeks[i]++; }
    return { ...it, descChars: it.description.length, usage: t ? { sessions: u?.sessions ?? 0, last: u?.last ?? null, weeks } : null };
  });
  const hooks = inv.hooks.map((h) => {
    const measurable = h.cli === 'claude';
    const u = t?.[h.cli]?.hook?.[h.hash];
    return { ...h, usage: !t || !measurable ? null : { runs: u?.runs ?? 0, avgMs: u?.timed ? Math.round(u.ms / u.timed) : null, totalMs: u?.ms ?? 0, errors: u?.errors ?? 0, last: u?.last ?? null } };
  });
  const { totals: _t, ...status } = usage;
  return { ...inv, items, hooks, usageStatus: status, weeks: WEEKS };
}

const send = (res, status, body, type = 'application/json; charset=utf-8') => {
  res.writeHead(status, { 'content-type': type, 'content-security-policy': CSP, 'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer', 'cache-control': 'no-store' });
  res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body));
};

function readBody(req) {
  return new Promise((ok, fail) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > BODY_LIMIT) { fail(new UserError('That is too large.', 413)); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      try { ok(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}')); } catch { fail(new UserError('Bad request.')); }
    });
    req.on('error', fail);
  });
}

const ACTIONS = {
  '/api/add/skill': (b) => addSkill(r, b),
  '/api/add/agent': (b) => addAgent(r, b),
  '/api/add/hook': (b) => addHook(r, b),
  '/api/source/preview': (b) => previewSource(r, b),
  '/api/source/install': (b) => installSource(r, b),
  '/api/remove': (b) => removeItem(r, b),
  '/api/remove-dead': (b) => removeDeadHooks(r, b),
  '/api/copy': (b) => copyToOther(r, b),
  '/api/undo': (b) => undo(r, b),
};

const server = createServer(async (req, res) => {
  const origin = `http://${HOST}:${PORT}`;
  if (req.headers.host !== `${HOST}:${PORT}` && req.headers.host !== `localhost:${PORT}`) return send(res, 403, { error: 'Forbidden host.' });
  const url = new URL(req.url, origin);
  try {
    if (req.method === 'POST') {
      const fromApp = req.headers['x-reins'] === '1' && [origin, `http://localhost:${PORT}`].includes(req.headers.origin);
      if (!fromApp) return send(res, 403, { error: 'Forbidden.' });
      const action = ACTIONS[url.pathname];
      if (!action) return send(res, 404, { error: 'Not found.' });
      return send(res, 200, await action(await readBody(req)));
    }
    if (req.method !== 'GET') return send(res, 405, { error: 'Method not allowed.' });
    if (url.pathname === '/api/inventory') return send(res, 200, withUsage(readInventory(r)));
    if (url.pathname === '/api/history') return send(res, 200, history(r));
    if (url.pathname === '/api/item') {
      const inv = readInventory(r);
      const it = inv.items.find((x) => x.id === url.searchParams.get('id'));
      if (!it) return send(res, 404, { error: 'This item no longer exists.' });
      return send(res, 200, readItemFile(it.file));
    }
    const name = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
    if (!/^[a-z0-9-]+\.(html|js|css)$/.test(name)) return send(res, 404, { error: 'Not found.' });
    return send(res, 200, readFileSync(join(HERE, 'web', name)), MIME[extname(name)]);
  } catch (err) {
    if (err instanceof UserError) return send(res, err.status, { error: err.message });
    if (err.code === 'ENOENT') return send(res, 404, { error: 'Not found.' });
    console.error(err.code ?? err.name);
    return send(res, 500, { error: 'Something went wrong. Nothing else was changed.' });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Reins on http://${HOST}:${PORT}/`);
  clearOldDownloads(r);
  startScan();
});
