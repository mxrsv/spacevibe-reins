import { CLI_LABEL, h, icon, ms, num, shortDate } from './dom.js';

export const TABS = [
  ['skill', 'Skills', 'skill'],
  ['agent', 'Agents', 'agent'],
  ['hook', 'Hooks', 'hook'],
  ['history', 'History', 'history'],
];

const PRESETS = [
  { label: 'Notify when the agent stops', event: 'Stop', matcher: '', command: `osascript -e 'display notification "Agent finished" with title "Reins"'` },
  { label: 'Format a file after each edit', event: 'PostToolUse', matcher: 'Edit|Write', command: `jq -r '.tool_input.file_path // empty' | xargs -I {} prettier --write --ignore-unknown {}` },
];

export function hookLabel(hook) {
  const script = hook.paths.at(-1) ?? /[\w.-]+\.(?:sh|js|mjs|cjs|py|ts)\b/.exec(hook.command)?.[0];
  if (script) return script.split('/').pop();
  return hook.command.length > 72 ? `${hook.command.slice(0, 72)}…` : hook.command;
}

export function hookFolder(hook) {
  const path = hook.paths.at(-1);
  if (!path) return null;
  return path.split('/').slice(0, -1).join('/').replace(/^\/Users\/[^/]+/, '~').replace(/^\/(private\/)?var\/folders\/[^/]+\/[^/]+\/T/, '(temp)');
}

export function visibleItems(ctx) {
  const { state, data } = ctx;
  const q = state.q.trim().toLowerCase();
  return data.items.filter((it) => {
    if (it.kind !== state.tab) return false;
    if (state.cli !== 'all' && it.cli !== state.cli) return false;
    if (state.filter === 'unused' && (!it.usage || it.usage.sessions > 0)) return false;
    if (state.filter === 'one-cli' && it.inOther) return false;
    if (state.filter === 'plugin' && it.removable) return false;
    return !q || it.name.toLowerCase().includes(q) || it.description.toLowerCase().includes(q);
  }).sort((a, b) => (b.usage?.sessions ?? 0) - (a.usage?.sessions ?? 0) || a.name.localeCompare(b.name));
}

export function visibleHooks(ctx) {
  const { state, data } = ctx;
  const q = state.q.trim().toLowerCase();
  return data.hooks.filter((x) => {
    if (state.cli !== 'all' && x.cli !== state.cli) return false;
    if (state.filter === 'dead' && !x.dead) return false;
    if (state.filter === 'plugin' && x.removable) return false;
    if (state.event && x.event !== state.event) return false;
    return !q || x.command.toLowerCase().includes(q) || x.event.toLowerCase().includes(q);
  });
}

export function usageNote(data) {
  const s = data.usageStatus;
  if (s.state === 'scanning') return `Counting usage… ${s.total ? `${num(s.done)} of ${num(s.total)} logs` : ''}`;
  if (s.state === 'failed') return 'Usage could not be counted. The list is still accurate.';
  return `Counted from ${num(s.sessions.claude)} Claude and ${num(s.sessions.codex)} Codex sessions on this Mac`;
}

export const cliChip = (cli) => h('span', { class: `chip chip-${cli}` }, cli === 'claude' ? 'Claude' : 'Codex');

export function ownerTag(it) {
  if (it.owner === 'user') return null;
  return h('span', { class: 'tag' }, it.owner === 'link' ? 'linked' : it.owner);
}

export function slip(weeks) {
  return h('span', { class: 'slip', role: 'img', 'aria-label': `Used on ${weeks.reduce((a, b) => a + b, 0)} days in the last 26 weeks` },
    weeks.map((n) => h('i', { class: n === 0 ? 'cell' : n < 3 ? 'cell on' : 'cell on hot' })));
}

export function toolbar(ctx, { extra } = {}) {
  const { state, set } = ctx;
  const isHook = state.tab === 'hook';
  const filters = isHook
    ? [['all', 'All'], ['dead', 'Dead'], ['plugin', 'From plugins']]
    : [['all', 'All'], ['unused', 'Never used'], ['one-cli', 'In one CLI only'], ['plugin', 'From plugins']];
  return h('div', { class: 'toolbar' },
    h('label', { class: 'search' }, icon('search'),
      h('span', { class: 'sr' }, 'Search'),
      h('input', { id: 'q', type: 'search', placeholder: 'Search', value: state.q, oninput: (e) => set({ q: e.target.value }, 'q') })),
    h('div', { class: 'seg', role: 'group', 'aria-label': 'CLI' },
      [['all', 'Both'], ['claude', 'Claude'], ['codex', 'Codex']].map(([v, label]) =>
        h('button', { type: 'button', 'aria-pressed': String(state.cli === v), onclick: () => set({ cli: v }) }, label))),
    h('label', { class: 'select' }, h('span', { class: 'sr' }, 'Filter'),
      h('select', { onchange: (e) => set({ filter: e.target.value }) },
        filters.map(([v, label]) => h('option', { value: v, selected: state.filter === v ? true : null }, label)))),
    extra,
    h('button', { type: 'button', class: 'btn primary add', onclick: () => ctx.openAdd() }, icon('plus'), 'Add'));
}

export function deadBanner(ctx) {
  return ['claude', 'codex'].map((cli) => {
    if (ctx.state.cli !== 'all' && ctx.state.cli !== cli) return null;
    const all = ctx.data.hooks.filter((x) => x.cli === cli);
    const dead = all.filter((x) => x.dead && x.removable).length;
    if (!dead) return null;
    return h('div', { class: 'banner' },
      h('p', {}, h('strong', {}, `${num(dead)} of ${num(all.length)}`), ` ${CLI_LABEL[cli]} hooks point at scripts that no longer exist.`),
      h('button', { type: 'button', class: 'btn danger', onclick: () => ctx.removeDead(cli, dead) }, `Remove ${num(dead)} dead ${dead === 1 ? 'hook' : 'hooks'}`));
  });
}

export function hookList(ctx) {
  const hooks = visibleHooks(ctx);
  if (!hooks.length) return h('p', { class: 'empty' }, 'No hooks match.');
  const maxTotal = Math.max(1, ...hooks.map((x) => x.usage?.totalMs ?? 0));
  const order = [...new Set(Object.values(ctx.data.events).flat())];
  const events = [...new Set(hooks.map((x) => x.event))].sort((a, b) => order.indexOf(a) - order.indexOf(b));
  return h('div', { class: 'hook-list' }, events.map((event) => {
    const rows = hooks.filter((x) => x.event === event).sort((a, b) => a.dead - b.dead || (b.usage?.totalMs ?? 0) - (a.usage?.totalMs ?? 0));
    return h('section', { class: 'hook-group' },
      h('h3', {}, event, h('span', { class: 'count' }, num(rows.length))),
      rows.map((x) => hookRow(ctx, x, maxTotal)));
  }));
}

function hookRow(ctx, x, maxTotal) {
  const pct = x.usage ? Math.max(x.usage.totalMs ? 2 : 0, (x.usage.totalMs / maxTotal) * 100) : 0;
  const voided = ctx.state.voided.has(x.id);
  return h('div', { class: `row hook-row${x.dead ? ' is-dead' : ''}${ctx.state.selected === x.id ? ' is-selected' : ''}${voided ? ' is-void' : ''}` },
    h('button', { type: 'button', class: 'row-main', onclick: () => ctx.select(x.id) },
      h('span', { class: 'name' }, hookLabel(x), x.matcher && x.matcher !== '*' ? h('code', { class: 'matcher' }, x.matcher) : null),
      h('span', { class: 'sub' }, x.dead ? 'Script is gone' : hookFolder(x) ?? x.command.slice(0, 80))),
    h('span', { class: 'cli-cell' }, cliChip(x.cli), x.removable ? null : ownerTag(x)),
    h('span', { class: 'time-bar', 'aria-hidden': 'true' }, h('i', { style: null, 'data-w': pct.toFixed(1) })),
    h('span', { class: 'stat' }, !x.usage ? h('span', { class: 'unknown', title: 'This CLI does not log hook runs.' }, 'not logged') : `${num(x.usage.runs)} runs`),
    h('span', { class: 'stat' }, x.usage?.avgMs != null ? `${ms(x.usage.avgMs)} avg` : ''),
    h('span', { class: 'stat err' }, x.usage?.errors ? `${num(x.usage.errors)} failed` : ''),
    voided ? h('span', { class: 'void-stamp' }, 'VOID') : null);
}

export function historyList(ctx) {
  if (!ctx.history.length) return h('p', { class: 'empty' }, 'Nothing added or removed yet.');
  return h('ol', { class: 'history' }, ctx.history.map((e) =>
    h('li', { class: e.undone ? 'is-undone' : '' },
      h('span', { class: 'when' }, new Date(e.at).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false })),
      h('span', { class: 'what' }, e.label),
      e.undone ? h('span', { class: 'tag' }, 'undone') : h('button', { type: 'button', class: 'btn', onclick: () => ctx.undo(e.id) }, icon('undo'), 'Undo'))));
}

export function detailPanel(ctx) {
  const { state, data } = ctx;
  const it = [...data.items, ...data.hooks].find((x) => x.id === state.selected);
  if (!it) return null;
  const other = it.cli === 'claude' ? 'codex' : 'claude';
  const canCopy = it.kind === 'hook' ? data.events[other].includes(it.event) : !it.inOther;
  return h('aside', { class: 'detail', 'aria-label': 'Details' },
    h('header', {},
      h('h2', {}, it.kind === 'hook' ? hookLabel(it) : it.name),
      h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Close details', onclick: () => ctx.select(null) }, icon('close'))),
    h('div', { class: 'meta' }, cliChip(it.cli), it.kind === 'hook' ? h('code', {}, it.event + (it.matcher ? ` · ${it.matcher}` : '')) : null, ownerTag(it)),
    it.kind === 'hook' ? hookEvidence(it) : itemEvidence(it),
    h('div', { class: 'actions' },
      it.removable ? h('button', { type: 'button', class: 'btn danger', onclick: () => ctx.remove(it) }, icon('trash'), it.owner === 'link' ? 'Remove link' : 'Remove') : h('p', { class: 'hint' }, `Part of the ${it.owner} plugin.`),
      canCopy ? h('button', { type: 'button', class: 'btn', onclick: () => ctx.copy(it) }, icon('copy'), `Copy to ${CLI_LABEL[other]}`) : null),
    it.kind === 'hook'
      ? h('pre', { class: 'code' }, it.command)
      : h('pre', { class: 'code', id: 'preview' }, ctx.preview?.id === it.id ? ctx.preview.text : ''),
    h('p', { class: 'path' }, it.kind === 'hook' ? it.file : it.path));
}

function itemEvidence(it) {
  if (!it.usage) return h('p', { class: 'hint' }, 'Counting usage…');
  const how = it.cli === 'claude'
    ? 'Counts Skill tool calls and slash commands.'
    : 'Counts sessions where Codex opened this SKILL.md or spawned this agent.';
  return h('div', { class: 'evidence' },
    h('p', { class: 'big' }, it.usage.sessions ? `${num(it.usage.sessions)} sessions` : 'Never used'),
    it.usage.last ? h('p', {}, `Last used ${shortDate(it.usage.last)}`) : null,
    slip(it.usage.weeks),
    h('p', { class: 'hint' }, how),
    it.description ? h('p', { class: 'desc' }, it.description) : h('p', { class: 'warn' }, 'No description, so the agent has little reason to pick it.'));
}

function hookEvidence(it) {
  return h('div', { class: 'evidence' },
    it.dead ? h('p', { class: 'warn' }, `Missing: ${it.paths.join(', ')}`) : null,
    it.usage
      ? h('p', { class: 'big' }, `${num(it.usage.runs)} runs`)
      : h('p', { class: 'hint' }, `${CLI_LABEL[it.cli]} does not log hook runs, so timing is not available.`),
    it.usage?.runs ? h('p', {}, `${ms(it.usage.avgMs)} average · ${ms(it.usage.totalMs)} total · last ${shortDate(it.usage.last)}`) : null,
    it.usage?.errors ? h('p', { class: 'warn' }, `${num(it.usage.errors)} runs failed`) : null);
}

// --- Add drawer ---

export function openAddDrawer(ctx, initialKind) {
  const dlg = document.getElementById('add');
  let kind = initialKind;
  let clis = new Set(['claude', 'codex']);
  let error = '';
  let busy = false;
  let source = null;
  let picked = new Set();
  const form = { source: '', name: '', description: '', body: '', event: 'Stop', matcher: '', command: '', timeout: '' };

  const field = (label, key, attrs = {}, Tag = 'input') => h('label', { class: 'field' }, h('span', {}, label),
    h(Tag, { ...attrs, value: form[key], oninput: (e) => { form[key] = e.target.value; } }));

  const cliPick = () => h('fieldset', { class: 'clis' }, h('legend', {}, 'Add to'),
    ['claude', 'codex'].map((cli) => h('label', {}, h('input', {
      type: 'checkbox', checked: clis.has(cli),
      onchange: (e) => { clis = new Set(e.target.checked ? [...clis, cli] : [...clis].filter((c) => c !== cli)); draw(); },
    }), CLI_LABEL[cli])));

  async function submit(fn, closeAfter = true) {
    busy = true; error = ''; draw();
    try {
      const result = await fn();
      if (closeAfter) { dlg.close(); await ctx.after(result); return; }
    } catch (err) { error = err.message; }
    busy = false; draw();
  }

  const eventsFor = () => {
    const lists = [...clis].map((c) => ctx.data.events[c]);
    if (!lists.length) return ctx.data.events.claude;
    return lists.reduce((a, b) => a.filter((e) => b.includes(e)));
  };

  function skillForm() {
    return [
      h('label', { class: 'field' }, h('span', {}, 'GitHub link or folder'),
        h('div', { class: 'inline' },
          h('input', { id: 'source', value: form.source, placeholder: 'https://github.com/owner/repo', autofocus: true, oninput: (e) => { form.source = e.target.value; }, onkeydown: (e) => { if (e.key === 'Enter') { e.preventDefault(); fetchSource(); } } }),
          h('button', { type: 'button', class: 'btn', disabled: busy || null, onclick: fetchSource }, busy ? 'Reading…' : 'Read'))),
      source ? sourcePreview() : h('details', { class: 'write-new' }, h('summary', {}, 'Or write a new one'),
        field('Name', 'name', { placeholder: 'release-notes' }),
        field('When to use it', 'description', { rows: 2 }, 'textarea'),
        field('Instructions', 'body', { rows: 6 }, 'textarea'),
        cliPick(),
        h('button', { type: 'button', class: 'btn primary', disabled: busy || null, onclick: () => submit(() => ctx.api('/api/add/skill', { ...form, clis: [...clis] })) }, 'Add skill')),
    ];
  }

  function sourcePreview() {
    return h('div', { class: 'source' },
      h('p', { class: 'warn' }, 'Instructions from this source will steer your agent. Read them before adding.'),
      source.skills.map((s) => h('details', { class: 'source-skill', open: source.skills.length === 1 ? true : null },
        h('summary', {}, h('label', {}, h('input', { type: 'checkbox', checked: picked.has(s.name), onchange: (e) => { picked = new Set(e.target.checked ? [...picked, s.name] : [...picked].filter((n) => n !== s.name)); } }), h('strong', {}, s.name)), s.hasScripts ? h('span', { class: 'tag warn-tag' }, 'has scripts') : null),
        h('pre', { class: 'code' }, s.text))),
      cliPick(),
      h('button', { type: 'button', class: 'btn primary', disabled: busy || null, onclick: () => submit(() => ctx.api('/api/source/install', { sourceId: source.sourceId, names: [...picked], clis: [...clis] })) }, 'Add selected'));
  }

  async function fetchSource() {
    await submit(async () => {
      source = await ctx.api('/api/source/preview', { source: form.source });
      picked = new Set(source.skills.map((s) => s.name));
    }, false);
  }

  const agentForm = () => [
    field('Name', 'name', { placeholder: 'code-reviewer', autofocus: true }),
    field('When to use it', 'description', { rows: 2 }, 'textarea'),
    field('Instructions', 'body', { rows: 8 }, 'textarea'),
    cliPick(),
    h('button', { type: 'button', class: 'btn primary', disabled: busy || null, onclick: () => submit(() => ctx.api('/api/add/agent', { name: form.name, description: form.description, instructions: form.body, clis: [...clis] })) }, 'Add agent'),
  ];

  function hookForm() {
    const events = eventsFor();
    if (!events.includes(form.event)) form.event = events[0];
    return [
      h('div', { class: 'presets' }, PRESETS.map((p) => h('button', { type: 'button', class: 'btn', onclick: () => { Object.assign(form, { event: p.event, matcher: p.matcher, command: p.command }); draw(); } }, p.label))),
      cliPick(),
      h('label', { class: 'field' }, h('span', {}, 'Event'),
        h('select', { onchange: (e) => { form.event = e.target.value; } }, events.map((ev) => h('option', { value: ev, selected: ev === form.event ? true : null }, ev)))),
      field('Only for tools matching', 'matcher', { placeholder: 'Edit|Write' }),
      field('Command', 'command', { rows: 4, spellcheck: 'false', class: 'mono' }, 'textarea'),
      h('p', { class: 'warn' }, 'This command will run on your Mac in every new session that hits this event. Reins does not run it.'),
      h('button', { type: 'button', class: 'btn primary', disabled: busy || null, onclick: () => submit(() => ctx.api('/api/add/hook', { ...form, clis: [...clis] })) }, 'Add hook'),
    ];
  }

  function draw() {
    const body = kind === 'skill' ? skillForm() : kind === 'agent' ? agentForm() : hookForm();
    dlg.replaceChildren(h('div', { class: 'drawer' },
      h('header', {},
        h('h2', {}, 'Add'),
        h('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Close', onclick: () => dlg.close() }, icon('close'))),
      h('div', { class: 'seg wide', role: 'group', 'aria-label': 'What to add' },
        [['skill', 'Skill'], ['agent', 'Agent'], ['hook', 'Hook']].map(([v, label]) =>
          h('button', { type: 'button', 'aria-pressed': String(kind === v), onclick: () => { kind = v; error = ''; draw(); } }, label))),
      error ? h('p', { class: 'error', role: 'alert' }, error) : null,
      body));
  }

  draw();
  dlg.showModal();
}

export function confirmDialog(title, text, actionLabel) {
  const dlg = document.getElementById('confirm');
  return new Promise((done) => {
    dlg.replaceChildren(h('div', { class: 'confirm' },
      h('h2', {}, title), h('p', {}, text),
      h('div', { class: 'actions' },
        h('button', { type: 'button', class: 'btn', onclick: () => { dlg.close(); done(false); } }, 'Cancel'),
        h('button', { type: 'button', class: 'btn danger', onclick: () => { dlg.close(); done(true); } }, actionLabel))));
    dlg.showModal();
  });
}
