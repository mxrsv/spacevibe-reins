// Temp HOME only. The real home is used solely to check that the guard refuses it; no file under it is touched.
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir, userInfo } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import { attachUsage, discoverProjects, filterCounts, readInventory, roots, sha } from './inventory.mjs';
import { scan } from './usage.mjs';

const home = mkdtempSync(join(tmpdir(), 'reins-inv-'));
after(() => rmSync(home, { recursive: true, force: true }));
const envFor = (h, extra = {}) => ({ HOME: h, CLAUDE_CONFIG_DIR: join(h, '.claude'), CODEX_HOME: join(h, '.codex'), REINS_HOME: join(h, '.reins'), ...extra });

describe('AC3 guard', () => {
  const real = userInfo().homedir;
  test('refuses roots under the real home when REINS_TEST=1', () => {
    assert.throws(() => roots({ REINS_TEST: '1', HOME: real }), /real home/);
    assert.throws(() => roots(envFor(home, { REINS_TEST: '1', CLAUDE_CONFIG_DIR: join(real, '.claude') })), /real home/);
    assert.throws(() => roots(envFor(home, { REINS_TEST: '1', CODEX_HOME: join(real, '.codex') })), /real home/);
    assert.throws(() => roots(envFor(home, { REINS_TEST: '1', REINS_HOME: join(real, '.reins', '..', '.reins') })), /real home/);
    assert.throws(() => roots({ REINS_TEST: '1' }), /real home/, 'HOME unset falls back to the real home');
  });
  test('accepts temp roots', () => {
    assert.equal(roots(envFor(home, { REINS_TEST: '1' })).claude.root, join(home, '.claude'));
  });
  test('has no effect when REINS_TEST is unset', () => {
    assert.equal(roots({ HOME: real }).claude.root, join(real, '.claude'));
  });
});

const write = (path, text) => { mkdirSync(join(path, '..'), { recursive: true }); writeFileSync(path, text); };
const hookCfg = (event, command) => JSON.stringify({ env: { TOKEN: 'do-not-read' }, hooks: { [event]: [{ matcher: 'Edit', hooks: [{ type: 'command', command }] }] } });

describe('project configuration', () => {
  const h = join(home, 'proj-home');
  const alpha = join(h, 'work/alpha');
  const beta = join(h, 'work/beta');
  const r = roots(envFor(h, { REINS_TEST: '1' }));
  before(() => {
    // Global config.
    write(join(h, '.claude/skills/glob/SKILL.md'), '---\nname: glob\ndescription: g\n---\n');
    write(join(h, '.claude/settings.json'), hookCfg('Stop', 'echo shared'));
    // alpha is found through a Claude session log, and a worktree and the home dir are logged too.
    const cwdRec = (cwd) => JSON.stringify({ type: 'user', cwd, timestamp: '2026-10-01T10:00:00Z' });
    write(join(h, '.claude/projects/-enc-alpha/s1.jsonl'), `{"type":"file-history-snapshot"}\n${cwdRec(alpha)}`);
    write(join(h, '.claude/projects/-enc-wt/s1.jsonl'), cwdRec(join(alpha, '.claude/worktrees/feature')));
    write(join(h, '.claude/projects/-enc-home/s1.jsonl'), cwdRec(h));
    write(join(h, '.claude/projects/-enc-gone/s1.jsonl'), cwdRec(join(h, 'work/deleted')));
    write(join(alpha, '.claude/worktrees/feature/.claude/settings.json'), hookCfg('Stop', 'echo copy-in-worktree'));
    write(join(alpha, '.claude/skills/pskill/SKILL.md'), '---\nname: pskill\ndescription: project skill\n---\n');
    write(join(alpha, '.claude/agents/pagent.md'), '---\nname: pagent\ndescription: project agent\n---\n');
    write(join(alpha, '.claude/settings.json'), hookCfg('Stop', 'echo shared'));
    write(join(alpha, '.claude/settings.local.json'), hookCfg('PreToolUse', `sh '${alpha}/gone.sh'`));
    // beta is found through a Codex project key only.
    write(join(h, '.codex/config.toml'), `model = "x"\n[projects."${beta}"]\ntrust_level = "trusted"\n[projects."${join(h, 'work/missing')}"]\ntrust_level = "trusted"\n`);
    write(join(beta, '.claude/skills/bskill/SKILL.md'), '---\nname: bskill\ndescription: b\n---\n');
    mkdirSync(join(h, '.codex/sessions'), { recursive: true });
  });

  test('finds projects from session logs and Codex project keys, skipping worktrees, home and missing folders', () => {
    assert.deepEqual(discoverProjects(r).sort(), [alpha, beta].sort());
  });

  test('reads project skills, agents and hooks with scope and project', () => {
    const inv = readInventory(r);
    const byName = (n) => inv.items.find((i) => i.name === n);
    assert.deepEqual({ scope: byName('glob').scope, project: byName('glob').project }, { scope: 'global', project: null });
    assert.deepEqual({ scope: byName('pskill').scope, project: byName('pskill').project, kind: byName('pskill').kind }, { scope: 'project', project: alpha, kind: 'skill' });
    assert.equal(byName('pagent').kind, 'agent');
    assert.equal(byName('bskill').project, beta);
    assert.equal(byName('pskill').removable, false);
    const hooks = inv.hooks.filter((x) => x.project === alpha);
    assert.deepEqual(hooks.map((x) => [x.event, x.file.slice(alpha.length)]).sort(), [['PreToolUse', '/.claude/settings.local.json'], ['Stop', '/.claude/settings.json']]);
    assert.equal(hooks.find((x) => x.event === 'PreToolUse').dead, true);
    assert.equal(hooks.every((x) => x.scope === 'project' && !x.removable), true);
    assert.equal(inv.hooks.some((x) => x.command === 'echo copy-in-worktree'), false);
  });

  test('the same hook in the global file and a project keeps one hash but two ids', () => {
    const inv = readInventory(r);
    const same = inv.hooks.filter((x) => x.command === 'echo shared');
    assert.equal(same.length, 2);
    assert.equal(new Set(same.map((x) => x.hash)).size, 1);
    assert.equal(new Set(same.map((x) => x.id)).size, 2);
    assert.equal(same.find((x) => x.scope === 'global').id.startsWith('claude:hook:'), true);
  });

  test('a project hook shows the runs of its event plus command', async () => {
    const run = (cmd, exit) => JSON.stringify({ type: 'attachment', timestamp: '2026-10-02T10:00:00Z', attachment: { type: 'hook_success', hookEvent: 'Stop', command: cmd, durationMs: 1, exitCode: exit } });
    write(join(h, '.claude/projects/-enc-alpha/s2.jsonl'), [run('echo shared', 0), run('echo shared', 1)].join('\n'));
    const usage = { state: 'ready', ...(await scan(r)) };
    const inv = attachUsage(readInventory(r), usage, { now: Date.parse('2026-11-02T00:00:00Z') });
    const hook = inv.hooks.find((x) => x.command === 'echo shared' && x.scope === 'project');
    assert.deepEqual({ runs: hook.usage.runs, errors: hook.usage.errors }, { runs: 2, errors: 1 });
    assert.deepEqual(hook.cells.claude, { state: 'counted', runs: 2, errors: 1, last: '2026-10-02' });
  });

  test('without projects or logs nothing breaks', () => {
    const empty = roots(envFor(join(home, 'empty-home'), { REINS_TEST: '1' }));
    assert.deepEqual(discoverProjects(empty), []);
    assert.deepEqual(readInventory(empty).items, []);
  });
});

describe('usage cells and filter counts', () => {
  const h = join(home, 'cell-home');
  const r = roots(envFor(h, { REINS_TEST: '1' }));
  const NOW = Date.parse('2026-11-02T12:00:00Z');
  const NEWEST_LOG = Date.parse('2026-10-29T00:00:00Z');
  const at = (path, iso) => { const d = new Date(iso); utimesSync(path, d, d); };
  const skill = (cli, name, iso) => {
    const file = join(h, `.${cli}/skills/${name}/SKILL.md`);
    write(file, `---\nname: ${name}\ndescription: d\n---\n`);
    at(file, iso);
  };
  const totals = () => ({
    claude: { skill: { both: { sessions: 3, days: ['2026-10-20'], last: '2026-10-20' } }, agent: {}, hook: { [sha('Stop|echo ran')]: { runs: 7, ms: 70, timed: 7, errors: 2, last: '2026-10-25' } } },
    codex: { skill: {}, agent: {}, hook: {} },
  });
  const windows = { claude: { files: 9, oldest: '2026-09-01', newest: NEWEST_LOG }, codex: { files: 2, oldest: '2026-09-15', newest: NEWEST_LOG } };
  const ready = { state: 'ready', totals: totals(), windows };
  let inv;
  const cell = (name, cli, kind = 'skill', itemCli = 'claude') => inv.items.find((i) => i.name === name && i.kind === kind && i.cli === itemCli).cells[cli];

  before(() => {
    skill('claude', 'both', '2026-09-20T00:00:00Z');
    skill('codex', 'both', '2026-09-20T00:00:00Z');
    skill('claude', 'only-claude', '2026-09-20T00:00:00Z'); // zero uses, long installed: never ran
    skill('claude', 'after-log', '2026-10-30T00:00:00Z');   // 3 days old but newer than the newest log: pending
    skill('claude', 'fresh', '2026-11-02T08:00:00Z');       // inside the 24 h grace: pending
    write(join(h, '.claude/settings.json'), JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo ran' }, { type: 'command', command: `sh '${h}/gone/dead.sh'` }] }] } }));
    at(join(h, '.claude/settings.json'), '2026-09-20T00:00:00Z');
    write(join(h, '.codex/hooks.json'), JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo codex-only' }] }] } }));
    at(join(h, '.codex/hooks.json'), '2026-09-20T00:00:00Z');
    inv = attachUsage(readInventory(r), ready, { now: NOW });
  });

  test('counted, with zero runs meaning never ran', () => {
    assert.deepEqual(cell('both', 'claude'), { state: 'counted', runs: 3, last: '2026-10-20' });
    assert.deepEqual(cell('both', 'codex'), { state: 'counted', runs: 0, last: null });
    assert.deepEqual(cell('only-claude', 'claude'), { state: 'counted', runs: 0, last: null });
  });

  test('missing when not installed in that CLI, the same cells on both rows of one skill', () => {
    assert.deepEqual(cell('only-claude', 'codex'), { state: 'missing' });
    assert.deepEqual(cell('both', 'claude', 'skill', 'codex'), cell('both', 'claude'));
  });

  test('pending when no log window covers the item yet', () => {
    assert.equal(cell('after-log', 'claude').state, 'pending');
    assert.match(cell('after-log', 'claude').reason, /newest log/);
    assert.equal(cell('fresh', 'claude').state, 'pending');
    assert.match(cell('fresh', 'claude').reason, /24 hours/);
  });

  test('pending for everything until the usage scan has finished, and when a CLI has no logs', () => {
    const waiting = attachUsage(readInventory(r), { state: 'scanning', totals: null }, { now: NOW });
    assert.equal(waiting.items.find((i) => i.name === 'both' && i.cli === 'claude').cells.claude.state, 'pending');
    const noCodexLogs = attachUsage(readInventory(r), { state: 'ready', totals: totals(), windows: { ...windows, codex: { files: 0, oldest: null, newest: null } } }, { now: NOW });
    assert.equal(noCodexLogs.items.find((i) => i.name === 'both' && i.cli === 'codex').cells.codex.state, 'pending');
  });

  test('hooks: Claude counted with errors, Codex unmeasurable, absent CLI missing', () => {
    const ran = inv.hooks.find((x) => x.command === 'echo ran');
    assert.deepEqual(ran.cells.claude, { state: 'counted', runs: 7, errors: 2, last: '2026-10-25' });
    assert.deepEqual(ran.cells.codex, { state: 'missing' });
    assert.deepEqual({ runs: ran.usage.runs, errors: ran.usage.errors, avgMs: ran.usage.avgMs }, { runs: 7, errors: 2, avgMs: 10 });
    const cx = inv.hooks.find((x) => x.command === 'echo codex-only');
    assert.deepEqual(cx.cells.codex, { state: 'unmeasurable', reason: 'Codex does not log hook runs' });
    assert.deepEqual(cx.cells.claude, { state: 'missing' });
    assert.equal(cx.usage, null);
  });

  test('filter counts: all, only in one CLI, never ran, dead', () => {
    const rows = [...inv.items, ...inv.hooks];
    assert.deepEqual(filterCounts(rows), { all: 7, only: { claude: 5, codex: 1 }, neverRan: 1, dead: 1 });
    assert.deepEqual(filterCounts([]), { all: 0, only: { claude: 0, codex: 0 }, neverRan: 0, dead: 0 });
  });

  test('filter counts: a dead hook with 0 runs is counted under dead only', () => {
    const row = { key: 'k', dead: true, cells: { claude: { state: 'counted', runs: 0 }, codex: { state: 'missing' } } };
    const c = filterCounts([row]);
    assert.equal(c.dead, 1);
    assert.equal(c.neverRan, 0);
  });
});
