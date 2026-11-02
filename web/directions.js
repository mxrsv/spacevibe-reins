import { CLI_LABEL, h, icon, num, shortDate } from './dom.js';
import { TABS, cliChip, deadBanner, detailPanel, historyList, hookList, ownerTag, slip, toolbar, usageNote, visibleItems } from './shared.js';

const tabButton = (ctx, [id, label, ic], count) =>
  h('button', { type: 'button', class: 'tab', 'aria-current': ctx.state.tab === id ? 'page' : null, onclick: () => ctx.set({ tab: id, filter: 'all', event: null, selected: null }) },
    icon(ic), h('span', {}, label), count != null ? h('span', { class: 'count' }, num(count)) : null);

const tabCount = (ctx, id) => (id === 'hook' ? ctx.data.hooks.length : id === 'history' ? null : ctx.data.items.filter((x) => x.kind === id).length);

function body(ctx, itemsView) {
  if (ctx.state.tab === 'history') return historyList(ctx);
  if (ctx.state.tab === 'hook') return [deadBanner(ctx), hookList(ctx)];
  const items = visibleItems(ctx);
  return items.length ? itemsView(items) : h('p', { class: 'empty' }, 'Nothing matches.');
}

const problems = (ctx) => ctx.data.problems.map((p) => h('div', { class: 'banner' }, h('p', {}, p)));

function itemSummary(ctx) {
  const items = ctx.data.items.filter((x) => x.kind === ctx.state.tab && (ctx.state.cli === 'all' || x.cli === ctx.state.cli));
  if (!items.length || !items[0].usage) return null;
  const unused = items.filter((x) => x.usage.sessions === 0).length;
  const chars = items.reduce((a, x) => a + x.descChars, 0);
  return h('p', { class: 'summary' },
    h('strong', {}, `${num(unused)} of ${num(items.length)}`), ' never used',
    ctx.state.tab === 'skill' ? ` · descriptions total ${num(chars)} characters` : '');
}

const rowClass = (ctx, it) => `row${ctx.state.selected === it.id ? ' is-selected' : ''}${ctx.state.voided.has(it.id) ? ' is-void' : ''}${it.usage?.sessions === 0 ? ' is-unused' : ''}`;

// A · Date due: a side rail, and every row carries its own date-due slip.
export function viewA(ctx) {
  const rows = (items) => h('div', { class: 'ledger' },
    h('div', { class: 'ledger-head', 'aria-hidden': 'true' }, h('span', {}, 'Name'), h('span', {}, 'CLI'), h('span', {}, 'Last 26 weeks'), h('span', {}, 'Sessions'), h('span', {}, 'Last used')),
    items.map((it) => h('div', { class: rowClass(ctx, it) },
      h('button', { type: 'button', class: 'row-main', onclick: () => ctx.select(it.id) },
        h('span', { class: 'name' }, it.name, ownerTag(it)),
        h('span', { class: 'sub' }, it.description || 'No description')),
      h('span', { class: 'cli-cell' }, cliChip(it.cli), it.inOther ? null : h('span', { class: 'only' }, 'only here')),
      it.usage ? slip(it.usage.weeks) : h('span', { class: 'unknown' }, 'counting'),
      h('span', { class: 'stat strong' }, it.usage ? (it.usage.sessions ? num(it.usage.sessions) : h('span', { class: 'never' }, 'Never')) : ''),
      h('span', { class: 'stat' }, it.usage ? shortDate(it.usage.last) : ''),
      ctx.state.voided.has(it.id) ? h('span', { class: 'void-stamp' }, 'VOID') : null)));

  return h('div', { class: 'shell shell-a' },
    h('nav', { class: 'rail', 'aria-label': 'Sections' },
      h('h1', { class: 'brand' }, 'Reins'),
      TABS.map((t) => tabButton(ctx, t, tabCount(ctx, t[0]))),
      h('p', { class: 'rail-note' }, usageNote(ctx.data))),
    h('main', { class: 'main' },
      problems(ctx),
      toolbar(ctx),
      ctx.state.tab === 'skill' || ctx.state.tab === 'agent' ? itemSummary(ctx) : null,
      body(ctx, rows)),
    detailPanel(ctx));
}

// B · Chart: a top bar, and ranked bars where the value is the picture.
export function viewB(ctx) {
  const rows = (items) => {
    const used = items.filter((x) => (x.usage?.sessions ?? 0) > 0);
    const unused = items.filter((x) => (x.usage?.sessions ?? 0) === 0);
    const max = Math.max(1, ...used.map((x) => x.usage.sessions));
    return [
      h('ol', { class: 'chart' }, used.map((it, i) => h('li', { class: `${rowClass(ctx, it)} bar-row${i === 0 ? ' is-first' : ''}` },
        h('button', { type: 'button', class: 'row-main', onclick: () => ctx.select(it.id) },
          h('span', { class: 'fill', 'data-w': Math.max(3, (it.usage.sessions / max) * 100).toFixed(1) }),
          h('span', { class: 'rank' }, i + 1),
          h('span', { class: 'name' }, it.name),
          h('span', { class: 'cli-mini' }, it.cli === 'claude' ? 'Claude' : 'Codex'),
          h('span', { class: 'value' }, num(it.usage.sessions))),
        ctx.state.voided.has(it.id) ? h('span', { class: 'void-stamp' }, 'VOID') : null))),
      unused.length ? h('section', { class: 'bench' },
        h('h3', {}, 'Never used', h('span', { class: 'count' }, num(unused.length))),
        h('div', { class: 'bench-grid' }, unused.map((it) => h('button', { type: 'button', class: `bench-item${ctx.state.selected === it.id ? ' is-selected' : ''}${ctx.state.voided.has(it.id) ? ' is-void' : ''}`, onclick: () => ctx.select(it.id) }, it.name, h('span', { class: 'cli-mini' }, it.cli === 'claude' ? 'Claude' : 'Codex'))))) : null,
    ];
  };
  return h('div', { class: 'shell shell-b' },
    h('nav', { class: 'topbar', 'aria-label': 'Sections' },
      h('h1', { class: 'brand' }, 'Reins'),
      h('div', { class: 'tabs' }, TABS.map((t) => tabButton(ctx, t, tabCount(ctx, t[0])))),
      h('p', { class: 'rail-note' }, usageNote(ctx.data))),
    h('main', { class: 'main' }, problems(ctx), toolbar(ctx), body(ctx, rows)),
    detailPanel(ctx));
}

// C · Line: session events lead as a route map, and both CLIs are set face to face.
const ROUTE = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'SubagentStart', 'SubagentStop', 'Stop', 'SessionEnd'];

function route(ctx) {
  const count = (cli, event, dead) => ctx.data.hooks.filter((x) => x.cli === cli && x.event === event && (dead ? x.dead : !x.dead)).length;
  return h('div', { class: 'route', role: 'group', 'aria-label': 'Hooks along a session' },
    ROUTE.map((event) => {
      const live = { claude: count('claude', event, false), codex: count('codex', event, false) };
      const dead = count('codex', event, true) + count('claude', event, true);
      return h('button', { type: 'button', class: 'stop', 'aria-pressed': String(ctx.state.event === event), onclick: () => ctx.set({ tab: 'hook', filter: 'all', event: ctx.state.event === event ? null : event, selected: null }) },
        h('span', { class: 'stop-name' }, event),
        h('span', { class: 'track track-claude' }, h('i', {}), h('b', {}, live.claude)),
        h('span', { class: 'track track-codex' }, h('i', {}), h('b', {}, live.codex)),
        h('span', { class: 'stop-dead' }, dead ? `${num(dead)} dead` : ''));
    }));
}

export function viewC(ctx) {
  const rows = (items) => {
    const byName = new Map();
    for (const it of items) {
      const key = it.name.split(':').pop();
      byName.set(key, { ...(byName.get(key) ?? {}), [it.cli]: it });
    }
    const pairs = [...byName.entries()].sort((a, b) => {
      const score = ([, p]) => (p.claude?.usage?.sessions ?? 0) + (p.codex?.usage?.sessions ?? 0);
      return score(b) - score(a) || a[0].localeCompare(b[0]);
    });
    const max = Math.max(1, ...items.map((x) => x.usage?.sessions ?? 0));
    const side = (it, cli, twin) => {
      if (!it) {
        return h('div', { class: 'side side-empty' }, twin?.removable !== undefined ? h('button', { type: 'button', class: 'copy-across', onclick: () => ctx.copy(twin) }, icon('copy'), `Copy to ${CLI_LABEL[cli]}`) : null);
      }
      const n = it.usage?.sessions ?? 0;
      return h('button', { type: 'button', class: `side side-${cli}${ctx.state.selected === it.id ? ' is-selected' : ''}${ctx.state.voided.has(it.id) ? ' is-void' : ''}`, onclick: () => ctx.select(it.id) },
        h('span', { class: 'value' }, it.usage ? (n ? num(n) : 'Never') : ''),
        h('span', { class: 'mirror-bar' }, h('i', { 'data-w': n ? Math.max(3, (n / max) * 100).toFixed(1) : '0' })));
    };
    return h('div', { class: 'mirror' },
      h('div', { class: 'mirror-head', 'aria-hidden': 'true' }, h('span', {}, 'Claude Code'), h('span', {}, 'Name'), h('span', {}, 'Codex')),
      pairs.map(([name, p]) => h('div', { class: 'mirror-row' },
        side(p.claude, 'claude', p.codex),
        h('button', { type: 'button', class: 'mirror-name', onclick: () => ctx.select((p.claude ?? p.codex).id) }, name),
        side(p.codex, 'codex', p.claude))));
  };
  return h('div', { class: 'shell shell-c' },
    h('header', { class: 'c-head' },
      h('h1', { class: 'brand' }, 'Reins'),
      h('nav', { class: 'tabs', 'aria-label': 'Sections' }, TABS.map((t) => tabButton(ctx, t, tabCount(ctx, t[0])))),
      h('p', { class: 'rail-note' }, usageNote(ctx.data))),
    route(ctx),
    h('main', { class: 'main' }, problems(ctx), toolbar(ctx), body(ctx, rows)),
    detailPanel(ctx));
}
