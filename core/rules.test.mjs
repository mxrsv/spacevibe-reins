// Runs only against temp folders. It must never see the real ~/.claude or ~/.codex.
import assert from 'node:assert/strict';
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { roots } from './inventory.mjs';
import { history, undo } from './mutate.mjs';
import {
  CAPABILITIES, addRule, capabilityGrid, changeVerdict, listRules, previewSetCapability, readCodexPermissions, removeRule, scopesFor, setCapability,
} from './rules.mjs';

const CANARY = 'canary-secret-9f3a1c';

function sandbox() {
  const home = mkdtempSync(join(tmpdir(), 'reins-rules-'));
  const env = { HOME: home, CLAUDE_CONFIG_DIR: join(home, '.claude'), CODEX_HOME: join(home, '.codex'), REINS_HOME: join(home, '.reins') };
  Object.assign(process.env, env);
  mkdirSync(env.CLAUDE_CONFIG_DIR, { recursive: true });
  mkdirSync(env.CODEX_HOME, { recursive: true });
  const r = roots(env);
  assert.ok(r.claude.hookFile.startsWith(home), 'sandbox must not point at a real config');
  return { home, r, file: r.claude.hookFile, done: () => rmSync(home, { recursive: true, force: true }) };
}

const GLOBAL = { kind: 'global' };
const bytes = (file) => readFileSync(file);
const rl = (verdict, rule) => ({ verdict, rule });
const stateOf = (rules, cap) => capabilityGrid(rules).find((c) => c.capability === cap).state;
const noTempFiles = (dir) => assert.deepEqual(readdirSync(dir).filter((f) => f.endsWith('.tmp')), []);

test('lists rules by scope and skips values that are not rules', () => {
  const s = sandbox();
  const proj = join(s.home, 'proj');
  mkdirSync(join(proj, '.claude'), { recursive: true });
  writeFileSync(s.file, JSON.stringify({ env: { TOKEN: CANARY }, permissions: { allow: ['Bash(npm test:*)', 42, 'not a rule!'], deny: ['Read(./.env)'] } }));
  writeFileSync(join(proj, '.claude/settings.json'), JSON.stringify({ permissions: { ask: ['Edit'] } }));
  writeFileSync(join(proj, '.claude/settings.local.json'), JSON.stringify({ permissions: { allow: ['WebFetch'] } }));
  const { rules, problems } = listRules(s.r, scopesFor(proj));
  assert.deepEqual(problems, []);
  assert.deepEqual(rules.map((x) => `${x.scope}:${x.verdict}:${x.rule}`), [
    'global:allow:Bash(npm test:*)', 'global:allow:not a rule!', 'global:deny:Read(./.env)', 'project:ask:Edit', 'local:allow:WebFetch',
  ]);
  assert.equal(rules[0].tool, 'Bash');
  assert.equal(rules[0].specifier, 'npm test:*');
  assert.equal(rules[1].tool, null);
  assert.deepEqual(listRules(s.r, [{ kind: 'local', dir: s.home }]).rules, []);
  assert.throws(() => listRules(s.r, [{ kind: 'project', dir: 'relative' }]), /absolute/);
  s.done();
});

test('add, change and remove keep other keys and the indent, and undo restores identical bytes', () => {
  const s = sandbox();
  for (const indent of ['    ', '\t']) {
    const text = `${JSON.stringify({ env: { TOKEN: CANARY }, model: 'x', permissions: { allow: ['Read'] }, hooks: {} }, null, indent)}\n`;
    writeFileSync(s.file, text, { mode: 0o640 });
    chmodSync(s.file, 0o640);
    const before = bytes(s.file);

    const added = addRule(s.r, { scope: GLOBAL, verdict: 'deny', rule: 'Bash(rm *)' });
    const afterAdd = bytes(s.file);
    const parsed = JSON.parse(afterAdd);
    assert.deepEqual(parsed.permissions, { allow: ['Read'], deny: ['Bash(rm *)'] });
    assert.deepEqual(parsed.env, { TOKEN: CANARY });
    assert.equal(parsed.model, 'x');
    assert.ok(afterAdd.toString().startsWith(`{\n${indent}"env"`), 'indent kept');
    assert.ok(afterAdd.toString().endsWith('}\n'));
    assert.equal(statSync(s.file).mode & 0o777, 0o640);

    const moved = changeVerdict(s.r, { scope: GLOBAL, rule: 'Bash(rm *)', from: 'deny', to: 'ask' });
    assert.deepEqual(JSON.parse(bytes(s.file)).permissions, { allow: ['Read'], deny: [], ask: ['Bash(rm *)'] });
    const removed = removeRule(s.r, { scope: GLOBAL, verdict: 'ask', rule: 'Bash(rm *)' });
    assert.deepEqual(JSON.parse(bytes(s.file)).permissions.ask, []);

    undo(s.r, { id: removed.id });
    undo(s.r, { id: moved.id });
    undo(s.r, { id: added.id });
    assert.ok(bytes(s.file).equals(before), 'undo restored the exact bytes');
    assert.equal(statSync(s.file).mode & 0o777, 0o640);
    noTempFiles(join(s.home, '.claude'));
  }
  s.done();
});

test('rules written into a file without a permissions block, and undo of a created file', () => {
  const s = sandbox();
  const proj = join(s.home, 'proj');
  mkdirSync(proj);
  const local = join(proj, '.claude/settings.local.json');
  const e = addRule(s.r, { scope: { kind: 'local', dir: proj }, verdict: 'allow', rule: 'Bash(git status)' });
  assert.deepEqual(JSON.parse(bytes(local)), { permissions: { allow: ['Bash(git status)'] } });
  assert.equal(statSync(local).mode & 0o777, 0o600);
  undo(s.r, { id: e.id });
  assert.equal(existsSync(local), false);

  writeFileSync(s.file, '{"model":"x"}');
  const before = bytes(s.file);
  const g = addRule(s.r, { scope: GLOBAL, verdict: 'allow', rule: 'WebSearch' });
  assert.equal(bytes(s.file).toString().endsWith('\n'), false, 'no trailing newline added when the file had none');
  undo(s.r, { id: g.id });
  assert.ok(bytes(s.file).equals(before));
  s.done();
});

test('a symlinked settings file stays a symlink and the target is edited', () => {
  const s = sandbox();
  const target = join(s.home, 'shared-settings.json');
  writeFileSync(target, '{}\n');
  symlinkSync(target, s.file);
  addRule(s.r, { scope: GLOBAL, verdict: 'allow', rule: 'Read' });
  assert.ok(lstatSync(s.file).isSymbolicLink());
  assert.deepEqual(JSON.parse(readFileSync(target, 'utf8')).permissions.allow, ['Read']);
  s.done();
});

test('refuses invalid JSON, wrong shapes and bad input without touching the file or leaking its text', () => {
  const s = sandbox();
  writeFileSync(s.file, `{"env":{"TOKEN":"${CANARY}"} oops`);
  const before = bytes(s.file);
  const attempts = [
    () => addRule(s.r, { scope: GLOBAL, verdict: 'allow', rule: 'Read' }),
    () => removeRule(s.r, { scope: GLOBAL, verdict: 'allow', rule: 'Read' }),
    () => setCapability(s.r, { scope: GLOBAL, capability: 'read', verdict: 'deny' }),
  ];
  for (const f of attempts) {
    assert.throws(f, (e) => /not valid JSON/.test(e.message) && !e.message.includes(CANARY) && e.status === 409);
  }
  assert.ok(bytes(s.file).equals(before));
  assert.match(listRules(s.r).problems[0], /not valid JSON/);
  assert.equal(history(s.r).length, 0);
  noTempFiles(join(s.home, '.claude'));

  writeFileSync(s.file, JSON.stringify({ permissions: { allow: 'Read' } }));
  assert.throws(() => addRule(s.r, { scope: GLOBAL, verdict: 'allow', rule: 'Bash' }), /not a list/);
  writeFileSync(s.file, '[]');
  assert.throws(() => addRule(s.r, { scope: GLOBAL, verdict: 'allow', rule: 'Bash' }), /JSON object/);

  writeFileSync(s.file, '{}');
  assert.throws(() => addRule(s.r, { scope: GLOBAL, verdict: 'maybe', rule: 'Bash' }), /Verdict/);
  for (const rule of ['', '   ', 'two\nlines', 'Bash(unclosed', '(x)', 'a'.repeat(1001)]) {
    assert.throws(() => addRule(s.r, { scope: GLOBAL, verdict: 'allow', rule }), /rule/i);
  }
  addRule(s.r, { scope: GLOBAL, verdict: 'allow', rule: 'Bash' });
  assert.throws(() => addRule(s.r, { scope: GLOBAL, verdict: 'deny', rule: 'Bash' }), /already in allow/);
  assert.throws(() => removeRule(s.r, { scope: GLOBAL, verdict: 'deny', rule: 'Bash' }), /already changed/);
  s.done();
});

test('undo refuses when the file changed after the edit', () => {
  const s = sandbox();
  writeFileSync(s.file, '{}\n');
  const e = addRule(s.r, { scope: GLOBAL, verdict: 'allow', rule: 'Read' });
  writeFileSync(s.file, '{"model":"hand-edited"}\n');
  assert.throws(() => undo(s.r, { id: e.id }), /changed since/);
  assert.equal(JSON.parse(readFileSync(s.file, 'utf8')).model, 'hand-edited');
  s.done();
});

test('capability grid, one row per mapping', () => {
  const state = (cap, ...rules) => stateOf(rules, cap);
  assert.deepEqual(capabilityGrid([]).map((c) => [c.capability, c.state]), CAPABILITIES.map((c) => [c, 'none']));
  // Read files and Secrets
  assert.equal(state('read', rl('allow', 'Read')), 'allow');
  assert.equal(state('secrets', rl('allow', 'Read')), 'allow', 'a bare Read also covers .env');
  assert.equal(state('read', rl('allow', 'Read(src/**)')), 'mixed');
  assert.equal(state('read', rl('deny', 'Read(./.env)')), 'none', 'a .env rule is not a Read files rule');
  assert.equal(state('secrets', rl('deny', 'Read(./.env)')), 'deny');
  assert.equal(state('secrets', rl('deny', 'Read(**/.env*)')), 'deny');
  assert.equal(state('secrets', rl('allow', 'Read(./.env)'), rl('ask', 'Read(./.env.*)')), 'mixed');
  assert.equal(state('secrets', rl('allow', 'Read'), rl('deny', 'Read(./.env)')), 'deny');
  assert.equal(state('read', rl('allow', 'Read'), rl('deny', 'Read(./.env)')), 'allow');
  // Edit files
  assert.equal(state('edit', rl('ask', 'Edit')), 'ask');
  assert.equal(state('edit', rl('allow', 'MultiEdit')), 'allow');
  assert.equal(state('edit', rl('deny', 'Write')), 'deny');
  assert.equal(state('edit', rl('ask', 'Edit'), rl('allow', 'Write(src/**)')), 'ask');
  assert.equal(state('edit', rl('deny', 'Edit(secrets/**)')), 'mixed');
  assert.equal(state('edit', rl('deny', 'Write'), rl('allow', 'Edit(a)')), 'deny');
  assert.equal(state('edit', rl('allow', 'Edit'), rl('ask', 'Edit(docs/**)')), 'mixed');
  // Run commands and Push and deploy
  assert.equal(state('run', rl('allow', 'Bash')), 'allow');
  assert.equal(state('run', rl('allow', 'Bash(*)')), 'allow');
  assert.equal(state('push', rl('allow', 'Bash')), 'allow', 'a bare Bash also covers push');
  assert.equal(state('run', rl('allow', 'Bash(npm test:*)')), 'mixed');
  assert.equal(state('push', rl('allow', 'Bash(npm test:*)')), 'none');
  assert.equal(state('run', rl('allow', 'Bash'), rl('allow', 'Bash(ls)')), 'allow');
  assert.equal(state('run', rl('allow', 'Bash'), rl('deny', 'Bash(rm *)')), 'mixed');
  assert.equal(state('run', rl('ask', 'Bash'), rl('allow', 'Bash(ls)')), 'ask');
  assert.equal(state('run', rl('ask', 'Bash'), rl('deny', 'Bash(rm *)')), 'mixed');
  assert.equal(state('run', rl('allow', 'Bash'), rl('deny', 'Bash')), 'deny', 'deny beats allow');
  assert.equal(state('run', rl('allow', 'Bash'), rl('ask', 'Bash')), 'ask', 'ask beats allow');
  const pushDeny = [rl('allow', 'Bash'), rl('deny', 'Bash(git push:*)')];
  assert.equal(stateOf(pushDeny, 'run'), 'allow');
  assert.equal(stateOf(pushDeny, 'push'), 'deny');
  assert.equal(state('push', rl('deny', 'Bash'), rl('allow', 'Bash(git push *)')), 'deny');
  assert.equal(state('push', rl('allow', 'Bash(vercel deploy)')), 'allow');
  assert.equal(state('push', rl('allow', 'Bash(npm publish)')), 'allow');
  assert.equal(state('push', rl('allow', 'Bash(git push *)'), rl('deny', 'Bash(vercel *)')), 'mixed');
  assert.equal(state('run', rl('allow', 'Bash(git push *)')), 'none', 'push rules are not Run commands rules');
  // Network
  assert.equal(state('network', rl('deny', 'WebFetch')), 'deny');
  assert.equal(state('network', rl('allow', 'WebSearch')), 'allow');
  assert.equal(state('network', rl('allow', 'WebSearch'), rl('allow', 'WebFetch(domain:a.dev)')), 'allow');
  assert.equal(state('network', rl('allow', 'WebFetch(domain:a.dev)')), 'mixed');
  // Rules that belong to no cell
  assert.deepEqual(capabilityGrid([rl('allow', 'mcp__x__y'), rl('allow', 'Skill(a)'), rl('allow', '???')]).map((c) => c.state), CAPABILITIES.map(() => 'none'));
  // The concrete rules behind a cell, and editable
  const cell = capabilityGrid([rl('allow', 'Bash'), rl('deny', 'Bash(rm *)')]).find((c) => c.capability === 'run');
  assert.deepEqual(cell.rules.map((x) => x.rule), ['Bash', 'Bash(rm *)']);
  assert.equal(cell.editable, false);
});

test('previewSetCapability and setCapability replace the cell rules, journaled and undoable', () => {
  const s = sandbox();
  writeFileSync(s.file, `${JSON.stringify({ model: 'x', permissions: { allow: ['Bash', 'Read(./.env)', 'WebFetch'], ask: ['Edit'], deny: ['Bash(git push *)'] } }, null, 2)}\n`);
  const before = bytes(s.file);

  const prev = previewSetCapability(s.r, { scope: GLOBAL, capability: 'run', verdict: 'deny' });
  assert.deepEqual(prev.replaces, [rl('allow', 'Bash')]);
  assert.deepEqual(prev.writes, [rl('deny', 'Bash')]);
  assert.equal(prev.current, 'allow');
  assert.equal(prev.resulting, 'deny');
  assert.ok(bytes(s.file).equals(before), 'preview writes nothing');

  setCapability(s.r, { scope: GLOBAL, capability: 'run', verdict: 'deny' });
  const perms = JSON.parse(bytes(s.file)).permissions;
  assert.deepEqual(perms.allow, ['Read(./.env)', 'WebFetch']);
  assert.deepEqual(perms.deny, ['Bash(git push *)', 'Bash']);

  const net = setCapability(s.r, { scope: GLOBAL, capability: 'network', verdict: 'ask' });
  assert.deepEqual(JSON.parse(bytes(s.file)).permissions.ask, ['Edit', 'WebFetch', 'WebSearch']);
  undo(s.r, { id: net.id });
  assert.deepEqual(JSON.parse(bytes(s.file)).permissions.ask, ['Edit']);

  const edit = previewSetCapability(s.r, { scope: GLOBAL, capability: 'edit', verdict: 'allow' });
  assert.deepEqual(edit.replaces, [rl('ask', 'Edit')]);
  assert.equal(setCapability(s.r, { scope: GLOBAL, capability: 'edit', verdict: 'ask' }), null, 'already that value: no write, no journal entry');

  const entries = history(s.r);
  assert.equal(entries.length, 2);
  undo(s.r, { id: entries[1].id });
  assert.ok(bytes(s.file).equals(before));
  noTempFiles(join(s.home, '.claude'));
  s.done();
});

test('push and secrets cells write their canonical rules and report a rule that still wins', () => {
  const s = sandbox();
  writeFileSync(s.file, JSON.stringify({ permissions: { deny: ['Bash'], allow: ['Read'] } }));
  const push = previewSetCapability(s.r, { scope: GLOBAL, capability: 'push', verdict: 'allow' });
  assert.deepEqual(push.replaces, [], 'bare Bash belongs to Run commands and is kept');
  assert.deepEqual(push.writes.map((x) => x.rule), ['Bash(git push *)', 'Bash(vercel *)']);
  assert.equal(push.resulting, 'deny', 'the bare Bash deny still wins');

  const sec = setCapability(s.r, { scope: GLOBAL, capability: 'secrets', verdict: 'deny' });
  assert.deepEqual(JSON.parse(bytes(s.file)).permissions.deny, ['Bash', 'Read(./.env)', 'Read(./.env.*)']);
  assert.equal(stateOf(listRules(s.r).rules, 'secrets'), 'deny');
  assert.equal(stateOf(listRules(s.r).rules, 'read'), 'allow');
  setCapability(s.r, { scope: GLOBAL, capability: 'secrets', verdict: 'ask' });
  const p = JSON.parse(bytes(s.file)).permissions;
  assert.deepEqual(p.deny, ['Bash']);
  assert.deepEqual(p.ask, ['Read(./.env)', 'Read(./.env.*)']);
  assert.ok(sec.label.includes('Secrets'));
  s.done();
});

test('a mixed cell is refused for preview and write, and nothing changes', () => {
  const s = sandbox();
  writeFileSync(s.file, JSON.stringify({ permissions: { allow: ['Bash', 'Edit(src/**)'], deny: ['Bash(rm *)'] } }));
  const before = bytes(s.file);
  for (const capability of ['run', 'edit']) {
    assert.throws(() => previewSetCapability(s.r, { scope: GLOBAL, capability, verdict: 'allow' }), (e) => /no single value/.test(e.message) && e.status === 409);
    assert.throws(() => setCapability(s.r, { scope: GLOBAL, capability, verdict: 'deny' }), /no single value/);
  }
  assert.throws(() => setCapability(s.r, { scope: GLOBAL, capability: 'nope', verdict: 'deny' }), /Unknown capability/);
  assert.ok(bytes(s.file).equals(before));
  assert.equal(history(s.r).length, 0);
  s.done();
});

test('a cell write in a project scope only touches that project file', () => {
  const s = sandbox();
  const proj = join(s.home, 'proj');
  mkdirSync(join(proj, '.claude'), { recursive: true });
  writeFileSync(s.file, JSON.stringify({ permissions: { allow: ['Bash'] } }));
  const globalBefore = bytes(s.file);
  const scope = { kind: 'project', dir: proj };
  setCapability(s.r, { scope, capability: 'run', verdict: 'deny' });
  assert.deepEqual(JSON.parse(readFileSync(join(proj, '.claude/settings.json'), 'utf8')), { permissions: { deny: ['Bash'] } });
  assert.ok(bytes(s.file).equals(globalBefore));
  const merged = listRules(s.r, scopesFor(proj)).rules;
  assert.equal(stateOf(merged, 'run'), 'deny', 'a project deny beats a global allow');
  s.done();
});

test('Codex reader: legacy model', () => {
  const s = sandbox();
  mkdirSync(join(s.home, '.codex/rules'));
  writeFileSync(join(s.home, '.codex/config.toml'), `
# comment
approval_policy = "never"   # trailing comment
sandbox_mode = "danger-full-access"
approvals_reviewer = "user"
model = "gpt-x"
developer_instructions = """
approval_policy = "on-request"
[permissions.fake]
"""

[sandbox_workspace_write]
network_access = true
writable_roots = [
  "/tmp/a",
  "/tmp/b", # note
]

[projects."/Users/me/app"]
trust_level = "trusted"

[projects."/Users/me/weird]path"]
trust_level = "untrusted"

[projects]
"/Users/me/inline" = { trust_level = "trusted" }

[mcp_servers.github]
command = "npx"
[mcp_servers.github.env]
GITHUB_TOKEN = "${CANARY}"

[shell_environment_policy]
set = { API_KEY = "${CANARY}" }
`);
  writeFileSync(join(s.home, '.codex/rules/default.rules'), `
# prefix_rule(pattern=["x"], decision="forbidden")
prefix_rule(pattern=["git", "status"], decision="allow")
prefix_rule(
  pattern=["rm"],
  decision="forbidden",
)
prefix_rule(pattern=["curl", "${CANARY}"], decision="prompt")
prefix_rule(pattern=["ls"])
`);
  const c = readCodexPermissions(s.r);
  assert.equal(c.present, true);
  assert.equal(c.model, 'legacy');
  assert.equal(c.approval_policy, 'never');
  assert.equal(c.sandbox_mode, 'danger-full-access');
  assert.equal(c.unrestricted, true);
  assert.equal(c.approvals_reviewer, 'user');
  assert.deepEqual(c.sandbox_workspace_write, { network_access: true, writable_roots: ['/tmp/a', '/tmp/b'] });
  assert.deepEqual(c.projects, [
    { path: '/Users/me/app', trust_level: 'trusted' }, { path: '/Users/me/weird]path', trust_level: 'untrusted' }, { path: '/Users/me/inline', trust_level: 'trusted' },
  ]);
  assert.deepEqual(c.profiles, []);
  assert.deepEqual(c.warnings, []);
  assert.deepEqual(c.rules, { files: 1, allow: 2, prompt: 1, forbidden: 1, other: 0 });
  assert.equal(JSON.stringify(c).includes(CANARY), false, 'nothing from mcp_servers, env tables or rule patterns');
  s.done();
});

test('Codex reader: profiles model, granular approval policy, and missing config', () => {
  const s = sandbox();
  assert.deepEqual(
    (({ present, model, unrestricted, profiles, projects, rules }) => ({ present, model, unrestricted, profiles, projects, rules }))(readCodexPermissions(s.r)),
    { present: false, model: 'legacy', unrestricted: false, profiles: [], projects: [], rules: { files: 0, allow: 0, prompt: 0, forbidden: 0, other: 0 } },
  );
  writeFileSync(join(s.home, '.codex/config.toml'), `
default_permissions = "dev"

[approval_policy.granular]
sandbox_approval = true
rules = false

[permissions.dev.filesystem]
"/tmp" = "write"
"~/.ssh" = "none"

[permissions.dev.network]
enabled = true
mode = "limited"

[permissions.strict.filesystem]
"/" = "read"
`);
  const c = readCodexPermissions(s.r);
  assert.equal(c.model, 'profiles');
  assert.equal(c.default_permissions, 'dev');
  assert.equal(c.sandbox_mode, null);
  assert.equal(c.unrestricted, false);
  assert.deepEqual(c.approval_policy, { granular: { sandbox_approval: true, rules: false } });
  assert.deepEqual(c.profiles, [
    { name: 'dev', filesystemEntries: 2, networkEntries: 2, networkFlags: { enabled: true, mode: 'limited' } },
    { name: 'strict', filesystemEntries: 1, networkEntries: 0, networkFlags: {} },
  ]);
  assert.equal(c.sandbox_workspace_write, null);
  s.done();
});

test('Codex reader: both models set warns', () => {
  const s = sandbox();
  writeFileSync(join(s.home, '.codex/config.toml'), 'default_permissions = "dev"\nsandbox_mode = "workspace-write"\napproval_policy = { granular = { rules = true } }\n[permissions.dev.network]\nenabled = false\n');
  const c = readCodexPermissions(s.r);
  assert.equal(c.model, 'both');
  assert.equal(c.warnings.length, 1);
  assert.match(c.warnings[0], /default_permissions and sandbox_mode/);
  assert.equal(c.unrestricted, false);
  assert.deepEqual(c.approval_policy, { granular: { rules: true } });
  s.done();
});

test('a secret in settings never appears in any return value, error, label or journal', () => {
  const s = sandbox();
  const proj = join(s.home, 'proj');
  mkdirSync(join(proj, '.claude'), { recursive: true });
  const secret = { env: { TOKEN: CANARY }, apiKeyHelper: `echo ${CANARY}`, permissions: { allow: ['Read'] } };
  writeFileSync(s.file, JSON.stringify(secret, null, 2));
  writeFileSync(join(proj, '.claude/settings.json'), JSON.stringify(secret));
  const seen = [];
  const keep = (v) => { seen.push(JSON.stringify(v)); return v; };
  const scopes = scopesFor(proj);
  keep(listRules(s.r, scopes));
  keep(capabilityGrid(listRules(s.r, scopes).rules));
  keep(previewSetCapability(s.r, { scope: GLOBAL, capability: 'run', verdict: 'ask' }));
  const a = keep(addRule(s.r, { scope: GLOBAL, verdict: 'deny', rule: 'Bash(rm *)' }));
  const b = keep(changeVerdict(s.r, { scope: GLOBAL, rule: 'Bash(rm *)', from: 'deny', to: 'ask' }));
  keep(setCapability(s.r, { scope: { kind: 'project', dir: proj }, capability: 'network', verdict: 'deny' }));
  keep(removeRule(s.r, { scope: GLOBAL, verdict: 'ask', rule: 'Bash(rm *)' }));
  keep(history(s.r));
  keep(readCodexPermissions(s.r));
  writeFileSync(s.file, `{"env":{"T":"${CANARY}"`);
  try { addRule(s.r, { scope: GLOBAL, verdict: 'allow', rule: 'Read' }); } catch (e) { seen.push(e.message); }
  try { undo(s.r, { id: a.id }); } catch (e) { seen.push(e.message); } // file was hand-edited, so undo refuses
  assert.ok(seen.length > 5 && b);
  for (const text of seen) assert.equal(text.includes(CANARY), false);
  assert.equal(readFileSync(join(s.home, '.reins/journal.json'), 'utf8').includes(CANARY), false);
  s.done();
});
