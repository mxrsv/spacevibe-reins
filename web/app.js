import { h, icon } from './dom.js';
import { confirmDialog, openAddDrawer } from './shared.js';
import { viewA, viewB, viewC } from './directions.js';

const POLL_MS = 2000;
const TOAST_MS = 9000;
const VIEWS = { a: viewA, b: viewB, c: viewC };
const root = document.getElementById('root');
const params = new URLSearchParams(location.search);

const state = {
  dir: VIEWS[params.get('d')] ? params.get('d') : 'a',
  tab: 'skill', cli: 'all', filter: 'all', q: '', event: null, selected: null, voided: new Set(),
};
document.documentElement.dataset.dir = state.dir;

let data = null;
let historyEntries = [];
let preview = null;

async function api(path, body) {
  const res = await fetch(path, body ? { method: 'POST', headers: { 'content-type': 'application/json', 'x-reins': '1' }, body: JSON.stringify(body) } : undefined);
  const json = await res.json().catch(() => ({ error: 'The app did not answer.' }));
  if (!res.ok) throw new Error(json.error ?? 'Something went wrong.');
  return json;
}

async function load() {
  [data, historyEntries] = await Promise.all([api('/api/inventory'), api('/api/history')]);
}

function toast(message, undoId) {
  const box = document.getElementById('toast');
  const el = h('div', { class: 'toast', role: 'status' }, h('span', {}, message),
    undoId ? h('button', { type: 'button', class: 'btn', onclick: () => { el.remove(); ctx.undo(undoId); } }, icon('undo'), 'Undo') : null);
  box.replaceChildren(el);
  setTimeout(() => el.remove(), TOAST_MS);
}

const fail = (err) => toast(err.message);

async function loadPreview(id) {
  const it = data.items.find((x) => x.id === id);
  if (!it) return;
  try {
    const file = await api(`/api/item?id=${encodeURIComponent(id)}`);
    preview = { id, text: file.text };
    const pre = document.getElementById('preview');
    if (pre && state.selected === id) pre.textContent = file.text;
  } catch (err) { fail(err); }
}

const ctx = {
  state,
  get data() { return data; },
  get history() { return historyEntries; },
  get preview() { return preview; },
  api,
  set(patch, keepFocus) {
    Object.assign(state, patch);
    render(keepFocus);
  },
  select(id) {
    state.selected = id;
    render();
    if (id) loadPreview(id);
  },
  openAdd() {
    openAddDrawer(ctx, state.tab === 'agent' || state.tab === 'hook' ? state.tab : 'skill');
  },
  async after(entry) {
    await load();
    render();
    toast(entry.label, entry.id);
  },
  async remove(it) {
    try {
      const entry = await api('/api/remove', { id: it.id });
      state.voided = new Set([...state.voided, it.id]);
      render();
      toast(entry.label, entry.id);
      setTimeout(async () => {
        state.voided = new Set([...state.voided].filter((x) => x !== it.id));
        state.selected = state.selected === it.id ? null : state.selected;
        await load();
        render();
      }, 1100);
    } catch (err) { fail(err); }
  },
  async removeDead(cli, count) {
    const ok = await confirmDialog(`Remove ${count} dead ${count === 1 ? 'hook' : 'hooks'}?`, 'Their scripts no longer exist. You can undo this from History.', 'Remove');
    if (!ok) return;
    try {
      await ctx.after(await api('/api/remove-dead', { cli }));
    } catch (err) { fail(err); }
  },
  async copy(it) {
    try { await ctx.after(await api('/api/copy', { id: it.id })); } catch (err) { fail(err); }
  },
  async undo(id) {
    try {
      const { label } = await api('/api/undo', { id });
      await load();
      render();
      toast(`Undone: ${label}`);
    } catch (err) { fail(err); }
  },
};

// Bar widths are set here because the CSP forbids inline style attributes.
function applyWidths() {
  for (const el of root.querySelectorAll('[data-w]')) el.style.width = `${el.dataset.w}%`;
}

function render(keepFocus) {
  if (!data) return;
  const scroller = root.querySelector('.main');
  const top = scroller?.scrollTop ?? 0;
  const caret = keepFocus ? document.getElementById(keepFocus)?.selectionStart : null;
  root.replaceChildren(VIEWS[state.dir](ctx));
  applyWidths();
  const nextScroller = root.querySelector('.main');
  if (nextScroller) nextScroller.scrollTop = top;
  if (keepFocus) {
    const el = document.getElementById(keepFocus);
    el?.focus();
    if (caret != null) el?.setSelectionRange(caret, caret);
  }
}

document.addEventListener('keydown', (e) => {
  if (document.querySelector('dialog[open]') || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) {
    if (e.key === 'Escape' && e.target.id === 'q') { state.q = ''; render(); }
    return;
  }
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === '/') { e.preventDefault(); document.getElementById('q')?.focus(); }
  if (e.key === 'n') { e.preventDefault(); ctx.openAdd(); }
  if (e.key === 'Escape' && state.selected) ctx.select(null);
});

async function poll() {
  if (data.usageStatus.state !== 'scanning') return;
  await new Promise((done) => setTimeout(done, POLL_MS));
  try {
    await load();
    if (!document.querySelector('dialog[open]') && document.activeElement?.id !== 'q') render();
  } catch { /* the next poll retries */ }
  poll();
}

load().then(() => { render(); poll(); }).catch((err) => {
  root.replaceChildren(h('p', { class: 'empty' }, err.message));
});
