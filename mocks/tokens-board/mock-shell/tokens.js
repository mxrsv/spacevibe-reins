/* Shared runtime for the Tokens direction mocks. Needs tokens-data.js, data.js and ui.js (for ic, esc, $). */
ICONS.x = '<path d="M6 6l12 12M18 6 6 18"/>';
ICONS.tokens = '<ellipse cx="12" cy="6.5" rx="7.5" ry="3"/><path d="M4.5 6.5v5.5c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3V6.5"/><path d="M4.5 12v5.5c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3V12"/>';
const CLIS = ['claude', 'codex'];
const KEY = { claude: 'c', codex: 'x' };
const PKEY = { claude: 'pc', codex: 'px' };
const NKEY = { claude: 'nc', codex: 'nx' };
const MEASURES = { tokens: 'All tokens', fresh: 'New only', cost: 'Est. cost' };
const byDate = new Map(TD.days.map((d) => [d.d, d]));
const lastDate = TD.days.at(-1).d;
const firstClaude = TD.days.find((d) => Object.keys(d.c).length)?.d ?? lastDate;
const firstCodex = TD.days.find((d) => Object.keys(d.x).length)?.d ?? lastDate;
const iso = (dt) => `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
const parse = (s) => new Date(`${s}T00:00:00`);
const shift = (s, n) => { const d = parse(s); d.setDate(d.getDate() + n); return iso(d); };
const dayObj = (s) => byDate.get(s) ?? { d: s, c: {}, x: {}, pc: {}, px: {}, nc: 0, nx: 0 };
const span = (from, to) => { const out = []; for (let s = from; s <= to; s = shift(s, 1)) out.push(dayObj(s)); return out; };
const short = (s) => parse(s).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
const weekday = (s) => parse(s).toLocaleDateString('en-US', { weekday: 'short' });
const dayLabel = (s) => (s === lastDate ? 'Today' : s === shift(lastDate, -1) ? 'Yesterday' : `${weekday(s)}, ${short(s)}`);
const monday = (s) => { const d = parse(s); return shift(s, -((d.getDay() + 6) % 7)); };

/* numbers */
const tk = (n) => { const a = Math.abs(n); if (a >= 1e9) return `${+(n / 1e9).toFixed(a >= 1e10 ? 1 : 2)}B`; if (a >= 1e6) return `${+(n / 1e6).toFixed(a >= 1e8 ? 0 : 1)}M`; if (a >= 1e3) return `${+(n / 1e3).toFixed(a >= 1e5 ? 0 : 1)}K`; return String(Math.round(n)); };
const usd = (n) => `~$${n >= 100 ? Math.round(n).toLocaleString('en-US') : n.toFixed(n >= 10 ? 0 : 2)}`;
const empty = () => ({ i: 0, cr: 0, cw: 0, o: 0, t: 0, fresh: 0, cost: 0, unpriced: 0 });
function addTuple(a, t) { const s = t[0] + t[1] + t[2] + t[3]; return { i: a.i + t[0], cr: a.cr + t[1], cw: a.cw + t[2], o: a.o + t[3], t: a.t + s, fresh: a.fresh + s - t[1], cost: a.cost + (t[4] ?? 0), unpriced: a.unpriced + (t[4] === null ? s : 0) }; }
/* one CLI over some days; pick narrows to a model or project */
function agg(days, cli, pick = {}) {
  let a = empty();
  for (const d of days) {
    if (pick.project !== undefined) { const t = d[PKEY[cli]][pick.project]; if (t) a = addTuple(a, t); } else if (pick.model !== undefined) { const t = d[KEY[cli]][pick.model]; if (t) a = addTuple(a, t); } else for (const t of Object.values(d[KEY[cli]])) a = addTuple(a, t);
  }
  return a;
}
const value = (a, m) => (m === 'tokens' ? a.t : m === 'fresh' ? a.fresh : a.cost);
function names(days, cli, kind) { const k = kind === 'model' ? KEY[cli] : PKEY[cli]; const s = new Set(); for (const d of days) for (const n of Object.keys(d[k])) s.add(n); return [...s]; }
const conv = (days, cli) => days.reduce((n, d) => n + d[NKEY[cli]], 0);
const pct = (v, max) => (max > 0 ? (v / max) * 100 : 0);

/* cell parts */
const fmtV = (a, m) => {
  if (m !== 'cost') return tk(value(a, m));
  if (a.t === 0) return '0';
  if (a.cost === 0 && a.unpriced > 0) return 'not measured';
  return usd(a.cost);
};
const warn = (a, m) => (m === 'cost' && a.unpriced > 0 && a.cost > 0 ? `<span class="warn-ic" title="${tk(a.unpriced)} tokens use a model with no price">${ic('alert', 12)}</span>` : '');
const tipOf = (a) => esc(`Input ${tk(a.i)}\nCache write ${tk(a.cw)}\nCache read ${tk(a.cr)}\nOutput ${tk(a.o)}\nEst. cost ${a.t && a.cost ? usd(a.cost) : 'not measured'}${a.unpriced && a.cost ? `\n${tk(a.unpriced)} tokens have no price` : ''}`);
function bar(cli, a, max, m, flip = false) {
  const fill = `${cli}-fill`;
  if (m === 'tokens') {
    const solid = a.fresh ? `<i class="${fill}" style="width:${pct(a.fresh, max)}%"></i>` : '';
    const cache = a.cr ? `<i class="${fill} faint" style="width:${pct(a.cr, max)}%"></i>` : '';
    return `<span class="b ${flip ? 'flip' : ''}">${flip ? cache + solid : solid + cache}</span>`;
  }
  const v = value(a, m);
  return `<span class="b ${flip ? 'flip' : ''}">${v ? `<i class="${fill}" style="width:${pct(v, max)}%"></i>` : ''}</span>`;
}
function cell(cli, a, max, m) {
  const isNone = a.t === 0;
  const unm = m === 'cost' && a.cost === 0 && a.unpriced > 0;
  return `<div class="c" data-tip="${tipOf(a)}">${unm ? '<span class="dim" style="font-size:12px"></span>' : bar(cli, a, max, m)}<span class="val ${isNone ? 'zero' : ''}${unm ? ' dim' : ''}" ${unm ? 'style="font-size:12px"' : ''}>${isNone ? '–' : unm ? 'no price' : fmtV(a, m)}${warn(a, m)}</span></div>`;
}
const mergeA = (a, b) => Object.fromEntries(Object.keys(a).map((k) => [k, a[k] + b[k]]));
const costCell = (a) => { const none = a.t === 0; const unm = a.cost === 0 && a.unpriced > 0; return `<div class="cost ${none || unm ? 'none' : ''}">${none ? '–' : unm ? 'not measured' : usd(a.cost)}${unm ? '' : warn(a, 'cost')}</div>`; };

/* period shapes used by the ledger and mirror */
const SERIES = { days: 'Daily, last 30 days', weeks: 'Weekly, last 12 weeks', months: 'Monthly, all time' };
function series(kind) {
  if (kind === 'days') {
    const out = []; for (let i = 0; i < 30; i++) { const s = shift(lastDate, -i); out.push({ id: s, label: dayLabel(s), spine: short(s), days: [dayObj(s)], group: monday(s) }); }
    return out;
  }
  if (kind === 'weeks') {
    const out = []; let w = monday(lastDate);
    for (let i = 0; i < 12; i++) { const end = shift(w, 6); out.push({ id: w, label: `${short(w)} – ${short(end)}`, spine: short(w), days: span(w, end > lastDate ? lastDate : end) }); w = shift(w, -7); }
    return out;
  }
  const out = []; const months = [...new Set(TD.days.map((d) => d.d.slice(0, 7)))].sort().reverse();
  for (const mo of months) { const ds = TD.days.filter((d) => d.d.startsWith(mo)); out.push({ id: mo, label: parse(`${mo}-01`).toLocaleDateString('en-US', { month: 'long', year: 'numeric' }), spine: parse(`${mo}-01`).toLocaleDateString('en-US', { month: 'short', year: '2-digit' }), days: ds }); }
  return out;
}
const groupLabel = (mon) => `${short(mon)} – ${short(shift(mon, 6))}`;

/* page runtime */
const T = { period: 'days', measure: 'tokens', q: '', sel: null, open: new Set() };
const Page = { render: null, primary: () => '', onEnter: null, periods: SERIES, placeholder: 'Filter' };
const DIRS_T = [['index.html', 'Tokens Board']];

function unpricedInView() { const days = Page.viewDays?.() ?? TD.days; let u = 0; for (const c of CLIS) u += agg(days, c).unpriced; return u; }
function footNote() {
  if (T.measure === 'tokens') return `<span class="note"><i class="lg"></i>New tokens<i class="lg faint" style="margin-left:8px"></i>Cache reads</span>`;
  if (T.measure === 'cost') return `<span class="note">${ic('alert', 13)}Estimate from the price table. ${tk(unpricedInView())} tokens here use a model with no price</span>`;
  return `<span class="note">Input, cache writes and output</span>`;
}
function mountShell() {
  const here = location.pathname.split('/').pop();
  const opt = (obj, cur) => Object.entries(obj).map(([v, l]) => `<option value="${v}" ${v === cur ? 'selected' : ''}>${l}</option>`).join('');
  document.getElementById('root').innerHTML = `<div class="app"><aside class="side"><div class="lights"><i></i><i></i><i></i></div>
    <nav class="nav" aria-label="Sections"><a href="#" style="text-decoration:none"><button>${ic('loadout')}Loadout</button></a><a href="#" style="text-decoration:none"><button>${ic('rules')}Rules</button></a><a href="#" style="text-decoration:none"><button>${ic('activity')}Activity</button></a><button aria-current="page">${ic('tokens')}Tokens</button></nav>
    <div class="side-foot tk"><div class="dirs" aria-label="Direction"><span class="cap">Mock, synthetic data</span>${DIRS_T.map(([h, l]) => `<a href="${h}" ${h === here ? 'aria-current="page"' : ''}>${l}</a>`).join('')}</div>
    <div class="foot-line"><span>${Page.shell ? '' : `Claude from ${short(firstClaude)}<br>Codex from ${short(firstCodex)}`}</span><span class="sp"></span><button class="icon-btn" id="theme" aria-label="Toggle theme">${ic('moon')}</button></div></div></aside>
    ${Page.shell ? `<main class="tk-main shellish"><div class="top"><h1>Tokens</h1><span class="sp"></span><button class="search" data-open-actions>${ic('search', 15)}<span>Search or run a command</span><kbd>⌘K</kbd></button></div><div class="tools" id="tools"></div><div id="tk-body" class="tk-body"></div><div class="hintbar" id="hints"></div><div class="acts-panel" id="acts" role="menu" aria-label="Actions"></div></main>` : `<main class="tk-main"><div class="tk-search">${ic('search', 16)}<input id="q" placeholder="${esc(Page.placeholder)}" autocomplete="off" aria-label="${esc(Page.placeholder)}">
      <select class="acc" id="period" aria-label="Period">${opt(Page.periods, T.period)}</select><select class="acc" id="measure" aria-label="Measure">${opt(MEASURES, T.measure)}</select></div>
      <div id="tk-body" class="${Page.bodyClass ?? 'tk-body'}"></div>
      <div class="tk-foot"><span class="act">${ic('tokens', 14)}<b>Tokens</b></span><span id="foot-note"></span><span class="sp"></span><span class="act" id="primary"></span><span class="divider"></span><span class="act">Actions <kbd>⌘K</kbd></span></div>
      <div class="acts-panel" id="acts" role="menu" aria-label="Actions"></div></main>`}</div><div class="tip" id="tip"></div><div class="pop" id="pop" role="dialog" aria-label="Price table"></div>`;
}
function draw() {
  const body = $('#tk-body'); const panes = [...body.querySelectorAll('.pane')].map((p) => p.scrollTop); const y = body.scrollTop;
  body.innerHTML = Page.render();
  body.scrollTop = y; [...body.querySelectorAll('.pane')].forEach((p, i) => { p.scrollTop = panes[i] ?? 0; });
  Page.drawChrome?.();
  if ($('#foot-note')) { $('#foot-note').innerHTML = footNote(); const p = Page.primary(); $('#primary').innerHTML = p ? `${esc(p)} <kbd>↵</kbd>` : ''; }
  body.querySelector('[data-nav][aria-selected="true"]')?.scrollIntoView({ block: 'nearest' });
}
function actItems() {
  const items = [];
  if (Page.actions) items.push(...Page.actions());
  Object.entries(Page.periods).forEach(([v, l]) => items.push({ g: 'Period', label: l, on: T.period === v, run: () => { setPeriod(v); } }));
  Object.entries(MEASURES).forEach(([v, l]) => items.push({ g: 'Measure', label: l, on: T.measure === v, run: () => { T.measure = v; if ($('#measure')) $('#measure').value = v; } }));
  return items;
}
let actIdx = 0;
function drawActs() { let g = ''; const its = actItems(); actIdx = Math.min(actIdx, its.length - 1); $('#acts').innerHTML = its.map((a, i) => { const h = a.g !== g ? `<div class="h">${a.g}</div>` : ''; g = a.g; return `${h}<button role="menuitem" data-ai="${i}" aria-selected="${i === actIdx}"><span>${esc(a.label)}</span>${a.on ? ic('check', 14) : ''}</button>`; }).join(''); }
const toggleActs = (open) => { const el = $('#acts'); const on = open ?? !el.classList.contains('open'); el.classList.toggle('open', on); if (on) { actIdx = 0; drawActs(); } else $('#q')?.focus(); };
function setPeriod(v) { T.period = v; T.sel = null; T.open = new Set(); if ($('#period')) $('#period').value = v; Page.onPeriod?.(); }
function start() {
  mountShell(); Page.onPeriod?.(); draw(); $('#q')?.focus();
  document.addEventListener('input', (e) => { if (e.target.id === 'q') { T.q = e.target.value.trim().toLowerCase(); Page.onFilter?.(); draw(); } });
  document.addEventListener('change', (e) => { if (e.target.id === 'period') { setPeriod(e.target.value); draw(); } if (e.target.id === 'measure') { T.measure = e.target.value; draw(); } });
  document.addEventListener('click', (e) => {
    if (e.target.closest('#theme')) { const d = document.documentElement.dataset; d.theme = d.theme === 'light' ? 'dark' : 'light'; return; }
    const ai = e.target.closest('[data-ai]'); if (ai) { actItems()[+ai.dataset.ai].run(); toggleActs(false); draw(); return; }
    if (!e.target.closest('#acts')) $('#acts').classList.remove('open');
    if (e.target.closest('[data-noselect]')) return;
    const r = e.target.closest('[data-nav]'); if (r) { const same = T.sel === r.dataset.nav; T.sel = r.dataset.nav; Page.onClick?.(r.dataset.nav, same); draw(); }
  });
  document.addEventListener('keydown', (e) => {
    const open = $('#acts').classList.contains('open');
    if ((e.metaKey || e.ctrlKey) && e.key === 'k') { e.preventDefault(); toggleActs(); return; }
    if (open) {
      const its = actItems();
      if (e.key === 'Escape') toggleActs(false);
      else if (e.key === 'ArrowDown') { e.preventDefault(); actIdx = Math.min(actIdx + 1, its.length - 1); drawActs(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); actIdx = Math.max(actIdx - 1, 0); drawActs(); }
      else if (e.key === 'Enter') { e.preventDefault(); its[actIdx].run(); toggleActs(false); draw(); }
      return;
    }
    if (e.target.tagName === 'SELECT') return;
    if (e.key === 'Escape') { if ($('#q')) $('#q').value = ''; T.q = ''; Page.onFilter?.(); Page.onEscape?.(); draw(); return; }
    const horiz = Page.horizontal && !T.q && (e.key === 'ArrowLeft' || e.key === 'ArrowRight');
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || horiz) {
      e.preventDefault();
      const ids = [...new Set([...$('#tk-body').querySelectorAll('[data-nav]')].map((n) => n.dataset.nav))]; if (!ids.length) return;
      const fwd = e.key === 'ArrowDown' || e.key === 'ArrowRight';
      const i = ids.indexOf(T.sel); const n = i < 0 ? (fwd ? 0 : ids.length - 1) : fwd ? Math.min(i + 1, ids.length - 1) : Math.max(i - 1, 0);
      T.sel = ids[n < 0 ? 0 : n]; Page.onMove?.(); draw(); return;
    }
    if (e.key === 'Enter' && T.sel) { e.preventDefault(); Page.onEnter?.(T.sel); draw(); }
  });
  const tip = $('#tip');
  document.addEventListener('mousemove', (e) => { const t = e.target.closest?.('[data-tip]'); if (!t) { tip.style.display = 'none'; return; } tip.textContent = t.dataset.tip; tip.style.display = 'block'; const w = tip.offsetWidth; tip.style.left = `${Math.min(e.clientX + 12, innerWidth - w - 8)}px`; tip.style.top = `${e.clientY + 14}px`; });
}

/* shared card pieces */
const RANGE_NAME = { days: 'Last 30 days', weeks: 'Last 12 weeks', months: 'All time' };
const ROW_NAME = { days: 'Days', weeks: 'Weeks', months: 'Months' };
const cliHead = (cli) => `<span class="h"><span class="dot ${cli}"></span>${CLI[cli]}</span>`;
function ranked(days, cli, kind, m) { return names(days, cli, kind).map((n) => [n, agg(days, cli, kind === 'model' ? { model: n } : { project: n })]).filter(([, a]) => a.t).sort((x, y) => value(y[1], m) - value(x[1], m) || y[1].t - x[1].t); }
const rankItems = (days, cli, kind, m, limit = 5) => ranked(days, cli, kind, m).slice(0, limit).map(([n, a]) => `<li><span>${esc(n)}</span><span>${m === 'cost' && !a.cost ? '<span class="dim">no price</span>' : fmtV(a, m)}</span></li>`).join('') || '<li><span class="dim">No data</span></li>';
