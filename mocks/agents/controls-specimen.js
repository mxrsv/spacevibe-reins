'use strict';
/* C′ mock: the specimen sheet (?specimen=1) — every button kind in every state for the chosen direction, and the four
   candidate page icon sets beside the sidebar's own set. Loads before agents-panel.js, which calls renderSpecimen(). */

const SPIN = '<span class="spin" aria-hidden="true"></span>';
const STATES = [
  { k: 'Default' }, { k: 'Hover', cls: 'is-hover' }, { k: 'Pressed', cls: 'is-active' }, { k: 'Focus', cls: 'is-focus' },
  { k: 'Selected', sel: true }, { k: 'Disabled', dis: true }, { k: 'Loading', load: true },
];
const NA = '<span class="na caption">—</span>';

const KINDS = [
  { l: 'Primary', load: true, dis: true, make: (s) => `<button class="btn primary ${s.cls ?? ''}" ${s.dis ? 'disabled' : ''}>${s.load ? SPIN : ''}${s.load ? 'Saving' : 'Review and save'}${keycap('⌘S')}</button>` },
  { l: 'Secondary', load: true, dis: true, make: (s) => `<button class="btn ${s.cls ?? ''}" ${s.dis ? 'disabled' : ''}>${s.load ? SPIN : icon('add')}Add hook${keycap('↵')}</button>` },
  { l: 'Ghost', dis: true, make: (s) => `<button class="btn ghost ${s.cls ?? ''}" ${s.dis ? 'disabled' : ''}>Discard</button>` },
  { l: 'Danger', load: true, dis: true, make: (s) => `<button class="btn danger ${s.cls ?? ''}" ${s.dis ? 'disabled' : ''}>${s.load ? SPIN : icon('trash')}Remove 1 dead</button>` },
  { l: 'Icon', load: true, dis: true, make: (s) => `<button class="btn icon ${s.cls ?? ''}" ${s.dis ? 'disabled' : ''} aria-label="Close">${s.load ? SPIN : icon('close')}</button>` },
  { l: 'Card button', sel: true, make: (s) => `<button class="facet ${s.cls ?? ''}" data-section="permissions" aria-expanded="${!!s.sel}">${icon('permissions')}<span class="row-title">Permissions</span><span class="v">11</span></button>` },
  {
    l: 'Segmented', sel: true,
    make: (s) => `<div class="seg">${['Read only', 'Workspace', 'Full'].map((o, i) => `<button aria-pressed="${s.sel ? i === 2 : i === 0}" class="${i === 1 ? s.cls ?? '' : ''}">${o}</button>`).join('')}</div>`,
  },
  {
    l: 'Verdict picker', sel: true,
    make: (s) => `<div class="seg">${[['Allow', 'ok'], ['Ask', 'warn'], ['Deny', 'bad']].map(([o, t], i) => `<button data-tone="${t}" aria-pressed="${s.sel ? i === 2 : i === 0}" class="${i === 1 ? s.cls ?? '' : ''}">${o}</button>`).join('')}</div>`,
  },
  { l: 'Chip', sel: true, make: (s) => `<button class="chip ${s.cls ?? ''}" aria-pressed="${!!s.sel}"><span class="code">opus</span><span class="c">104</span></button>` },
  { l: 'Scope picker', dis: true, make: (s) => `<button class="scope ${s.cls ?? ''}" ${s.dis ? 'disabled' : ''}>Global${icon('updown', 'i14')}</button>` },
];

function cell(kind, st) {
  if (st.sel && !kind.sel) return NA;
  if (st.dis && !kind.dis) return NA;
  if (st.load && !kind.load) return NA;
  return kind.make(st);
}

function iconRow(set, current) {
  const g = PAGE_ICONS[set];
  const strip = Object.keys(g.icons).map((k) => `<span title="${k}">${iconFrom(set, k, 'i20')}</span>`).join('');
  const sample = `<button class="facet" data-section="hooks">${iconFrom(set, 'hooks')}<span class="row-title">Hooks</span><span class="v">4</span></button>
    <button class="btn">${iconFrom(set, 'add')}Add server</button>`;
  return `<div class="set-row${set === current ? ' current' : ''}"><span style="display:flex;flex-direction:column;gap:2px"><span class="row-title">${esc(g.label)}${set === current ? ' <span class="tag ok"><i></i>on the page</span>' : ''}</span><span class="caption t3">${esc(g.license)}</span></span>
    <span class="glyphs">${strip}</span><span class="samples">${sample}</span></div>`;
}

function renderSpecimen() {
  document.documentElement.dataset.theme = state.theme;
  document.documentElement.dataset.buttons = ['a', 'b', 'c'].includes(PARAMS.get('buttons')) ? PARAMS.get('buttons') : 'a';
  app.className = 'spec';
  const rows = KINDS.map((kind) => `<tr><td class="row-title">${kind.l}</td>${STATES.map((st) => `<td>${cell(kind, st)}</td>`).join('')}</tr>`).join('');
  const nav = ['loadout', 'agents', 'activity', 'limits'].map((k) => `<span title="${k}">${navIcon(k, 'i22')}</span>`).join('');
  app.innerHTML = `<div class="spec-page">
    <section class="card">${cardHead('Buttons', { detail: 'every kind, every state, on a card' })}
      <table class="spec-table"><thead><tr><th></th>${STATES.map((s) => `<th class="label t3">${s.k}</th>`).join('')}</tr></thead><tbody>${rows}</tbody></table></section>
    <section class="card">${cardHead('Icons', { detail: 'the sidebar keeps its own set; pages use one of these' })}
      <div class="set-row nav-row"><span style="display:flex;flex-direction:column;gap:2px"><span class="row-title">Sidebar · Solar Bold Duotone</span><span class="caption t3">Navigation only</span></span><span class="glyphs">${nav}</span><span></span></div>
      ${Object.keys(PAGE_ICONS).map((set) => iconRow(set, PAGE_SET)).join('')}</section></div>`;
}
