// Runs only against temp folders. It must never see the real ~/.claude or ~/.codex.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { readInventory, roots, scriptPaths, tomlFields } from './core/inventory.mjs';
import { addAgent, addHook, addSkill, copyToOther, history, installSource, previewSource, removeDeadHooks, removeItem, undo } from './core/mutate.mjs';
import { scan } from './core/usage.mjs';

const home = mkdtempSync(join(tmpdir(), 'reins-test-'));
const r = roots({ HOME: home });
const SECRET = 'do-not-lose-this-value';

before(() => {
  mkdirSync(join(home, '.claude/skills/keep'), { recursive: true });
  writeFileSync(join(home, '.claude/skills/keep/SKILL.md'), '---\nname: keep\ndescription: >\n  folded\n  text\n---\nbody');
  mkdirSync(join(home, 'shared/linked'), { recursive: true });
  writeFileSync(join(home, 'shared/linked/SKILL.md'), '---\nname: linked\ndescription: shared\n---\n');
  symlinkSync(join(home, 'shared/linked'), join(home, '.claude/skills/linked'));
  mkdirSync(join(home, '.claude/agents'), { recursive: true });
  writeFileSync(join(home, '.claude/agents/rev.md'), '---\nname: rev\ndescription: "reviews"\n---\nInstructions "quoted"\n');
  writeFileSync(join(home, '.claude/settings.json'), JSON.stringify({
    env: { TOKEN: SECRET }, model: 'x',
    hooks: { Stop: [{ hooks: [{ type: 'command', command: `sh '${home}/gone/dead.sh'` }, { type: 'command', command: 'echo live' }] }] },
  }, null, 2));
  mkdirSync(join(home, '.codex/skills/.system/hidden'), { recursive: true });
  writeFileSync(join(home, '.codex/skills/.system/hidden/SKILL.md'), '---\nname: hidden\n---\n');
  writeFileSync(join(home, '.codex/hooks.json'), JSON.stringify({ hooks: {} }));
});
after(() => execFileSync('rm', ['-rf', home]));

const inv = () => readInventory(r);
const settings = () => JSON.parse(readFileSync(r.claude.hookFile, 'utf8'));
const find = (name, cli = 'claude') => inv().items.find((i) => i.name === name && i.cli === cli);

test('reads items and flags dead hooks without touching system folders', () => {
  const v = inv();
  assert.equal(find('keep').description, 'folded text');
  assert.equal(find('linked').owner, 'link');
  assert.equal(v.items.some((i) => i.name === 'hidden'), false);
  assert.equal(v.hooks.find((h) => h.command.includes('dead.sh')).dead, true);
  assert.equal(v.hooks.find((h) => h.command === 'echo live').dead, false);
});

test('scriptPaths only counts script files', () => {
  assert.deepEqual(scriptPaths('/usr/bin/osascript -e hi >> /tmp/out.log'), []);
  assert.deepEqual(scriptPaths("if [ -x '/a b/c.sh' ]; then '/a b/c.sh'; fi"), ['/a b/c.sh']);
});

test('add then undo a skill in both CLIs', () => {
  const e = addSkill(r, { clis: ['claude', 'codex'], name: 'quick', description: 'use: "when" asked', body: 'do it' });
  assert.ok(find('quick') && find('quick', 'codex'));
  assert.equal(find('quick').description, 'use: "when" asked');
  undo(r, { id: e.id });
  assert.equal(find('quick'), undefined);
  assert.equal(find('quick', 'codex'), undefined);
  assert.throws(() => undo(r, { id: e.id }), /already undone/);
});

test('rejects unsafe names and existing names', () => {
  for (const name of ['../evil', 'a/b', '.hidden', 'UP', '']) {
    assert.throws(() => addSkill(r, { clis: ['claude'], name, description: 'x' }), /lowercase/);
  }
  assert.throws(() => addSkill(r, { clis: ['claude'], name: 'keep', description: 'x' }), /already has/);
  assert.throws(() => addAgent(r, { clis: ['claude'], name: '../../x', description: 'x' }), /lowercase/);
});

test('removing a linked skill leaves its target, undo restores the link', () => {
  const e = removeItem(r, { id: find('linked').id });
  assert.equal(existsSync(join(home, '.claude/skills/linked')), false);
  assert.ok(existsSync(join(home, 'shared/linked/SKILL.md')));
  undo(r, { id: e.id });
  assert.ok(lstatSync(join(home, '.claude/skills/linked')).isSymbolicLink());
  assert.equal(readlinkSync(join(home, '.claude/skills/linked')), join(home, 'shared/linked'));
});

test('removing a real skill moves it to trash and undo brings it back', () => {
  const e = removeItem(r, { id: find('keep').id });
  assert.equal(find('keep'), undefined);
  undo(r, { id: e.id });
  assert.match(readFileSync(join(home, '.claude/skills/keep/SKILL.md'), 'utf8'), /body/);
});

test('hook add and remove keep every other setting', () => {
  const before = settings();
  const e = addHook(r, { clis: ['claude'], event: 'Stop', matcher: '', command: 'echo added', timeout: 5 });
  assert.equal(settings().env.TOKEN, SECRET);
  const h = inv().hooks.find((x) => x.command === 'echo added');
  assert.equal(h.timeout, 5);
  undo(r, { id: e.id });
  assert.deepEqual(settings(), before);
  assert.throws(() => addHook(r, { clis: ['codex'], event: 'TeammateIdle', command: 'x' }), /no TeammateIdle/);
});

test('a removed hook comes back under its original matcher', () => {
  const m = addHook(r, { clis: ['claude'], event: 'PreToolUse', matcher: 'Edit', command: 'echo one' });
  const h = inv().hooks.find((x) => x.command === 'echo one');
  const e = removeItem(r, { id: h.id });
  assert.equal(inv().hooks.some((x) => x.command === 'echo one'), false);
  undo(r, { id: e.id });
  assert.equal(inv().hooks.find((x) => x.command === 'echo one').matcher, 'Edit');
  undo(r, { id: m.id });
  assert.equal(settings().hooks.PreToolUse, undefined);
});

test('remove dead hooks is one undoable step', () => {
  const before = settings();
  const e = removeDeadHooks(r, { cli: 'claude' });
  assert.equal(inv().hooks.filter((h) => h.dead).length, 0);
  assert.ok(inv().hooks.some((h) => h.command === 'echo live'));
  undo(r, { id: e.id });
  assert.deepEqual(new Set(settings().hooks.Stop[0].hooks.map((h) => h.command)), new Set(before.hooks.Stop[0].hooks.map((h) => h.command)));
  assert.equal(settings().env.TOKEN, SECRET);
});

test('agent converts between md and toml, round-tripping quotes', () => {
  const e = copyToOther(r, { id: find('rev').id });
  const codex = find('rev', 'codex');
  assert.equal(codex.description, 'reviews');
  assert.match(tomlFields(readFileSync(codex.path, 'utf8')).instructions, /Instructions "quoted"/);
  undo(r, { id: e.id });
  assert.equal(find('rev', 'codex'), undefined);
});

test('plugin-owned items cannot be removed', () => {
  mkdirSync(join(home, 'plug/skills/plug-skill'), { recursive: true });
  writeFileSync(join(home, 'plug/skills/plug-skill/SKILL.md'), '---\nname: plug-skill\ndescription: p\n---\n');
  mkdirSync(join(home, '.claude/plugins'), { recursive: true });
  writeFileSync(join(home, '.claude/plugins/installed_plugins.json'), JSON.stringify({ plugins: { 'plug@m': [{ installPath: join(home, 'plug') }] } }));
  const s = settings();
  writeFileSync(r.claude.hookFile, JSON.stringify({ ...s, enabledPlugins: { 'plug@m': true } }, null, 2));
  const it = find('plug-skill');
  assert.equal(it.removable, false);
  assert.throws(() => removeItem(r, { id: it.id }), /belongs to a plugin/);
  writeFileSync(r.claude.hookFile, JSON.stringify(s, null, 2));
});

test('folder source previews then installs; invalid JSON refuses writes', async () => {
  mkdirSync(join(home, 'src/pack/one/.git'), { recursive: true });
  writeFileSync(join(home, 'src/pack/one/SKILL.md'), '---\nname: one\ndescription: first\n---\n');
  writeFileSync(join(home, 'src/pack/one/.git/secret'), 'x');
  const p = await previewSource(r, { source: join(home, 'src/pack') });
  assert.deepEqual(p.skills.map((s) => s.name), ['one']);
  const e = installSource(r, { sourceId: p.sourceId, names: ['one'], clis: ['codex'] });
  assert.ok(find('one', 'codex'));
  assert.equal(existsSync(join(home, '.codex/skills/one/.git')), false);
  undo(r, { id: e.id });
  await assert.rejects(previewSource(r, { source: 'https://evil.example/x/y' }), /github.com/);
  const raw = readFileSync(r.codex.hookFile, 'utf8');
  writeFileSync(r.codex.hookFile, '{broken');
  assert.throws(() => addHook(r, { clis: ['codex'], event: 'Stop', command: 'x' }), /not valid JSON/);
  assert.equal(readFileSync(r.codex.hookFile, 'utf8'), '{broken');
  writeFileSync(r.codex.hookFile, raw);
});

test('usage counts sessions and hook time, ignoring quoted text', async () => {
  const dir = join(home, '.claude/projects/p');
  mkdirSync(join(dir, 'sess2/subagents'), { recursive: true });
  const stamp = '"timestamp":"2026-10-30T10:00:00Z"';
  writeFileSync(join(dir, 'sess1.jsonl'), [
    `{"type":"assistant",${stamp},"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"kyant:keep"}}]}}`,
    `{"type":"assistant",${stamp},"message":{"content":[{"type":"tool_use","name":"Task","input":{"subagent_type":"rev"}}]}}`,
    `{"type":"user",${stamp},"message":{"content":"quoted \\"name\\":\\"Skill\\",\\"input\\":{\\"skill\\":\\"linked\\"}"}}`,
    `{"type":"attachment",${stamp},"attachment":{"type":"hook_success","hookEvent":"Stop","command":"echo live","durationMs":100,"exitCode":0}}`,
    `{"type":"attachment",${stamp},"attachment":{"type":"hook_non_blocking_error","hookEvent":"Stop","command":"echo live","durationMs":300,"exitCode":1}}`,
  ].join('\n'));
  writeFileSync(join(dir, 'sess2.jsonl'), `{"type":"user",${stamp},"message":{"content":"<command-name>/keep</command-name>"}}`);
  const { totals, sessions } = await scan(r);
  assert.equal(totals.claude.skill.keep.sessions, 2);
  assert.equal(totals.claude.skill.linked, undefined);
  assert.equal(totals.claude.agent.rev.sessions, 1);
  const hook = inv().hooks.find((h) => h.command === 'echo live');
  assert.deepEqual({ runs: totals.claude.hook[hook.hash].runs, ms: totals.claude.hook[hook.hash].ms, errors: totals.claude.hook[hook.hash].errors }, { runs: 2, ms: 400, errors: 1 });
  assert.equal(sessions.claude, 2);
  assert.ok(!readFileSync(join(r.data, 'usage-cache.json'), 'utf8').includes('echo live'));
});

test('history lists actions newest first', () => {
  assert.ok(history(r).length > 0);
});
