// Golden section "mutate": what core/mutate.mjs does to a copy of the synthetic HOME, operation by operation.
//
// Every scenario runs on its own fresh copy (the shared fixture tree is only read). Per scenario the golden records
//   - the spec (setup + operation), which the Swift test replays,
//   - the error status and message, or the journal entry summary (label + ops without ids, times and trash paths),
//   - `delta`: the files and links the operation changed, as {relative path: sha1 | null}. File text is hashed after the
//     copy's own root is replaced by $HOME, so the Swift run on a different folder produces the same hashes.
//     The two hook files (.claude/settings.json, .codex/hooks.json) are listed as "json": the Node core re-prints the
//     whole file with JSON.stringify and a final newline, the Swift core edits only the bytes it changes. Their parsed
//     content is in `json`, and `body` is the sha1 of the text without its final newline.
//   - `trash`: what the operation put in the app trash, as sorted "<path inside the slot>:<sha1>".
// Sorted keys everywhere, so a rerun gives no diff.
import { createHash } from 'node:crypto';
import { lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import { readInventory, roots } from '../../core/inventory.mjs';
import { addAgent, addHook, addSkill, copyToOther, removeDeadHooks, removeItem } from '../../core/mutate.mjs';

export const name = 'mutate';

const TOKEN = '$HOME';
const HOOK_FILES = ['.claude/settings.json', '.codex/hooks.json'];
const sha1 = (text) => createHash('sha1').update(text).digest('hex');

// copyToOther on a hook is not here: the Node core reads `it.name.split` before its hook branch and throws a TypeError for
// every hook, so there is no behavior to record (the Swift core copies a hook into Claude Code only, see MutateTests).
const SCENARIOS = [
  { name: 'add-skill-both', op: { fn: 'addSkill', clis: ['claude', 'codex'], name: 'quick-notes', description: '  Use when:\n "quoted"   and\ttabs  ', body: '  Do the thing.\n\nSecond line.  ' } },
  { name: 'add-skill-no-body', op: { fn: 'addSkill', clis: ['codex'], name: 'tiny', description: 'x', body: '' } },
  { name: 'add-skill-exists', op: { fn: 'addSkill', clis: ['claude'], name: 'ponytail', description: 'x', body: '' } },
  { name: 'add-skill-bad-name', op: { fn: 'addSkill', clis: ['claude'], name: '../evil', description: 'x', body: '' } },
  { name: 'add-skill-empty-description', op: { fn: 'addSkill', clis: ['claude'], name: 'fine', description: '  \n ', body: '' } },
  { name: 'add-skill-no-cli', op: { fn: 'addSkill', clis: [], name: 'fine', description: 'x', body: '' } },
  { name: 'add-agent-both', op: { fn: 'addAgent', clis: ['claude', 'codex'], name: 'note-taker', description: 'Takes "quoted" notes', instructions: 'Line one\nSay "hi" \\ and \ttab\n' } },
  { name: 'add-agent-exists', op: { fn: 'addAgent', clis: ['claude'], name: 'architect', description: 'x', instructions: '' } },
  { name: 'add-hook-claude-stop', op: { fn: 'addHook', clis: ['claude'], event: 'Stop', matcher: '', command: 'echo added', timeout: 5 } },
  { name: 'add-hook-existing-matcher', op: { fn: 'addHook', clis: ['claude'], event: 'PreToolUse', matcher: 'Bash', command: 'echo audit' } },
  { name: 'add-hook-new-group', op: { fn: 'addHook', clis: ['claude'], event: 'PostToolUseFailure', matcher: ' Edit ', command: '  echo failed  ', timeout: 30 } },
  { name: 'add-hook-both', op: { fn: 'addHook', clis: ['claude', 'codex'], event: 'SessionStart', command: 'echo hi' } },
  { name: 'add-hook-duplicate-command', op: { fn: 'addHook', clis: ['codex'], event: 'Stop', command: `sh '${TOKEN}/.claude/scripts/notify-done.sh'` } },
  { name: 'add-hook-codex-bad-event', op: { fn: 'addHook', clis: ['codex'], event: 'TeammateIdle', command: 'x' } },
  { name: 'add-hook-empty-command', op: { fn: 'addHook', clis: ['claude'], event: 'Stop', command: '  ' } },
  { name: 'add-hook-invalid-json', setup: { files: { '.codex/hooks.json': '{broken' } }, op: { fn: 'addHook', clis: ['codex'], event: 'Stop', command: 'x' } },
  { name: 'add-hook-missing-file', setup: { remove: ['.codex/hooks.json'] }, op: { fn: 'addHook', clis: ['codex'], event: 'Stop', command: 'echo created', timeout: 10 } },
  { name: 'remove-skill', op: { fn: 'removeItem', find: { kind: 'skill', cli: 'claude', name: 'diagnosing-bugs' } } },
  { name: 'remove-skill-linked', setup: { files: { 'shared/linked/SKILL.md': '---\nname: linked\ndescription: shared\n---\n' }, links: { '.claude/skills/linked': `${TOKEN}/shared/linked` } }, op: { fn: 'removeItem', find: { kind: 'skill', cli: 'claude', name: 'linked' } } },
  { name: 'remove-agent', op: { fn: 'removeItem', find: { kind: 'agent', cli: 'claude', name: 'architect' } } },
  { name: 'remove-agent-codex', op: { fn: 'removeItem', find: { kind: 'agent', cli: 'codex', name: 'security-reviewer' } } },
  { name: 'remove-hook', op: { fn: 'removeItem', find: { kind: 'hook', cli: 'claude', event: 'PostToolUse', commandIncludes: 'prettier' } } },
  { name: 'remove-hook-last-in-group', op: { fn: 'removeItem', find: { kind: 'hook', cli: 'claude', event: 'SessionStart', commandIncludes: 'load-context' } } },
  { name: 'remove-hook-codex', op: { fn: 'removeItem', find: { kind: 'hook', cli: 'codex', event: 'Stop', commandIncludes: 'notify-done' } } },
  { name: 'remove-plugin-skill', op: { fn: 'removeItem', find: { kind: 'skill', cli: 'claude', name: 'neon-postgres' } } },
  { name: 'remove-gone', op: { fn: 'removeItem', find: { id: 'claude:skill:local:no-such-skill' } } },
  { name: 'remove-dead-hooks', op: { fn: 'removeDeadHooks', cli: 'claude' } },
  { name: 'remove-dead-hooks-none', op: { fn: 'removeDeadHooks', cli: 'codex' } },
  { name: 'copy-skill', op: { fn: 'copyToOther', find: { kind: 'skill', cli: 'claude', name: 'ponytail' } } },
  { name: 'copy-skill-to-claude', op: { fn: 'copyToOther', find: { kind: 'skill', cli: 'codex', name: 'impeccable' } } },
  { name: 'copy-skill-plugin', op: { fn: 'copyToOther', find: { kind: 'skill', cli: 'claude', name: 'neon-postgres' } } },
  {
    name: 'copy-skill-folder-with-link-and-git',
    setup: {
      files: {
        '.claude/skills/packed/SKILL.md': '---\nname: packed\ndescription: has extras\n---\n\nBody.\n',
        '.claude/skills/packed/scripts/run.sh': '#!/bin/sh\nexit 0\n',
        '.claude/skills/packed/.git/config': '[core]\n',
      },
      links: { '.claude/skills/packed/alias.md': 'SKILL.md' },
    },
    op: { fn: 'copyToOther', find: { kind: 'skill', cli: 'claude', name: 'packed' } },
  },
  { name: 'copy-agent-md-to-toml', op: { fn: 'copyToOther', find: { kind: 'agent', cli: 'claude', name: 'typescript-reviewer' } } },
  {
    name: 'copy-agent-quotes-md-to-toml',
    setup: { files: { '.claude/agents/quoter.md': '---\nname: quoter\ndescription: "Says \\"hi\\" and\\\\or more"\n---\n\nInstructions "quoted"\nSecond \\ line\n' } },
    op: { fn: 'copyToOther', find: { kind: 'agent', cli: 'claude', name: 'quoter' } },
  },
  {
    name: 'copy-agent-block-toml-to-md',
    setup: { files: { '.codex/agents/toml-only.toml': 'name = "toml-only"\ndescription = "Reads \\"toml\\""\ndeveloper_instructions = """\nFirst "quoted"\nSecond\n"""\n' } },
    op: { fn: 'copyToOther', find: { kind: 'agent', cli: 'codex', name: 'toml-only' } },
  },
  {
    name: 'copy-agent-line-toml-to-md',
    setup: { files: { '.codex/agents/one-line.toml': 'name = "one-line"\ndescription = "Short"\ndeveloper_instructions = "Line with \\"escaped\\" quotes\\nand newline"\n' } },
    op: { fn: 'copyToOther', find: { kind: 'agent', cli: 'codex', name: 'one-line' } },
  },
  { name: 'copy-agent-exists', op: { fn: 'copyToOther', find: { kind: 'agent', cli: 'claude', name: 'security-reviewer' } } },
];

// ---- fresh copy of the fixture tree -----------------------------------------------------------------------------------

function copyTree(from, to, fromRoot, toRoot) {
  mkdirSync(to, { recursive: true });
  for (const e of readdirSync(from, { withFileTypes: true })) {
    const src = join(from, e.name);
    const dst = join(to, e.name);
    if (e.name === '.fixture-stamp') continue;
    if (e.isDirectory()) copyTree(src, dst, fromRoot, toRoot);
    else if (e.isFile()) {
      writeFileSync(dst, readFileSync(src, 'utf8').replaceAll(fromRoot, toRoot));
      const st = lstatSync(src);
      utimesSync(dst, st.atime, st.mtime);
    }
  }
}

function applySetup(root, setup = {}) {
  for (const rel of setup.remove ?? []) rmSync(join(root, rel), { force: true });
  for (const [rel, text] of Object.entries(setup.files ?? {})) {
    mkdirSync(dirname(join(root, rel)), { recursive: true });
    writeFileSync(join(root, rel), text.replaceAll(TOKEN, root));
  }
  for (const [rel, target] of Object.entries(setup.links ?? {})) {
    mkdirSync(dirname(join(root, rel)), { recursive: true });
    symlinkSync(target.replaceAll(TOKEN, root), join(root, rel));
  }
}

// ---- measuring ------------------------------------------------------------------------------------------------------

// {relative path: sha1 of the text with the root replaced by $HOME, or "link:<target>"}; the Reins data folder is skipped.
function measure(dir, root, { skipData = false } = {}) {
  const out = {};
  const visit = (current) => {
    for (const e of readdirSync(current, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const path = join(current, e.name);
      const rel = relative(dir, path);
      if (skipData && (rel === '.reins' || rel === '.fixture-stamp')) continue;
      if (e.isSymbolicLink()) out[rel] = `link:${readlinkSync(path).replaceAll(root, TOKEN)}`;
      else if (e.isDirectory()) visit(path);
      else if (e.isFile()) out[rel] = sha1(readFileSync(path, 'utf8').replaceAll(root, TOKEN));
    }
  };
  visit(dir);
  return out;
}

const trashEntries = (data, root) => {
  const trash = join(data, 'trash');
  const out = [];
  try { readdirSync(trash); } catch { return out; }
  for (const slot of readdirSync(trash)) {
    for (const [rel, hash] of Object.entries(measure(join(trash, slot), root))) out.push(`${rel}:${hash}`);
  }
  return out.sort();
};

const DROPPED_OP_KEYS = new Set(['to', 'backup', 'after', 'restore']);
const summarize = (entry, root) => JSON.parse(JSON.stringify({
  label: entry.label,
  ops: entry.ops.map((op) => Object.fromEntries(Object.entries(op).filter(([k]) => !DROPPED_OP_KEYS.has(k)))),
}).replaceAll(root, TOKEN));

function pick(r, find) {
  const inv = readInventory(r);
  const hit = [...inv.items, ...inv.hooks].find((x) => (find.id ? x.id === find.id : x.kind === find.kind && x.cli === find.cli
    && (find.name ? x.name === find.name : x.event === find.event && x.command.includes(find.commandIncludes))));
  if (!hit && !find.id) throw new Error(`golden scenario cannot find ${JSON.stringify(find)}`);
  return hit?.id ?? find.id;
}

function perform(r, op, root) {
  switch (op.fn) {
    case 'addSkill': return addSkill(r, { clis: op.clis, name: op.name, description: op.description, body: op.body });
    case 'addAgent': return addAgent(r, { clis: op.clis, name: op.name, description: op.description, instructions: op.instructions });
    case 'addHook': return addHook(r, { clis: op.clis, event: op.event, matcher: op.matcher, command: op.command?.replaceAll(TOKEN, root), timeout: op.timeout });
    case 'removeItem': return removeItem(r, { id: pick(r, op.find) });
    case 'removeDeadHooks': return removeDeadHooks(r, { cli: op.cli });
    case 'copyToOther': return copyToOther(r, { id: pick(r, op.find) });
    default: throw new Error(`unknown operation ${op.fn}`);
  }
}

function runScenario(canonical, scenario) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'reins-mutate-golden-')));
  try {
    copyTree(canonical, root, canonical, root);
    mkdirSync(join(root, '.reins'), { recursive: true });
    applySetup(root, scenario.setup);
    const r = roots({ HOME: root, CLAUDE_CONFIG_DIR: join(root, '.claude'), CODEX_HOME: join(root, '.codex'), REINS_HOME: join(root, '.reins'), REINS_TEST: '1' });
    const before = measure(root, root, { skipData: true });
    const textBefore = Object.fromEntries(HOOK_FILES.map((rel) => { try { return [rel, readFileSync(join(root, rel), 'utf8')]; } catch { return [rel, null]; } }));
    let error = null;
    let journal = null;
    try {
      journal = summarize(perform(r, scenario.op, root), root);
    } catch (e) {
      if (typeof e.status !== 'number') throw e;
      error = { status: e.status, message: e.message.replaceAll(root, TOKEN) };
    }
    const after = measure(root, root, { skipData: true });
    const delta = {};
    const json = {};
    const body = {};
    for (const rel of new Set([...Object.keys(before), ...Object.keys(after)])) {
      if (before[rel] === after[rel]) continue;
      if (HOOK_FILES.includes(rel)) {
        delta[rel] = after[rel] === undefined ? null : 'json';
        if (after[rel] !== undefined) {
          const text = readFileSync(join(root, rel), 'utf8').replaceAll(root, TOKEN);
          json[rel] = JSON.parse(text);
          body[rel] = { bodySha1: sha1(text.replace(/\n$/, '')), wasPretty: (textBefore[rel] ?? '\n').includes('\n') };
        }
      } else delta[rel] = after[rel] ?? null;
    }
    return {
      name: scenario.name,
      setup: scenario.setup ?? null,
      op: scenario.op,
      error,
      journal,
      delta: sorted(delta),
      json: sorted(json),
      body: sorted(body),
      trash: trashEntries(join(root, '.reins'), root),
    };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const sorted = (value) => {
  if (Array.isArray(value)) return value.map(sorted);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map((k) => [k, sorted(value[k])]));
  return value;
};

export default async function mutate(ctx) {
  const h = await ctx.home();
  // The unchanged tree, hashed the same way: lets the Swift test check its own copy before it changes anything.
  const initial = measure(h.root, h.root, { skipData: true });
  const scenarios = SCENARIOS.map((s) => runScenario(h.root, s));
  ctx.writeGolden('mutate', { hookFiles: HOOK_FILES, initial, scenarios });
}
