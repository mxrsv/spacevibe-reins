// Golden section "rules": what core/rules.mjs returns, for the Swift RulesStore and CodexPermissions to match.
//
//   node scripts/make-golden.mjs rules
//
// Three kinds of case, all synthetic (AGENTS.md S-R2):
//   shared   the shared fixture HOME (Fixtures/home, read only): rules, capability grid and every capability preview per
//            scope of its three projects.
//   main     a section-specific HOME written by this script to Fixtures/rules-home/main (the shared tree and
//            scripts/fixture-home.mjs stay untouched). Adds what the shared tree lacks: a project without settings, a broken
//            and a wrong-shaped settings file, `"permissions": null`, mixed and own-rule cells, a Codex config that sets both
//            permission models, and a canary secret in env keys. Read cases run on it like on `shared`, and every write case
//            runs on a fresh copy of it.
//   codex    Codex configs for the cases `main` does not cover, one folder each under Fixtures/rules-home/codex-<name>.
//
// Fixtures/rules-home holds `$HOME` where a path belongs (the Codex project tables); both sides replace it with the folder
// they build the copy in, so the golden contains `$HOME` only.
//
// Output: Fixtures/golden/rules.json, Fixtures/rules-home/**. Idempotent: no time, id or random value reaches either.
//
// Differences from Node that the golden already irons out (the Swift side is the intended behavior):
//   - preview: no `file` and no absolute `scope`; `scopeLabel` is the short file label.
//   - the refusal for a file that is not valid settings read ". Nothing was changed" after a full stop; one stop is kept.
//   - a write is checked by the parsed settings JSON, not the bytes: Node rewrites the file with JSON.stringify, Swift edits
//     only the changed list. Byte-level behavior (indent, CRLF, mode, undo) is tested in Swift directly.
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { roots } from '../../core/inventory.mjs';
import { UserError } from '../../core/mutate.mjs';
import {
  CAPABILITIES, VERDICTS, addRule, capabilityGrid, changeVerdict, listRules, previewSetCapability, readCodexPermissions, removeRule, setCapability,
} from '../../core/rules.mjs';

export const name = 'rules';

const FIXTURES = resolve(import.meta.dirname, '../../Tests/ReinsCoreTests/Fixtures');
const RULES_HOME = join(FIXTURES, 'rules-home');
const TOKEN = '$HOME';
const CANARY = 'canary-secret-9f3a1c';

// ---- the fixture homes ------------------------------------------------------------------------------------------

const json = (v) => `${JSON.stringify(v, null, 2)}\n`;

const MAIN_FILES = {
  '.claude/settings.json': json({
    env: { API_TOKEN: CANARY },
    apiKeyHelper: `echo ${CANARY}`,
    permissions: {
      allow: ['Read', 'Edit', 'WebSearch', 'Bash(git status:*)', 'mcp__demo__lookup', 42, 'not a rule!'],
      ask: ['Bash(git push *)', 'Read(./.env)'],
      deny: ['WebFetch(domain:blocked.example)'],
    },
  }),
  'proj-open/.claude/settings.json': json({ model: 'demo', permissions: { allow: ['Bash'], deny: ['Bash(git push *)', 'Read(./.env)'] } }),
  'proj-open/.claude/settings.local.json': json({ permissions: { ask: ['Edit', 'WebFetch', 'Bash(npm test *)'] } }),
  'proj-bare/.claude/notes.md': 'A project folder with a .claude folder and no settings file.\n',
  'proj-broken/.claude/settings.json': `{"env": {"TOKEN": "${CANARY}"} oops`,
  'proj-broken/.claude/settings.local.json': json({ permissions: { allow: 'Read' } }),
  'proj-null/.claude/settings.json': json({ model: 'demo', permissions: null }),
  '.codex/config.toml': `approval_policy = "never"
sandbox_mode = "danger-full-access"
default_permissions = "dev"
approvals_reviewer = "user"
developer_instructions = """
sandbox_mode = "read-only"
[permissions.fake]
"""

[sandbox_workspace_write]
network_access = true
writable_roots = ["/work/a", "/work/b"]

[permissions.dev.filesystem]
"/work" = "write"
"~/.ssh" = "none"

[permissions.dev.network]
enabled = true
mode = "limited"

[permissions.strict.filesystem]
"/" = "read"

[projects."${TOKEN}/proj-open"]
trust_level = "trusted"

[projects."${TOKEN}/proj-bare"]
trust_level = "untrusted"

[projects."${TOKEN}/proj-broken"]
trust_level = "trusted"

[projects."${TOKEN}/proj-null"]
trust_level = "trusted"

[projects]
"/work/inline" = { trust_level = "trusted" }

[mcp_servers.github]
command = "npx"

[mcp_servers.github.env]
GITHUB_TOKEN = "${CANARY}"

[shell_environment_policy]
set = { API_KEY = "${CANARY}" }
`,
  '.codex/rules/default.rules': `# prefix_rule(pattern=["x"], decision="forbidden")
prefix_rule(pattern=["git", "status"], decision="allow")
prefix_rule(
  pattern=["rm"],
  decision="forbidden",
)
prefix_rule(pattern=["curl", "${CANARY}"], decision="prompt")
prefix_rule(pattern=["ls"])
prefix_rule(pattern=["make"], decision="maybe")
`,
};

const CODEX_CASES = {
  legacy: {
    '.codex/config.toml': `# comment
approval_policy = "never"   # trailing comment
sandbox_mode = "workspace-write"
approvals_reviewer = "user"
model = "demo-model"
developer_instructions = """
approval_policy = "on-request"
[permissions.fake]
"""

[sandbox_workspace_write]
network_access = false
writable_roots = [
  "/work/a",
  "/work/b", # note
]

[projects."/work/app"]
trust_level = "trusted"

[projects."/work/weird]path"]
trust_level = "untrusted"

[projects]
"/work/inline" = { trust_level = "trusted" }

[mcp_servers.github]
command = "npx"
[mcp_servers.github.env]
GITHUB_TOKEN = "${CANARY}"

[shell_environment_policy]
set = { API_KEY = "${CANARY}" }
`,
    '.codex/rules/default.rules': 'prefix_rule(pattern=["git", "push"], decision="prompt")\n',
  },
  profiles: {
    '.codex/config.toml': `default_permissions = "dev"

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
`,
  },
  inline: {
    '.codex/config.toml': 'default_permissions = "dev"\napproval_policy = { granular = { rules = true, sandbox_approval = false } }\nsandbox_workspace_write = { network_access = true, writable_roots = ["/work/x"] }\n[permissions.dev.network]\nenabled = false\n',
  },
  quirks: {
    '.codex/config.toml': `approval_policy = "on-request"
approval_policy = "never"
sandbox_mode = "read-only"

[[hooks]]
sandbox_mode = "danger-full-access"
approval_policy = "untrusted"

[permissions.quiet]

[permissions.noisy.network]
"bad key" = true
ok-key = "yes"

[projects."/work/one"]
trust_level = "trusted"

[projects."/work/one"]
trust_level = "untrusted"

[projects."/work/two"]
note = "no trust level here"

[sandbox_workspace_write]
writable_roots = ["/work/y"]
`,
    '.codex/rules/a.rules': 'prefix_rule(pattern=["a"], decision="allow")\nprefix_rule(pattern=["b"], decision="forbidden")\n',
    '.codex/rules/b.rules': 'prefix_rule(pattern=["c"], decision="forbidden")\n',
    '.codex/rules/notes.txt': 'prefix_rule(pattern=["d"], decision="forbidden")\n',
  },
};

function writeFixtures() {
  if (relative(FIXTURES, RULES_HOME).startsWith('..')) throw new Error('unexpected fixtures path');
  rmSync(RULES_HOME, { recursive: true, force: true });
  const put = (base, files) => {
    for (const [rel, text] of Object.entries(files)) {
      const target = join(base, rel);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, text);
    }
  };
  put(join(RULES_HOME, 'main'), MAIN_FILES);
  for (const [caseName, files] of Object.entries(CODEX_CASES)) put(join(RULES_HOME, `codex-${caseName}`), files);
}

const walk = (dir, out = []) => {
  for (const e of readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.isFile()) out.push(p);
  }
  return out;
};

// A copy of a rules-home folder in a new temp folder, `$HOME` replaced by that folder's real path.
function materialize(sub) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'reins-rules-golden-')));
  const source = join(RULES_HOME, sub);
  for (const file of walk(source)) {
    const target = join(root, relative(source, file));
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, readFileSync(file, 'utf8').replaceAll(TOKEN, root));
  }
  mkdirSync(join(root, '.reins'), { recursive: true });
  const env = { HOME: root, CLAUDE_CONFIG_DIR: join(root, '.claude'), CODEX_HOME: join(root, '.codex'), REINS_HOME: join(root, '.reins'), REINS_TEST: '1' };
  return { root, r: roots(env), done: () => rmSync(root, { recursive: true, force: true }) };
}

// ---- running the Node functions --------------------------------------------------------------------------------

const clean = (value, root) => JSON.parse(JSON.stringify(value ?? null).replaceAll(root, TOKEN));
const fixDoubleStop = (message) => message.replace('.. Nothing was changed.', '. Nothing was changed.');
const attempt = (fn, root) => {
  try { return { ok: clean(fn(), root) }; } catch (e) {
    if (!(e instanceof UserError)) throw e;
    return { error: { status: e.status, message: clean(fixDoubleStop(e.message), root) } };
  }
};

const scopeOf = (root, spec) => (spec.kind === 'global' ? { kind: 'global' } : { kind: spec.kind, dir: join(root, spec.rel) });
const specKey = (spec) => (spec.kind === 'global' ? 'global' : `${spec.kind}:${spec.rel}`);
const FILE_LABEL = { global: '~/.claude/settings.json', project: '.claude/settings.json', local: '.claude/settings.local.json' };
const ruleView = (x) => ({ id: x.id, scope: x.scope, dir: x.dir, file: x.file, verdict: x.verdict, rule: x.rule, tool: x.tool, specifier: x.specifier });
const gridView = (grid) => grid.map((c) => ({ capability: c.capability, label: c.label, state: c.state, editable: c.editable, rules: c.rules.map((x) => x.id) }));

// Lists, grids (one scope and, for projects, the three scopes merged) and every capability preview.
function readCases(r, root, specs) {
  const out = { lists: {}, grids: {}, merged: {}, previews: {} };
  for (const spec of specs) {
    const scope = scopeOf(root, spec);
    const key = specKey(spec);
    const listed = listRules(r, [scope]);
    out.lists[key] = clean({ rules: listed.rules.map(ruleView), problems: listed.problems }, root);
    out.grids[key] = clean(gridView(capabilityGrid(listed.rules)), root);
    for (const capability of CAPABILITIES) {
      for (const verdict of VERDICTS) {
        out.previews[`${key}|${capability}|${verdict}`] = attempt(() => {
          const p = previewSetCapability(r, { scope, capability, verdict });
          return { capability: p.capability, verdict: p.verdict, scopeLabel: FILE_LABEL[scope.kind], current: p.current, resulting: p.resulting, replaces: p.replaces, writes: p.writes };
        }, root);
      }
    }
    if (spec.kind === 'project') {
      const merged = listRules(r, [{ kind: 'global' }, scope, { kind: 'local', dir: scope.dir }]);
      out.merged[spec.rel] = clean(gridView(capabilityGrid(merged.rules)), root);
    }
  }
  return out;
}

const codexView = (r, root) => {
  const { file: _file, ...rest } = readCodexPermissions(r);
  return clean(rest, root);
};

// ---- write cases ------------------------------------------------------------------------------------------------

const G = { kind: 'global' };
const P = (rel) => ({ kind: 'project', rel });
const L = (rel) => ({ kind: 'local', rel });

function writeCases() {
  const cases = [];
  const add = (scope, fn, args) => cases.push({ scope, fn, args });
  for (const scope of [G, P('proj-open'), L('proj-open'), P('proj-bare'), L('proj-bare'), P('proj-null')]) {
    for (const capability of CAPABILITIES) for (const verdict of VERDICTS) add(scope, 'setCapability', { capability, verdict });
  }
  add(G, 'addRule', { verdict: 'allow', rule: 'Bash(npm test *)' });
  add(G, 'addRule', { verdict: 'deny', rule: '  Read(src/**)  ' });
  add(G, 'addRule', { verdict: 'ask', rule: 'WebSearch' });
  add(G, 'addRule', { verdict: 'deny', rule: 'mcp__demo__lookup' });
  for (const rule of ['', '   ', 'two\nlines', 'Bash(unclosed', '(x)', 'a'.repeat(1001), 'Bash()']) add(G, 'addRule', { verdict: 'allow', rule });
  add(G, 'removeRule', { verdict: 'ask', rule: 'Bash(git push *)' });
  add(G, 'removeRule', { verdict: 'allow', rule: 'not a rule!' });
  add(G, 'removeRule', { verdict: 'deny', rule: 'Read' });
  add(G, 'changeVerdict', { rule: 'Read', from: 'allow', to: 'deny' });
  add(G, 'changeVerdict', { rule: 'Read', from: 'allow', to: 'allow' });
  add(G, 'changeVerdict', { rule: 'Read', from: 'ask', to: 'deny' });
  add(P('proj-open'), 'addRule', { verdict: 'allow', rule: 'WebFetch(domain:example.dev)' });
  add(P('proj-open'), 'removeRule', { verdict: 'deny', rule: 'Read(./.env)' });
  add(L('proj-open'), 'changeVerdict', { rule: 'Edit', from: 'ask', to: 'allow' });
  add(P('proj-bare'), 'addRule', { verdict: 'allow', rule: 'Bash(git status)' });
  add(L('proj-bare'), 'addRule', { verdict: 'deny', rule: 'Read(./.env)' });
  add(P('proj-null'), 'addRule', { verdict: 'ask', rule: 'Bash(rm *)' });
  for (const scope of [P('proj-broken'), L('proj-broken')]) {
    add(scope, 'addRule', { verdict: 'allow', rule: 'Read' });
    add(scope, 'removeRule', { verdict: 'allow', rule: 'Read' });
    add(scope, 'setCapability', { capability: 'read', verdict: 'deny' });
  }
  return cases;
}

const RUN = {
  addRule: (r, scope, a) => addRule(r, { scope, ...a }),
  removeRule: (r, scope, a) => removeRule(r, { scope, ...a }),
  changeVerdict: (r, scope, a) => changeVerdict(r, { scope, ...a }),
  setCapability: (r, scope, a) => setCapability(r, { scope, ...a }),
};

// The settings files of a home, parsed. A file that is not JSON is recorded as a sentinel, never as its text.
function settingsAfter(root) {
  const out = {};
  for (const file of walk(root)) {
    const rel = relative(root, file);
    if (!rel.endsWith('.json') || rel.startsWith('.reins')) continue;
    try { out[rel] = JSON.parse(readFileSync(file, 'utf8')); } catch { out[rel] = '<not JSON>'; }
  }
  return out;
}

function runWrite(c) {
  const home = materialize('main');
  try {
    const outcome = attempt(() => {
      const entry = RUN[c.fn](home.r, scopeOf(home.root, c.scope), c.args);
      return entry && { label: entry.label, ops: entry.ops.map((op) => ({ type: op.type, existed: op.existed })) };
    }, home.root);
    return { ...c, expected: { ...outcome, files: clean(settingsAfter(home.root), home.root) } };
  } finally {
    home.done();
  }
}

// ---- the section ------------------------------------------------------------------------------------------------

export default async function rules(ctx) {
  writeFixtures();
  const shared = await ctx.home();
  const sharedSpecs = [G, ...['academy', 'api', 'bench'].flatMap((n) => [P(`work/spacevibe-${n}`), L(`work/spacevibe-${n}`)])];
  const sharedOut = { ...readCases(shared.r, shared.root, sharedSpecs), codex: codexView(shared.r, shared.root) };

  const mainSpecs = [G, ...['proj-open', 'proj-bare', 'proj-broken', 'proj-null'].flatMap((n) => [P(n), L(n)])];
  const main = materialize('main');
  let mainOut;
  try { mainOut = { ...readCases(main.r, main.root, mainSpecs), codex: codexView(main.r, main.root) }; } finally { main.done(); }

  const codex = {};
  for (const caseName of Object.keys(CODEX_CASES)) {
    const home = materialize(`codex-${caseName}`);
    try { codex[caseName] = codexView(home.r, home.root); } finally { home.done(); }
  }
  const empty = materialize('main');
  try {
    rmSync(join(empty.root, '.codex'), { recursive: true, force: true });
    codex.missing = codexView(empty.r, empty.root);
  } finally { empty.done(); }

  const writes = writeCases().map(runWrite);
  ctx.writeGolden('rules', { shared: sharedOut, main: mainOut, codex, writes });
}
