'use strict';
/* C′ mock: state, the window shell, overlays and every action. Loads after agents-panel-data.js and agents-panel-views.js. */

/* UI state */
const store = (() => { try { return JSON.parse(localStorage.getItem('reins-cprime') || '{}'); } catch { return {}; } })();
const state = {
  theme: PARAMS.get('theme') || store.theme || 'dark',
  widths: store.widths || { normal: 480, advanced: 720 },
  scope: { claude: 'global', codex: 'global' },
  open: null, // { agent, section, file? } file = an imported instruction file
  draft: null, base: null,
  rulesMode: 'preview',
  form: {}, adding: null, expanded: new Set(),
  confirm: null, ask: null, toast: null, history: [],
};
const persist = () => localStorage.setItem('reins-cprime', JSON.stringify({ theme: state.theme, widths: state.widths }));

/* Scope helpers */
function scopesFor(agent, section) {
  const kinds = SCOPES[agent][section];
  const out = [{ key: 'global', label: agent === 'claude' && section === 'mcp' ? 'User' : 'Global' }];
  for (const kind of kinds.filter((k) => k !== 'global')) for (const p of PROJECTS) out.push({ key: `${kind}:${p}`, label: kind === 'local' ? `${p} · Local` : p, kind, project: p });
  return out;
}
function currentScope(agent, section) {
  const want = state.scope[agent];
  return scopesFor(agent, section).some((s) => s.key === want) ? want : 'global';
}
const scopeLabel = (agent, section, key) => scopesFor(agent, section).find((s) => s.key === key)?.label ?? 'Global';
function filePath(agent, section, scope) {
  const [kind, p] = scope.split(':');
  if (agent === 'claude') {
    if (section === 'rules') return kind === 'global' ? '~/.claude/CLAUDE.md' : kind === 'project' ? `${p}/CLAUDE.md` : `${p}/CLAUDE.local.md`;
    if (section === 'mcp') return kind === 'project' ? `${p}/.mcp.json` : '~/.claude.json';
    return kind === 'global' ? '~/.claude/settings.json' : kind === 'project' ? `${p}/.claude/settings.json` : `${p}/.claude/settings.local.json`;
  }
  if (section === 'rules') return kind === 'global' ? '~/.codex/AGENTS.md' : `${p}/AGENTS.md`;
  if (section === 'hooks') return '~/.codex/hooks.json';
  return '~/.codex/config.toml';
}
const fileName = (path) => path.split('/').pop();

/* What the card shows, always at Global */
function facetValue(agent, section) {
  const v = readSaved(agent, section, 'global');
  if (section === 'rules') return { text: agent === 'claude' ? 'CLAUDE.md' : 'AGENTS.md', code: true };
  if (section === 'permissions') return agent === 'claude' ? { text: v.rules.length } : { text: SANDBOX.find((o) => o.v === v.sandbox).l, warn: v.sandbox === 'danger-full-access' };
  if (section === 'hooks') { const dead = v.filter((h) => h.dead).length; return { text: v.length, dead }; }
  if (section === 'mcp') return { text: v.length };
  if (section === 'model') return { text: v.model ?? 'default', code: true };
  return null;
}
function summary(agent) {
  if (agent === 'claude') {
    const v = readSaved('claude', 'permissions', 'global');
    const ask = v.rules.filter((r) => r.v === 'ask').length, deny = v.rules.filter((r) => r.v === 'deny').length;
    if (v.mode === 'bypassPermissions') return { text: 'Runs every tool without asking', warn: true };
    return { text: `${MODES.find((m) => m.v === v.mode).d.replace(/\.$/, '')} · ${ask} ask rules · ${deny} deny rules` };
  }
  const s = codexStatus(readSaved('codex', 'permissions', 'global'));
  return { text: s.sentence, warn: s.warn };
}
function codexStatus(v) {
  const s = { 'read-only': 'Reads only', 'workspace-write': 'Writes only inside the workspace', 'danger-full-access': 'Can write anywhere' }[v.sandbox];
  const a = { untrusted: 'asks before commands it does not trust', 'on-request': 'asks when it needs more', never: 'never asks' }[v.approval];
  return { sentence: `${s} and ${a}`, warn: v.sandbox === 'danger-full-access' || v.approval === 'never', code: `sandbox_mode = "${v.sandbox}" · approval_policy = "${v.approval}"` };
}

/* ---------- Rendering: shell ---------- */
const app = document.getElementById('app');
const overlay = document.getElementById('overlay');

function render() {
  document.documentElement.dataset.theme = state.theme;
  document.documentElement.dataset.buttons = ['a', 'b', 'c'].includes(PARAMS.get('buttons')) ? PARAMS.get('buttons') : 'a';
  app.classList.toggle('open', !!state.open);
  app.style.setProperty('--pw', `${panelWidth()}px`);
  app.innerHTML = sidebar() + main() + `<aside class="panel" id="panel" aria-label="${state.open ? esc(panelTitle()) : ''}">${state.open ? panel() : ''}</aside>`;
  renderOverlay();
}
const panelWidth = () => Math.max(WIDTH.min, Math.min(state.open?.section === 'advanced' ? state.widths.advanced : state.widths.normal, innerWidth - 232 - CARDS_MIN));
addEventListener('resize', () => { if (state.open) app.style.setProperty('--pw', `${panelWidth()}px`); });
const panelTitle = () => `${CLI[state.open.agent].name} ${SECTIONS[state.open.section].title}`;

function sidebar() {
  const item = (id, title, ic, count, alert, current) => `<button class="nav-item" data-act="nav" data-id="${id}" ${current ? 'aria-current="page"' : ''}>${navIcon(ic, 'i22')}<span class="title">${title}</span>${count != null ? `<span class="num${alert ? ' alert' : ''}">${count}</span>` : ''}</button>`;
  const tile = (cls, name, line, img) => `<div class="limit-tile">${img ? `<span class="mark sm" style="background:var(--raised)"><img src="assets/gemini.svg" alt="" width="14" height="14"></span>` : `<span class="mark sm ${cls}"><i></i></span>`}<span style="display:flex;flex-direction:column;min-width:0"><span class="row-title">${name}</span><span class="caption t3">${line}</span></span></div>`;
  return `<nav class="sidebar" aria-label="Reins"><div class="traffic" aria-hidden="true"><i></i><i></i><i></i></div>
    <div class="nav">${item('loadout', 'Loadout', 'loadout', 18)}${item('agents', 'Agents', 'agents', null, false, true)}${item('activity', 'Activity', 'activity', 2, true)}${item('limits', 'Limits', 'limits')}</div>
    <div class="limits">${tile('cli-claude', 'Claude Code', '64% left · resets in 3 h')}${tile('cli-codex', 'Codex', '81% left · resets Monday')}${tile('', 'Gemini CLI', 'not measured', true)}</div>
    <div class="side-foot"><button class="btn icon" data-act="toast" data-msg="Settings is not part of this mock" aria-label="Settings">${navIcon('settings')}</button><button class="btn icon" data-act="theme" aria-label="Switch to the ${state.theme === 'dark' ? 'light' : 'dark'} theme">${navIcon(state.theme === 'dark' ? 'sun' : 'moon')}</button></div></nav>`;
}

function main() {
  const hints = state.open
    ? [['Esc', 'Close panel'], ...(isDirty() ? [['⌘S', 'Review and save']] : []), ['⌘K', 'Search or run']]
    : [['⌘K', 'Search or run'], ['Tab', 'Next button'], ['Return', 'Open']];
  return `<section class="main"><header class="topbar"><h1 class="title" style="margin:0">Agents</h1>
    <button class="search" data-act="toast" data-msg="The ⌘K palette is not part of this mock">${icon('search')}<span class="body">Search or run a command</span><span class="kbd">⌘K</span></button></header>
    <div class="content">${agentCard('claude')}${agentCard('codex')}</div>
    <footer class="hintbar caption">${hints.map(([k, l]) => `<span class="hint"><span class="kbd">${k}</span>${l}</span>`).join('')}</footer></section>`;
}

function agentCard(agent) {
  const s = summary(agent);
  const isOpen = (sec) => state.open?.agent === agent && state.open.section === sec;
  const facet = (sec) => {
    const v = facetValue(agent, sec);
    const val = sec === 'hooks' && v.dead ? `${v.text} · <span class="bad">${v.dead} dead</span>` : esc(v.text);
    return `<button class="facet" data-act="open" data-agent="${agent}" data-section="${sec}" aria-expanded="${isOpen(sec)}" aria-controls="panel">${icon(SECTIONS[sec].icon)}<span class="row-title">${SECTIONS[sec].title}</span><span class="v${v.code ? ' code' : ''}${v.warn ? ' warn' : ''}">${val}</span></button>`;
  };
  return `<article class="agent" aria-label="${CLI[agent].name}"><div class="agent-head"><span class="mark cli-${agent}"><i></i></span>
    <div class="who"><h2 class="title" style="margin:0">${CLI[agent].name}</h2><p class="body ${s.warn ? 'warn' : 't2'}" style="margin:0">${esc(s.text)}</p></div>
    <span class="path code">${CLI[agent].root}</span></div>
    <div class="facets">${FACETS.map(facet).join('')}<button class="facet ghost" data-act="open" data-agent="${agent}" data-section="advanced" aria-expanded="${isOpen('advanced')}" aria-controls="panel">${icon('advanced')}<span class="row-title">Advanced</span></button></div></article>`;
}

/* ---------- Overlays ---------- */
function renderOverlay() {
  let html = '';
  if (state.confirm) {
    const c = state.confirm;
    const lines = c.lines.map((l) => `<div class="ln"><span class="label t3" style="width:56px">${l.op}</span>${l.from?.tag ? `<span class="tag ${l.from.tag.tone}"><i></i>${l.from.tag.l}</span>${icon('arrowRight', 'i14')}` : ''}${l.tag ? `<span class="tag ${l.tag.tone}"><i></i>${l.tag.l}</span>` : ''}<span class="code-body trunc" title="${esc(l.text)}">${esc(l.text)}</span></div>`).join('');
    const warns = c.lines.filter((l) => l.warn).map((l) => `<div class="warn-note">${icon('warning', 'i20')}<span class="body">${esc(l.warn)}</span></div>`).join('');
    html += `<div class="scrim" data-act="cancel-confirm"><div class="dialog" role="dialog" aria-modal="true" aria-labelledby="dtitle" data-stop>
      <div><h2 class="title" id="dtitle">${esc(c.title)}</h2><p class="body t2" style="margin:4px 0 0">${esc(c.message)}</p></div>
      ${lines ? `<div class="box">${lines}</div>` : ''}${warns}${c.extra ? `<p class="caption t3" style="margin:0">${esc(c.extra)}</p>` : ''}
      <div class="actions"><button class="btn" data-act="cancel-confirm">Cancel${keycap('Esc')}</button><button class="btn primary" data-act="do-confirm" id="dconfirm">${esc(c.action)}${keycap('↵')}</button></div></div></div>`;
  }
  if (state.toast) html += `<div class="toast" role="status"><span class="body">${esc(state.toast.text)}</span>${state.toast.undo ? `<button class="btn" data-act="undo">${icon('undo')}Undo</button>` : ''}</div>`;
  overlay.innerHTML = html;
  if (state.confirm) document.getElementById('dconfirm')?.focus();
}
let toastTimer;
function toast(text, undo = false) {
  state.toast = { text, undo };
  renderOverlay();
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { state.toast = null; renderOverlay(); }, 6000);
}

let menuEl = null;
function closeMenu() { menuEl?.remove(); menuEl = null; }
function openMenu(anchor, items, onPick) {
  closeMenu();
  menuEl = document.createElement('div');
  menuEl.className = 'menu';
  menuEl.setAttribute('role', 'menu');
  menuEl.innerHTML = items.map((it, i) => it.sep ? '<div class="sep"></div>' : it.head ? `<div class="head label">${esc(it.head)}</div>`
    : `<button role="menuitemradio" aria-checked="${!!it.checked}" data-i="${i}" class="body${it.danger ? ' bad' : ''}"><span class="ck">${it.checked ? icon('check', 'i14') : ''}</span>${it.tone ? `<span class="tag ${it.tone}" style="background:none;padding:0"><i></i></span>` : ''}${esc(it.label)}</button>`).join('');
  document.body.appendChild(menuEl);
  const r = anchor.getBoundingClientRect(), m = menuEl.getBoundingClientRect();
  menuEl.style.left = `${Math.min(r.left, innerWidth - m.width - 8)}px`;
  menuEl.style.top = `${r.bottom + m.height + 4 > innerHeight ? r.top - m.height - 4 : r.bottom + 4}px`;
  menuEl.addEventListener('click', (e) => { const b = e.target.closest('button[data-i]'); if (!b) return; const it = items[+b.dataset.i]; closeMenu(); onPick(it); anchor.focus(); });
  menuEl.querySelector('button')?.focus();
}

/* ---------- Actions ---------- */
function openPanel(agent, section, file = null) {
  const scope = currentScope(agent, section);
  state.open = { agent, section, file };
  const base = file ? (IMPORTS[file.path] ?? '') : readSaved(agent, section, scope);
  state.base = clone(base); state.draft = clone(base);
  state.form = {}; state.adding = null; state.expanded = new Set(); state.ask = null;
  if (section === 'rules' && !file) state.rulesMode = 'preview';
  render();
  document.getElementById('ptitle')?.focus();
}
let pending = null;
function guard(next) {
  if (isDirty()) { pending = next; state.ask = true; refreshFooter(); document.querySelector('#pfoot [data-act=keep]')?.focus(); return; }
  next();
}
function closePanel() {
  const back = state.open && document.querySelector(`.facet[data-agent="${state.open.agent}"][data-section="${state.open.section}"]`);
  const sel = back ? `.facet[data-agent="${back.dataset.agent}"][data-section="${back.dataset.section}"]` : null;
  state.open = null; state.ask = null; render();
  if (sel) document.querySelector(sel)?.focus();
}
function edit(fn) { state.draft = fn(clone(state.draft)) ?? state.draft; rerenderPanel(); }
function rerenderPanel() {
  const body = document.getElementById('pbody');
  const top = body?.scrollTop ?? 0;
  render();
  const nb = document.getElementById('pbody'); if (nb) nb.scrollTop = top;
}
function refreshFooter() { const f = document.getElementById('pfoot'); if (f) f.outerHTML = footer(); }

function review() {
  const ch = changes();
  if (!ch.length) return;
  const { agent, section } = state.open;
  const scope = currentScope(agent, section);
  const path = state.open.file?.path ?? filePath(agent, section, scope);
  const paths = section === 'permissions' && agent === 'codex' && ch.some((c) => c.tag) ? `${path} and ~/.codex/rules/default.rules` : path;
  state.confirm = {
    title: `Save ${plural(ch.length, 'change')}?`,
    message: `Writes to ${state.open.file ? 'an imported file' : scopeLabel(agent, section, scope)}: ${paths}. Reins keeps a copy you can restore.`,
    lines: ch, action: 'Save',
    extra: agent === 'claude' && section === 'mcp' && !scope.startsWith('project') ? 'Claude Code also writes ~/.claude.json. Reins reads it again just before saving and applies only these changes.' : '',
    run: () => {
      const key = state.open.file ? `file:${path}` : keyOf(agent, section, scope);
      const prev = state.open.file ? IMPORTS[path] : (key in saved ? clone(saved[key]) : undefined);
      state.history.push({ key, prev, path });
      const value = clone(state.draft);
      if (section === 'mcp') for (const m of value) for (const s of m.secrets) delete s.replaced;
      if (state.open.file) IMPORTS[path] = value; else saved[key] = value;
      state.base = clone(value); state.draft = clone(value);
      state.form = {}; state.adding = null;
      render();
      toast(`Saved to ${path}`, true);
    },
  };
  renderOverlay();
}
function undo() {
  const h = state.history.pop();
  if (!h) return;
  if (h.key.startsWith('file:')) IMPORTS[h.path] = h.prev; else if (h.prev === undefined) delete saved[h.key]; else saved[h.key] = h.prev;
  if (state.open) { const { agent, section, file } = state.open; openPanel(agent, section, file); }
  else render();
  toast(`Restored the copy of ${fileName(h.path)}`);
}

function addRule() {
  const p = (state.form.rule ?? '').trim();
  const v = state.form.newVerdict ?? 'allow';
  const err = !/^[A-Za-z][\w-]*(\(.+\))?$/.test(p) ? 'Write a tool name, optionally with a pattern in brackets: Bash(git push:*)'
    : state.draft.rules.some((r) => r.p === p) ? `${p} is already in ${VERDICT[state.draft.rules.find((r) => r.p === p).v].l}.` : null;
  if (err) { state.form['rule:err'] = err; return rerenderPanel(); }
  state.form = { ...state.form, rule: '', 'rule:err': null };
  edit((d) => { d.rules.push({ p, v }); return d; });
  document.querySelector('[data-in=rule]')?.focus();
}
function addCmd() {
  const p = (state.form.cmd ?? '').trim().replace(/\s+/g, ' ');
  const err = state.draft.rules.some((r) => r.p === p) ? `${p} already has a rule.` : null;
  if (err) { state.form['cmd:err'] = err; return rerenderPanel(); }
  state.form = { ...state.form, cmd: '', 'cmd:err': null };
  edit((d) => { d.rules.push({ p, d: state.form.newDecision ?? 'prompt' }); return d; });
}

const SEG = {
  'rules-mode': (v) => { state.rulesMode = v; rerenderPanel(); if (v === 'edit') document.querySelector('[data-in=text]')?.focus(); },
  mode: (v) => edit((d) => { d.mode = v || null; return d; }),
  'new-verdict': (v) => { state.form.newVerdict = v; rerenderPanel(); },
  'new-decision': (v) => { state.form.newDecision = v; rerenderPanel(); },
  approval: (v) => edit((d) => { d.approval = v; return d; }),
  sandbox: (v) => edit((d) => { d.sandbox = v; return d; }),
  trust: (v) => edit((d) => { d.trust = v || null; return d; }),
  effort: (v) => edit((d) => { d.effort = v; return d; }),
  'mcp-type': (v) => { state.form.mcpType = v; rerenderPanel(); },
};

const ACTIONS = {
  nav: (b) => { if (b.dataset.id !== 'agents') toast(`${b.textContent.replace(/\d+/g, '').trim()} is not part of this mock`); },
  toast: (b) => toast(b.dataset.msg),
  theme: () => { state.theme = state.theme === 'dark' ? 'light' : 'dark'; persist(); render(); },
  open: (b) => {
    const { agent, section } = b.dataset;
    if (state.open?.agent === agent && state.open.section === section && !state.open.file) return guard(closePanel);
    guard(() => openPanel(agent, section));
  },
  close: () => guard(closePanel),
  keep: () => { state.ask = null; pending = null; refreshFooter(); },
  discard: () => {
    state.draft = clone(state.base); state.form = {}; state.adding = null;
    const next = pending; pending = null; state.ask = null;
    if (next) next(); else rerenderPanel();
  },
  review,
  'cancel-confirm': (b, e) => { if (e.target.closest('[data-stop]') && b.classList.contains('scrim')) return; state.confirm = null; renderOverlay(); },
  'do-confirm': () => { const c = state.confirm; state.confirm = null; c.run(); },
  undo,
  'scope-menu': (b) => {
    const { agent, section } = state.open;
    const cur = currentScope(agent, section);
    const items = []; let lastKind = 'global';
    for (const s of scopesFor(agent, section)) {
      const kind = s.kind ?? 'global';
      if (kind !== lastKind) { items.push({ sep: true }, { head: kind === 'project' ? 'Project' : 'Local, only you' }); lastKind = kind; }
      items.push({ label: s.label.replace(' · Local', ''), value: s.key, checked: s.key === cur });
    }
    openMenu(b, items, (it) => guard(() => { state.scope[agent] = it.value; openPanel(agent, section); }));
  },
  'go-scope': (b) => guard(() => { state.scope[state.open.agent] = b.dataset.scope; openPanel(state.open.agent, state.open.section); }),
  seg: (b) => SEG[b.dataset.name]?.(b.dataset.v === '' ? null : b.dataset.v),
  'verdict-menu': (b) => {
    const p = b.dataset.p, cur = state.draft.rules.find((r) => r.p === p).v;
    openMenu(b, [...Object.entries(VERDICT).map(([v, o]) => ({ label: o.l, value: v, tone: o.tone, checked: v === cur })), { sep: true }, { label: 'Remove', value: 'remove', danger: true }],
      (it) => edit((d) => { d.rules = it.value === 'remove' ? d.rules.filter((r) => r.p !== p) : d.rules.map((r) => (r.p === p ? { ...r, v: it.value } : r)); return d; }));
  },
  'decision-menu': (b) => {
    const p = b.dataset.p, cur = state.draft.rules.find((r) => r.p === p).d;
    openMenu(b, [...Object.entries(DECISION).map(([v, o]) => ({ label: o.l, value: v, tone: o.tone, checked: v === cur })), { sep: true }, { label: 'Remove', value: 'remove', danger: true }],
      (it) => edit((d) => { d.rules = it.value === 'remove' ? d.rules.filter((r) => r.p !== p) : d.rules.map((r) => (r.p === p ? { ...r, d: it.value } : r)); return d; }));
  },
  'mode-menu': (b) => {
    const inherit = currentScope('claude', 'permissions') !== 'global';
    const opts = inherit ? [{ v: null, l: 'Same as Global' }, ...MODES] : MODES;
    openMenu(b, opts.map((o) => ({ label: o.l, value: o.v, tone: o.warn ? 'warn' : null, checked: o.v === state.draft.mode })), (it) => edit((d) => { d.mode = it.value; return d; }));
  },
  'rm-rule': (b) => edit((d) => { d.rules = d.rules.filter((r) => r.p !== b.dataset.p); return d; }),
  'add-rule': addRule,
  'add-dir': () => { const p = state.form.dir.trim(); state.form.dir = ''; edit((d) => { if (!d.dirs.includes(p)) d.dirs.push(p); return d; }); },
  'rm-dir': (b) => edit((d) => { d.dirs = d.dirs.filter((p) => p !== b.dataset.p); return d; }),
  network: () => edit((d) => { d.network = !d.network; return d; }),
  'add-root': () => { const p = state.form.root.trim(); state.form.root = ''; edit((d) => { if (!d.roots.includes(p)) d.roots.push(p); return d; }); },
  'rm-root': (b) => edit((d) => { d.roots = d.roots.filter((p) => p !== b.dataset.p); return d; }),
  'add-cmd': addCmd,
  'rm-cmd': (b) => edit((d) => { d.rules = d.rules.filter((r) => r.p !== b.dataset.p); return d; }),
  'toggle-add': (b) => { state.adding = state.adding === b.dataset.what ? null : b.dataset.what; rerenderPanel(); document.querySelector(state.adding === 'hook' ? '[data-in=matcher]' : '[data-in=mcpName]')?.focus(); },
  'event-menu': (b) => openMenu(b, EVENTS[state.open.agent].map((ev) => ({ label: ev, value: ev, checked: ev === (state.form.event ?? EVENTS[state.open.agent][0]) })), (it) => { state.form.event = it.value; rerenderPanel(); }),
  'add-hook': () => {
    const h = { id: `n${Date.now()}`, event: state.form.event ?? EVENTS[state.open.agent][0], matcher: (state.form.matcher ?? '').trim(), cmd: state.form.command.trim(), runs: state.open.agent === 'codex' ? null : 0 };
    state.form = {}; state.adding = null;
    edit((d) => { d.push(h); return d; });
  },
  'rm-hook': (b) => edit((d) => d.filter((h) => h.id !== b.dataset.id)),
  'rm-dead': () => edit((d) => d.filter((h) => !h.dead)),
  'copy-hook': (b) => {
    const { agent } = state.open, other = CLI[agent].other;
    const h = state.draft.find((x) => x.id === b.dataset.id);
    const target = readSaved(other, 'hooks', 'global');
    const known = EVENTS[other].includes(h.event);
    state.confirm = {
      title: `Copy this hook to ${CLI[other].name}?`, message: `Writes to ${filePath(other, 'hooks', 'global')}. Reins keeps a copy you can restore.`,
      lines: [{ op: 'Add', text: `${h.event}${h.matcher ? ` · ${h.matcher}` : ''}: ${h.cmd}` }], action: 'Copy',
      extra: known ? `${CLI[other].name} names its tools differently, so check the matcher after copying.` : `${CLI[other].name} has no ${h.event} event.`,
      run: () => {
        const key = keyOf(other, 'hooks', 'global');
        state.history.push({ key, prev: key in saved ? clone(saved[key]) : undefined, path: filePath(other, 'hooks', 'global') });
        saved[key] = [...target, { ...h, id: `c${Date.now()}`, runs: other === 'codex' ? null : 0, errors: 0, dead: false }];
        render(); toast(`Copied to ${CLI[other].name}`, true);
      },
    };
    renderOverlay();
  },
  expand: (b) => { const n = b.dataset.name; state.expanded.has(n) ? state.expanded.delete(n) : state.expanded.add(n); rerenderPanel(); },
  'replace-secret': (b) => { state.form[`${b.dataset.f}:open`] = true; rerenderPanel(); document.querySelector(`[data-in="${b.dataset.f}"]`)?.focus(); },
  'set-secret': (b) => {
    const f = `secret:${b.dataset.mcp}:${b.dataset.k}`;
    if (!(state.form[f] ?? '').length) return;
    state.form = { ...state.form, [f]: '', [`${f}:open`]: false };
    edit((d) => { d.find((m) => m.name === b.dataset.mcp).secrets.find((s) => s.k === b.dataset.k).replaced = true; return d; });
  },
  'add-mcp': () => {
    const name = (state.form.mcpName ?? '').trim() || 'server';
    const m = { name, type: state.form.mcpType ?? 'stdio', target: state.form.mcpTarget.trim(), secrets: [] };
    state.form = {}; state.adding = null;
    edit((d) => { d.push(m); return d; });
  },
  'rm-mcp': (b) => edit((d) => d.filter((m) => m.name !== b.dataset.name)),
  'pick-model': (b) => edit((d) => { d.model = b.dataset.m; return d; }),
  'open-import': (b) => { const { agent, section } = state.open; guard(() => openPanel(agent, section, { path: b.dataset.path })); },
  'back-file': () => { const { agent, section } = state.open; guard(() => openPanel(agent, section)); },
};

document.addEventListener('click', (e) => {
  if (menuEl && !menuEl.contains(e.target)) closeMenu();
  const b = e.target.closest('[data-act]');
  if (!b || b.disabled) return;
  if (b.classList.contains('scrim') && e.target !== b) return;
  ACTIONS[b.dataset.act]?.(b, e);
});

document.addEventListener('input', (e) => {
  const name = e.target.dataset.in;
  if (!name) return;
  if (name === 'text') {
    state.draft = e.target.value;
    if (state.open.section === 'advanced') {
      const g = document.getElementById('gutter'); const n = state.draft.split('\n').length;
      if (g && g.childElementCount + 1 !== n) g.innerHTML = Array.from({ length: n }, (_, i) => i + 1).join('<br>');
      document.getElementById('status').innerHTML = statusLine(state.open.agent);
    }
    refreshFooter(); refreshHints();
    return;
  }
  if (name === 'model') { state.draft = { ...state.draft, model: e.target.value.trim() || null }; refreshFooter(); refreshHints(); document.querySelectorAll('[data-act=pick-model]').forEach((c) => c.setAttribute('aria-pressed', c.dataset.m === state.draft.model)); return; }
  state.form[name] = e.target.value;
  if (state.form[`${name}:err`]) { state.form[`${name}:err`] = null; e.target.parentElement.classList.remove('err'); e.target.closest('.card')?.querySelector('.err-line')?.remove(); }
  document.querySelectorAll(`[data-add-for="${name}"]`).forEach((btn) => { btn.disabled = !e.target.value.trim(); });
});
function refreshHints() { const h = document.querySelector('.hintbar'); if (h) h.outerHTML = main().match(/<footer[\s\S]*<\/footer>/)[0]; }

document.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && e.target.dataset?.in) {
    const add = { rule: 'add-rule', cmd: 'add-cmd', dir: 'add-dir', root: 'add-root', command: 'add-hook', mcpTarget: 'add-mcp' }[e.target.dataset.in];
    if (add && e.target.value.trim()) { e.preventDefault(); ACTIONS[add](); }
    if (e.target.dataset.in.startsWith('secret:')) { e.preventDefault(); const [, mcp, k] = e.target.dataset.in.split(':'); ACTIONS['set-secret']({ dataset: { mcp, k } }); }
  }
  if ((e.metaKey || e.ctrlKey) && e.key === 's') { e.preventDefault(); if (isDirty()) review(); }
  if (e.key === 'Tab' && e.target.tagName === 'TEXTAREA') {
    e.preventDefault(); const t = e.target, s = t.selectionStart;
    t.setRangeText('  ', s, t.selectionEnd, 'end'); t.dispatchEvent(new Event('input', { bubbles: true }));
  }
  if (e.key === 'Escape') {
    if (menuEl) { closeMenu(); return; }
    if (state.confirm) { state.confirm = null; renderOverlay(); return; }
    if (state.ask) { ACTIONS.keep(); return; }
    if (state.open) { e.preventDefault(); guard(closePanel); }
  }
  if (e.target.dataset?.grip !== undefined && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) { resizeBy(e.key === 'ArrowLeft' ? 16 : -16); e.preventDefault(); }
});
document.addEventListener('scroll', (e) => { if (e.target.tagName === 'TEXTAREA') { const g = document.getElementById('gutter'); if (g) g.scrollTop = e.target.scrollTop; } }, true);

/* Panel resizing: drag the left edge or use the arrow keys on it */
function setWidth(w) {
  const k = state.open?.section === 'advanced' ? 'advanced' : 'normal';
  const max = Math.min(WIDTH.max, innerWidth - 232 - CARDS_MIN);
  state.widths = { ...state.widths, [k]: Math.round(Math.max(WIDTH.min, Math.min(max, w))) };
  app.style.setProperty('--pw', `${state.widths[k]}px`);
}
function resizeBy(dx) { setWidth(panelWidth() + dx); persist(); }
document.addEventListener('pointerdown', (e) => {
  if (e.target.dataset?.grip === undefined) return;
  e.preventDefault();
  app.classList.add('resizing');
  const move = (ev) => setWidth(innerWidth - ev.clientX);
  const up = () => { app.classList.remove('resizing'); removeEventListener('pointermove', move); removeEventListener('pointerup', up); persist(); };
  addEventListener('pointermove', move); addEventListener('pointerup', up);
});

/* Deep link for screenshots: #open=claude/permissions */
const deep = /open=(\w+)\/(\w+)/.exec(location.hash);
if (PARAMS.get('specimen')) renderSpecimen();
else {
  render();
  if (deep && CLI[deep[1]] && SECTIONS[deep[2]]) openPanel(deep[1], deep[2]);
}
