/* Shared mock runtime: icons, state, usage cells, standard views, palette, toast/undo. */
const ICONS = {
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
  loadout: '<path d="M12 3 3.5 7.5 12 12l8.5-4.5L12 3Z"/><path d="m3.5 12 8.5 4.5 8.5-4.5"/><path d="m3.5 16.5 8.5 4.5 8.5-4.5"/>',
  rules: '<path d="M12 3 4.5 6v5.5c0 4.4 3 7.9 7.5 9.5 4.5-1.6 7.5-5.1 7.5-9.5V6L12 3Z"/><path d="m9 12 2 2 4-4"/>',
  activity: '<path d="M3 12h4l2.5-6 4 12 2.5-6H21"/>',
  review: '<path d="M5 21V4"/><path d="M5 4h12l-2.5 4.5L17 13H5"/>',
  skill: '<path d="m12 3 2.2 5.3L20 9l-4.3 3.8L17 18.5 12 15.6 7 18.5l1.3-5.7L4 9l5.8-.7L12 3Z"/>',
  agent: '<circle cx="12" cy="8" r="3.5"/><path d="M5 20c.8-4 3.6-6 7-6s6.2 2 7 6"/>',
  hook: '<path d="M12 3v8"/><path d="M12 11a4 4 0 1 0 4 4"/><path d="M16 15h4"/>',
  trash: '<path d="M4 7h16"/><path d="M10 11v6M14 11v6"/><path d="m6 7 1 13h10l1-13"/><path d="M9 7V4h6v3"/>',
  undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/>',
  lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  alert: '<path d="M12 4 2.8 19.5h18.4L12 4Z"/><path d="M12 10v4M12 17v.01"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
  moon: '<path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5Z"/>',
  dead: '<circle cx="12" cy="12" r="8"/><path d="m9 9 6 6M15 9l-6 6"/>',
  file: '<path d="M7 3h7l5 5v13H7V3Z"/><path d="M14 3v5h5"/>',
  play: '<path d="M7 4.5v15l12-7.5L7 4.5Z"/>',
};
const ic = (n, sz = 16) => `<svg class="ic" width="${sz}" height="${sz}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[n]}</svg>`;
const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = (n) => n.toLocaleString('en-US');
const CLI = { claude: 'Claude Code', codex: 'Codex' };
const OTHER = { claude: 'codex', codex: 'claude' };
const KINDS = { skill: 'Skills', agent: 'Agents', hook: 'Hooks' };

const S = {
  tab: 'loadout', kind: 'skill', filter: 'all', scope: 'Global', sel: null, undo: null,
  items: structuredClone(DATA.items), removed: new Set(), kept: new Set(),
  rules: structuredClone(DATA.rules), rmRules: new Set(), codex: structuredClone(DATA.codex),
  caps: structuredClone(DATA.caps), openCaps: new Set(), ev: null,
};
const live = () => S.items.filter((i) => !S.removed.has(i.id));
const itemById = (id) => S.items.find((i) => i.id === id);

/* classification */
const present = (it) => ['claude', 'codex'].filter((c) => it[c].s !== 'missing');
const inOne = (it) => present(it).length === 1;
const neverRan = (it) => !it.dead && present(it).length > 0 && present(it).every((c) => it[c].s === 'counted' && it[c].n === 0);
const filters = {
  all: () => true, one: inOne, never: neverRan, dead: (it) => !!it.dead,
};
const FILTER_LABEL = { all: 'All', one: 'In one CLI only', never: 'Never ran', dead: 'Dead' };
const totalErrors = () => live().reduce((a, i) => a + (i.errors || 0), 0);

/* undo / toast */
let toastTimer;
function toast(msg, undo) {
  const t = $('#toast');
  t.innerHTML = `<span>${esc(msg)}</span>${undo ? `<button data-act="undo">${ic('undo', 14)}Undo</button>` : ''}`;
  t.classList.add('show');
  S.undo = undo || null;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 7000);
}

/* usage evidence cell: counted / never / not counted yet / not measurable / not installed */
function kindMax(kind) { return Math.max(...S.items.filter((i) => i.kind === kind).flatMap((i) => ['claude', 'codex'].map((c) => i[c].n || 0))); }
function useCell(it, cli, opts = {}) {
  const cell = it[cli];
  if (cell.s === 'missing') {
    return opts.add
      ? `<div class="use"><button class="btn ghost" data-act="copy" data-id="${it.id}" data-to="${cli}">${ic('plus', 13)}Add to ${CLI[cli]}</button></div>`
      : `<div class="use na"><span>not installed</span></div>`;
  }
  if (cell.s === 'pending') return `<div class="use" title="Installed, no runs in the logs yet"><span class="bar pending"></span><span class="num pend">···</span></div>`;
  if (cell.s === 'na') return `<div class="use na" title="${esc(cell.why)}">${ic('alert', 14)}<span>not measurable</span></div>`;
  const w = cell.n ? Math.max(4, Math.round(Math.sqrt(cell.n / kindMax(it.kind)) * 100)) : 0;
  return `<div class="use"><span class="bar ${cli}"><i style="width:${w}%"></i></span><span class="num ${cell.n === 0 ? 'zero' : ''}">${fmt(cell.n)}</span></div>`;
}
const itemTags = (it) => [
  it.owner ? `<span class="tag">${ic('lock', 11)}${esc(it.owner)}</span>` : '',
  it.dead ? `<span class="tag danger">${ic('dead', 11)}${esc(it.dead)}</span>` : '',
  it.errors ? `<span class="tag warn">${it.errors} errors</span>` : '',
  it.note ? `<span class="tag">${esc(it.note)}</span>` : '',
].join(' ');

/* mutations (each returns an undo closure) */
function doRemove(id) {
  S.removed.add(id); const it = itemById(id);
  toast(`Removed ${it.kind === 'hook' ? 'hook ' + it.desc : it.name}`, () => S.removed.delete(id));
}
function doCopy(id, to) {
  const it = itemById(id); const prev = it[to]; it[to] = PEND;
  toast(`Added ${it.name} to ${CLI[to]}`, () => { it[to] = prev; });
}
function doRuleRemove(id) {
  S.rmRules.add(id); const r = S.rules.find((x) => x.id === id);
  toast(`Removed ${r.rule}`, () => S.rmRules.delete(id));
}

function doNarrow(id) {
  const r = S.rules.find((x) => x.id === id); const prev = r.v; const why = r.broad; r.v = 'ask'; delete r.broad;
  toast(`${r.rule} now asks first`, () => { r.v = prev; r.broad = why; });
}

/* standard views ------------------------------------------------------- */
function loadoutTools() {
  const items = live().filter((i) => i.kind === S.kind);
  const cnt = (k) => live().filter((i) => i.kind === k).length;
  const fc = (f) => items.filter(filters[f]).length;
  return `<div class="tools"><div class="seg" role="group" aria-label="Kind">${Object.keys(KINDS).map((k) => `<button data-act="kind" data-v="${k}" aria-pressed="${S.kind === k}">${KINDS[k]}<span class="n">${cnt(k)}</span></button>`).join('')}</div>
  <div class="chips" role="group" aria-label="Filter">${Object.keys(FILTER_LABEL).map((f) => `<button class="chip" data-act="filter" data-v="${f}" aria-pressed="${S.filter === f}">${FILTER_LABEL[f]}<span class="n">${fc(f)}</span></button>`).join('')}</div><span class="sp"></span><span class="sub">Last 30 days</span></div>`;
}
function itemRow(it) {
  const canRemove = !it.owner;
  const missing = ['claude', 'codex'].find((c) => it[c].s === 'missing');
  return `<div class="row click" role="button" tabindex="0" data-act="select" data-id="${it.id}" aria-selected="${S.sel === it.id}">
    <span class="lead">${ic(it.kind)}</span>
    <div class="grow"><div class="title">${esc(it.name)} ${itemTags(it)}</div><div class="sub ${it.kind === 'hook' ? 'mono' : ''}">${esc(it.desc)}</div></div>
    ${useCell(it, 'claude')}${useCell(it, 'codex')}
    <div class="acts iacts" style="width:132px;justify-content:flex-end">
      ${missing && !it.dead ? `<button class="btn" data-act="copy" data-id="${it.id}" data-to="${missing}" title="Add to ${CLI[missing]}">${ic('copy', 13)}${CLI[missing] === 'Codex' ? 'Codex' : 'Claude'}</button>` : ''}
      ${canRemove ? `<button class="btn danger" data-act="remove" data-id="${it.id}" aria-label="Remove ${esc(it.name)}">${ic('trash', 13)}</button>` : `<span class="sub">read-only</span>`}
    </div></div>`;
}
function colHead() {
  return `<div class="row" style="min-height:32px;background:var(--surface-2)"><span class="lead"></span><div class="grow sub">Name</div>
    <div class="use sub"><span class="dot claude"></span>Claude Code</div><div class="use sub"><span class="dot codex"></span>Codex</div><div class="iacts" style="width:132px"></div></div>`;
}
function legend() {
  return `<div class="legend"><span><i class="sw"></i>counted from logs</span><span><i class="sw z"></i><b style="color:var(--danger);font-weight:600">0</b> never ran</span><span><i class="sw d"></i>not counted yet</span><span>${ic('alert', 13)}not measurable</span></div>`;
}
function viewLoadout() {
  const rows = live().filter((i) => i.kind === S.kind && filters[S.filter](i));
  return `<div class="scroll"><div class="group">${colHead()}${rows.map(itemRow).join('') || `<div class="row"><div class="sub">Nothing matches this filter.</div></div>`}</div>${legend()}</div>`;
}

const VERDICT = { allow: ['Allow', ''], ask: ['Ask', 'warn'], deny: ['Deny', 'danger'] };
function ruleRow(r) {
  return `<div class="row"><span style="width:52px"><span class="tag ${VERDICT[r.v][1]}">${VERDICT[r.v][0]}</span></span>
    <div class="grow"><div class="title mono">${esc(r.rule)}</div>${r.broad ? `<div class="sub" style="color:var(--warn)">Broad. ${esc(r.broad)}</div>` : ''}</div>
    <div class="acts">${r.broad ? `<button class="btn" data-act="narrow" data-id="${r.id}">Narrow to ask</button>` : ''}<button class="btn danger" data-act="rule-remove" data-id="${r.id}" aria-label="Remove ${esc(r.rule)}">${ic('trash', 13)}</button></div></div>`;
}
function viewRules() {
  const rs = S.rules.filter((r) => r.scope === S.scope && !S.rmRules.has(r.id));
  const grp = (v, label) => { const l = rs.filter((r) => r.v === v); return l.length ? `<div class="glabel">${label}<span class="n">${l.length}</span></div><div class="group">${l.map(ruleRow).join('')}</div>` : ''; };
  return `<div class="tools"><select class="select" data-act="scope" aria-label="Scope">${DATA.scopes.map((s) => `<option ${s === S.scope ? 'selected' : ''}>${s}</option>`).join('')}</select><span class="sub">${S.scope === 'Global' ? 'Applies to every project' : 'Adds to Global rules'}</span></div>
  <div class="scroll"><div class="glabel"><span class="dot claude"></span>Claude Code<span class="n">${rs.length} rules</span></div>${rs.length ? '' : '<div class="group"><div class="row sub">No rules at this scope.</div></div>'}${grp('deny', 'Deny')}${grp('ask', 'Ask first')}${grp('allow', 'Allow')}
  <div class="glabel"><span class="dot codex"></span>Codex<span class="n">config.toml</span></div><div class="group">${S.codex.map((c) => `<div class="row"><div class="grow title mono">${c.key}</div><select class="select mono" data-act="codex" data-key="${c.key}">${c.options.map((o) => `<option ${o === c.value ? 'selected' : ''}>${o}</option>`).join('')}</select></div>`).join('')}</div></div>`;
}

function sessionTitle(s) { return s.fallback ? `<span class="mono">${esc(s.title)}</span>` : esc(s.title); }
function sessionRow(s) {
  const st = { running: ['running', 'tag claude'], waiting: ['waiting for you', 'tag warn'], na: ['not measurable', 'tag'] }[s.state];
  return `<div class="row" ${s.why ? `title="${esc(s.why)}"` : ''}><span class="dot ${s.cli}"></span>
    <div class="grow"><div class="title">${sessionTitle(s)}</div><div class="sub">${s.project} · ${s.fallback ? 'first request: "đổi thứ tự bài học trong khoá"' : esc(s.tool)} · ${s.age}</div></div>
    <span class="${st[1]}">${st[0]}</span><span class="num" style="width:56px" title="Estimated from token logs">~${s.cost}</span></div>`;
}
function failureRow(f, extra = '') {
  return `<div class="row ${extra}" data-act="select-f" data-id="${f.id}"><span class="dot ${f.cli}"></span>
    <div class="grow"><div class="title mono">${esc(f.cmd)}</div><div class="sub">${esc(f.exit)} · ${esc(f.project)} · last ${f.last}</div></div>
    <span class="tag ${f.n >= 5 ? 'danger' : ''}">×${f.n}</span></div>`;
}
function fileRow(f) {
  const i = f.path.lastIndexOf('/');
  return `<div class="row"><span class="lead">${ic('file')}</span><div class="grow"><div class="title mono"><span style="color:var(--fg-3)">${esc(f.path.slice(0, i + 1))}</span>${esc(f.path.slice(i + 1))}</div></div>
    <span class="sub">${f.edits} edits · ${f.sessions} session${f.sessions > 1 ? 's' : ''} · ${f.last}</span></div>`;
}
function viewActivity() {
  return `<div class="scroll"><div class="glabel">Running<span class="n">${DATA.sessions.length}</span></div><div class="group">${DATA.sessions.map(sessionRow).join('')}</div>
  <div class="glabel">Failed commands<span class="n">repeats grouped</span></div><div class="group">${DATA.failures.map((f) => failureRow(f)).join('')}</div>
  <div class="glabel">File history<span class="n">across sessions</span></div><div class="group">${DATA.files.map(fileRow).join('')}</div></div>`;
}

/* page frame ----------------------------------------------------------- */
const DIRS = [['a-triage.html', 'A · Triage'], ['b-matrix.html', 'B · Matrix'], ['c-timeline.html', 'C · Timeline']];
function navBtn(tab, label, icon, count, alert) {
  return `<button data-act="nav" data-tab="${tab}" aria-current="${S.tab === tab ? 'page' : 'false'}">${ic(icon)}${label}${count != null ? `<span class="count ${alert ? 'alert' : ''}">${count}</span>` : ''}</button>`;
}
function frame({ nav, title, main, hints }) {
  const here = location.pathname.split('/').pop();
  return `<div class="app"><aside class="side"><div class="lights"><i></i><i></i><i></i></div><nav class="nav" aria-label="Sections">${nav}</nav>
    <div class="side-foot"><span>Mock data</span><span class="sp"></span><button class="icon-btn" data-act="theme" aria-label="Toggle theme">${ic('moon')}</button></div></aside>
    <main class="main"><div class="top"><h1>${title}</h1><span class="sp"></span><button class="search" data-act="palette">${ic('search', 15)}<span>Search or run a command</span><kbd>⌘K</kbd></button></div>${main}
    <div class="hintbar">${hints}</div></main></div>
    <div class="mockbar" aria-label="Direction">${DIRS.map(([h, l]) => `<a href="${h}" ${h === here ? 'aria-current="page"' : ''}>${l}</a>`).join('')}</div>
    <div class="pal-wrap" id="pal"><div class="pal" role="dialog" aria-label="Command palette"><input id="pal-q" placeholder="Search skills, hooks, rules, or run an action" autocomplete="off"><div class="pal-list" id="pal-list"></div><div class="pal-foot"><span><kbd>↑</kbd><kbd>↓</kbd> navigate</span><span><kbd>↵</kbd> run</span><span><kbd>esc</kbd> close</span></div></div></div>`;
}
const hint = (k, t) => `<span><kbd>${k}</kbd>${t}</span>`;

/* command palette ------------------------------------------------------ */
let palIdx = 0, palRows = [];
function palActions(go) {
  const acts = [];
  ['loadout', 'rules', 'activity'].forEach((t) => acts.push({ g: 'Go to', label: t[0].toUpperCase() + t.slice(1), icon: t, run: () => go(t) }));
  live().filter((i) => i.dead).forEach((i) => acts.push({ g: 'Actions', label: `Remove dead hook ${i.desc}`, icon: 'trash', run: () => doRemove(i.id) }));
  live().filter((i) => i.codex.s === 'missing' && i.kind !== 'hook' && !i.owner).slice(0, 3).forEach((i) => acts.push({ g: 'Actions', label: `Copy ${i.name} to Codex`, icon: 'copy', run: () => doCopy(i.id, 'codex') }));
  if (S.undo) acts.push({ g: 'Actions', label: 'Undo last change', icon: 'undo', run: () => S.undo() });
  live().forEach((i) => acts.push({ g: KINDS[i.kind], label: i.name + (i.kind === 'hook' ? '  ' + i.desc : ''), icon: i.kind, r: i.kind, run: () => { S.kind = i.kind; S.filter = 'all'; S.sel = i.id; go('loadout'); } }));
  return acts;
}
function palRender(go) {
  const q = $('#pal-q').value.toLowerCase();
  palRows = palActions(go).filter((a) => a.label.toLowerCase().includes(q)).slice(0, 12);
  palIdx = Math.min(palIdx, Math.max(0, palRows.length - 1));
  let last = ''; let html = '';
  palRows.forEach((a, i) => { if (a.g !== last) { html += `<div class="pal-h">${a.g}</div>`; last = a.g; } html += `<div class="pal-i" data-pi="${i}" aria-selected="${i === palIdx}">${ic(a.icon, 15)}<span>${esc(a.label)}</span>${a.r ? `<span class="r">${a.r}</span>` : ''}</div>`; });
  $('#pal-list').innerHTML = html || '<div class="pal-h">No results</div>';
}

/* boot ----------------------------------------------------------------- */
function boot({ render, extra = {} }) {
  document.body.insertAdjacentHTML('beforeend', '<div class="toast" id="toast" role="status"></div>');
  const redraw = () => { const y = $('.scroll')?.scrollTop; render(); if (y) { const s = $('.scroll'); if (s) s.scrollTop = y; } };
  const doGo = (t) => { S.tab = t; closePal(); redraw(); };
  const openPal = () => { $('#pal').classList.add('open'); $('#pal-q').value = ''; palIdx = 0; palRender(doGo); $('#pal-q').focus(); };
  const closePal = () => $('#pal')?.classList.remove('open');
  const acts = {
    nav: (d) => { S.tab = d.tab; S.sel = null; },
    kind: (d) => { S.kind = d.v; S.filter = 'all'; }, filter: (d) => { S.filter = d.v; },
    remove: (d) => doRemove(d.id), copy: (d) => doCopy(d.id, d.to), 'rule-remove': (d) => doRuleRemove(d.id),
    select: (d) => { S.sel = S.sel === d.id ? null : d.id; },
    narrow: (d) => doNarrow(d.id),
    theme: () => { const l = document.documentElement.dataset.theme !== 'light'; document.documentElement.dataset.theme = l ? 'light' : 'dark'; },
    palette: () => openPal(),
    undo: () => { S.undo?.(); S.undo = null; $('#toast').classList.remove('show'); },
    ...extra,
  };
  document.addEventListener('click', (e) => {
    const pi = e.target.closest('[data-pi]'); if (pi) { palRows[+pi.dataset.pi].run(); closePal(); redraw(); return; }
    if (e.target.id === 'pal') { closePal(); return; }
    const el = e.target.closest('[data-act]'); if (!el || el.tagName === 'SELECT') return;
    if (el.dataset.act === 'select' && e.target.closest('.acts')) return;
    acts[el.dataset.act]?.(el.dataset, el); if (!['theme', 'palette'].includes(el.dataset.act)) redraw();
  });
  document.addEventListener('change', (e) => {
    const el = e.target.closest('select[data-act]'); if (!el) return;
    if (el.dataset.act === 'scope') S.scope = el.value;
    if (el.dataset.act === 'codex') { const c = S.codex.find((x) => x.key === el.dataset.key); const prev = c.value; c.value = el.value; toast(`${c.key} = ${c.value}`, () => { c.value = prev; }); }
    redraw();
  });
  document.addEventListener('keydown', (e) => {
    const open = $('#pal')?.classList.contains('open');
    if ((e.metaKey || e.ctrlKey) && e.key === 'k') { e.preventDefault(); open ? closePal() : openPal(); return; }
    if (open) {
      if (e.key === 'Escape') closePal();
      else if (e.key === 'ArrowDown') { e.preventDefault(); palIdx = Math.min(palIdx + 1, palRows.length - 1); palRender(doGo); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); palIdx = Math.max(palIdx - 1, 0); palRender(doGo); }
      else if (e.key === 'Enter') { e.preventDefault(); palRows[palIdx]?.run(); closePal(); redraw(); }
      return;
    }
    if (e.key === 'Enter' && document.activeElement?.matches('[data-act="select"]')) document.activeElement.click();
    page.onKey?.(e, redraw);
  });
  document.addEventListener('input', (e) => { if (e.target.id === 'pal-q') { palIdx = 0; palRender(doGo); } });
  redraw();
}
const page = { onKey: null };
