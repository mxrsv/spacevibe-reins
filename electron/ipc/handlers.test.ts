// Handler tests run under plain node against a temporary HOME. They never see the real ~/.claude or ~/.codex.
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { roots } from '#core/inventory.mjs';
import { CHANNELS, type Channel, type IpcContract, type Reply, type Req, type Res } from '../../src/lib/ipc-contract.ts';
import type { Ctx } from '../lib/context.ts';
import type { Handlers } from '../lib/handler.ts';
import { buildHandlerTable, dispatch, missingChannels } from '../lib/handler-table.ts';
import { toReply } from '../lib/reply.ts';
import { createUsageStore, startUsageScan } from '../lib/usage-store.ts';
import { usageWorkerPath } from '../lib/worker-path.ts';

const here = import.meta.dirname;
const files = readdirSync(here).filter((f) => f.endsWith('.ts') && !f.endsWith('.test.ts'));
const modules: Record<string, { handlers: Handlers }> = {};
for (const f of files) modules[f] = await import(`./${f}`);
const table = buildHandlerTable(modules);

const home = mkdtempSync(join(tmpdir(), 'reins-ipc-test-'));
const SECRET = 'do-not-lose-this-value';
const ctx: Ctx = { roots: roots({ HOME: home }), usage: createUsageStore() };

const call = <C extends Channel>(channel: C, request?: Req<C>) => dispatch(table, ctx, channel, request) as Promise<Reply<Res<C>>>;
async function ok<C extends Channel>(channel: C, request?: Req<C>): Promise<Res<C>> {
  const reply = await call(channel, request);
  assert.equal(reply.ok, true, JSON.stringify(reply));
  return (reply as { ok: true; data: Res<C> }).data;
}
async function fails<C extends Channel>(channel: C, request: unknown, status: number, message: RegExp) {
  const reply = await dispatch(table, ctx, channel, request);
  assert.equal(reply.ok, false);
  assert.equal((reply as { status: number }).status, status);
  assert.match((reply as { error: string }).error, message);
}
const inventory = async () => ok('inventory:read');
const find = async (name: string, cli = 'claude') => (await inventory()).items.find((i) => i.name === name && i.cli === cli);

before(async () => {
  mkdirSync(join(home, '.claude/skills/keep'), { recursive: true });
  writeFileSync(join(home, '.claude/skills/keep/SKILL.md'), '---\nname: keep\ndescription: folded\n---\nbody');
  mkdirSync(join(home, 'shared/linked'), { recursive: true });
  writeFileSync(join(home, 'shared/linked/SKILL.md'), '---\nname: linked\ndescription: shared\n---\n');
  symlinkSync(join(home, 'shared/linked'), join(home, '.claude/skills/linked'));
  mkdirSync(join(home, '.claude/agents'), { recursive: true });
  writeFileSync(join(home, '.claude/agents/rev.md'), '---\nname: rev\ndescription: "reviews"\n---\nInstructions\n');
  writeFileSync(join(home, '.claude/settings.json'), JSON.stringify({
    env: { TOKEN: SECRET },
    hooks: { Stop: [{ hooks: [{ type: 'command', command: `sh '${home}/gone/dead.sh'` }, { type: 'command', command: 'echo live' }] }] },
  }));
  mkdirSync(join(home, '.codex'), { recursive: true });
  writeFileSync(join(home, '.codex/hooks.json'), JSON.stringify({ hooks: {} }));
  const logs = join(home, '.claude/projects/p');
  mkdirSync(logs, { recursive: true });
  const stamp = `"timestamp":"${new Date().toISOString()}"`;
  writeFileSync(join(logs, 's1.jsonl'), [
    `{"type":"assistant",${stamp},"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"keep"}}]}}`,
    `{"type":"attachment",${stamp},"attachment":{"type":"hook_success","hookEvent":"Stop","command":"echo live","durationMs":100,"exitCode":0}}`,
  ].join('\n'));
});
after(() => rmSync(home, { recursive: true, force: true }));

test('every contract channel has exactly one handler, and a duplicate or unknown one is refused', () => {
  assert.deepEqual(missingChannels(table), []);
  assert.deepEqual(Object.keys(table).sort(), [...CHANNELS].sort());
  assert.throws(() => buildHandlerTable({ a: { handlers: table as Handlers }, b: { handlers: table as Handlers } }), /more than one handler/);
  assert.throws(() => buildHandlerTable({ a: { handlers: { 'fs:read': () => 1 } as unknown as Handlers } }), /not in the IPC contract/);
});

test('a channel outside the allow-list is refused, including inherited object keys', async () => {
  for (const channel of ['fs:read-file', 'shell:exec', '__proto__', 'constructor', 'toString', '', 7, null]) {
    const reply = await dispatch(table, ctx, channel, { path: '/etc/hosts' });
    assert.deepEqual(reply, { ok: false, error: 'Not allowed.', status: 403 });
  }
});

test('inventory merges the usage scan once the worker finishes', async () => {
  assert.equal((await inventory()).usageStatus.state, 'scanning');
  const worker = startUsageScan(ctx.usage, usageWorkerPath(join(here, '../..')), { HOME: home });
  await new Promise((done, fail) => { worker.on('exit', done); worker.on('error', fail); });
  const inv = await inventory();
  assert.equal(inv.usageStatus.state, 'ready');
  assert.equal(inv.usageStatus.sessions?.claude, 1);
  assert.equal(inv.items.find((i) => i.name === 'keep')?.usage?.sessions, 1);
  assert.equal(inv.hooks.find((h) => h.command === 'echo live')?.usage?.runs, 1);
  assert.equal(inv.hooks.find((h) => h.command.includes('dead.sh'))?.dead, true);
  assert.equal(JSON.stringify(inv).includes(SECRET), false, 'settings values must never reach the renderer');
  assert.equal('totals' in inv.usageStatus, false);
});

test('item:read takes an id and refuses anything else', async () => {
  const keep = await find('keep');
  assert.match((await ok('item:read', { id: keep!.id })).text, /body/);
  await fails('item:read', { id: 'claude:skill:local:nope' }, 404, /no longer exists/);
  await fails('item:read', { id: '/etc/hosts' }, 404, /no longer exists/);
  await fails('item:read', { id: 7 }, 400, /Bad request/);
  await fails('item:read', undefined, 400, /Bad request/);
});

test('add then undo a skill in both CLIs, with the UserError message kept', async () => {
  const entry = await ok('skill:add', { clis: ['claude', 'codex'], name: 'quick', description: 'use: "when" asked', body: 'do it' });
  assert.ok(await find('quick') && await find('quick', 'codex'));
  assert.equal((await ok('history:list'))[0]?.id, entry.id);
  await ok('journal:undo', { id: entry.id });
  assert.equal(await find('quick'), undefined);
  await fails('journal:undo', { id: entry.id }, 409, /already undone/);
});

test('bad input comes back as a readable error, not a crash', async () => {
  for (const name of ['../evil', 'a/b', '.hidden', 'UP', '']) {
    await fails('skill:add', { clis: ['claude'], name, description: 'x' }, 400, /lowercase/);
  }
  await fails('skill:add', { clis: ['claude'], name: 'keep', description: 'x' }, 409, /already has/);
  await fails('agent:add', { clis: ['claude'], name: '../../x', description: 'x' }, 400, /lowercase/);
  await fails('skill:add', { clis: ['nope'], name: 'ok-name', description: 'x' }, 400, /Unknown CLI/);
  await fails('skill:add', { clis: [], name: 'ok-name', description: 'x' }, 400, /at least one/);
  await fails('skill:add', 'text', 400, /Bad request/);
  await fails('hook:add', { clis: ['codex'], event: 'TeammateIdle', command: 'x' }, 400, /no TeammateIdle/);
  await fails('hook:remove-dead', { cli: 'nope' }, 400, /Unknown CLI/);
});

test('an oversized request is refused before any handler runs', async () => {
  await fails('skill:add', { clis: ['claude'], name: 'big', description: 'x'.repeat(300 * 1024) }, 413, /too large/);
  assert.equal(await find('big'), undefined);
});

test('removing a linked skill leaves its target, undo restores the link', async () => {
  const linked = await find('linked');
  const entry = await ok('item:remove', { id: linked!.id });
  assert.equal(existsSync(join(home, '.claude/skills/linked')), false);
  assert.ok(existsSync(join(home, 'shared/linked/SKILL.md')));
  await ok('journal:undo', { id: entry.id });
  assert.ok(await find('linked'));
});

test('hook add, remove-dead and copy are each one undoable step', async () => {
  const added = await ok('hook:add', { clis: ['claude'], event: 'PreToolUse', matcher: 'Edit', command: 'echo one', timeout: 5 });
  assert.equal((await inventory()).hooks.find((h) => h.command === 'echo one')?.timeout, 5);
  const dead = await ok('hook:remove-dead', { cli: 'claude' });
  assert.equal((await inventory()).hooks.filter((h) => h.dead).length, 0);
  await ok('journal:undo', { id: dead.id });
  assert.equal((await inventory()).hooks.filter((h) => h.dead).length, 1);
  const rev = await find('rev');
  const copied = await ok('item:copy', { id: rev!.id });
  assert.ok(await find('rev', 'codex'));
  await ok('journal:undo', { id: copied.id });
  assert.equal(await find('rev', 'codex'), undefined);
  await ok('journal:undo', { id: added.id });
});

test('plugin-owned items cannot be removed (403 keeps its status)', async () => {
  mkdirSync(join(home, 'plug/skills/plug-skill'), { recursive: true });
  writeFileSync(join(home, 'plug/skills/plug-skill/SKILL.md'), '---\nname: plug-skill\ndescription: p\n---\n');
  mkdirSync(join(home, '.claude/plugins'), { recursive: true });
  writeFileSync(join(home, '.claude/plugins/installed_plugins.json'), JSON.stringify({ plugins: { 'plug@m': [{ installPath: join(home, 'plug') }] } }));
  const settings = JSON.parse(readFileSync(ctx.roots.claude.hookFile, 'utf8'));
  writeFileSync(ctx.roots.claude.hookFile, JSON.stringify({ ...settings, enabledPlugins: { 'plug@m': true } }));
  const item = await find('plug-skill');
  await fails('item:remove', { id: item!.id }, 403, /belongs to a plugin/);
  writeFileSync(ctx.roots.claude.hookFile, JSON.stringify(settings));
});

test('a folder source previews then installs; a non-GitHub URL is refused', async () => {
  mkdirSync(join(home, 'src/pack/one/.git'), { recursive: true });
  writeFileSync(join(home, 'src/pack/one/SKILL.md'), '---\nname: one\ndescription: first\n---\n');
  writeFileSync(join(home, 'src/pack/one/.git/secret'), 'x');
  const preview = await ok('source:preview', { source: join(home, 'src/pack') });
  assert.deepEqual(preview.skills.map((s) => s.name), ['one']);
  const entry = await ok('source:install', { sourceId: preview.sourceId, names: ['one'], clis: ['codex'] });
  assert.ok(await find('one', 'codex'));
  assert.equal(existsSync(join(home, '.codex/skills/one/.git')), false);
  await ok('journal:undo', { id: entry.id });
  await fails('source:preview', { source: 'https://evil.example/x/y' }, 400, /github.com/);
  await fails('source:install', { sourceId: preview.sourceId, names: 'one', clis: ['codex'] }, 400, /Bad request/);
});

test('unexpected errors are generic and never echo their message', async () => {
  const logged: unknown[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => { logged.push(...args); };
  try {
    const reply = await toReply(() => { throw new Error(`failed with ${SECRET}`); });
    assert.deepEqual(reply, { ok: false, error: 'Something went wrong. Nothing else was changed.', status: 500 });
    const missing = await toReply(() => { throw Object.assign(new Error(`ENOENT ${SECRET}`), { code: 'ENOENT' }); });
    assert.deepEqual(missing, { ok: false, error: 'Not found.', status: 404 });
  } finally { console.error = original; }
  assert.equal(JSON.stringify(logged).includes(SECRET), false);
});

// Type-level guard: the contract and the handlers agree (this file would not compile otherwise).
const _typed: IpcContract['journal:undo']['res'] = { label: '' };
void _typed;
