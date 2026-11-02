// Every write lives here. Each action records a journal entry so it can be undone, and
// removed files move to the app's own trash instead of being deleted.
import { execFile } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import {
  chmodSync, cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, readlinkSync, realpathSync,
  renameSync, rmSync, statSync, symlinkSync, unlinkSync, writeFileSync,
} from 'node:fs';
import { basename, dirname, join, resolve, sep } from 'node:path';
import { promisify } from 'node:util';
import { EVENTS, frontmatter, readInventory, tomlFields } from './inventory.mjs';

const run = promisify(execFile);
export const NAME_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;
const JOURNAL_LIMIT = 200;
const CLONE_TIMEOUT_MS = 60_000;

export class UserError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

const need = (cond, msg, status) => { if (!cond) throw new UserError(msg, status); };
const validName = (name) => need(NAME_RE.test(name ?? ''), 'Use lowercase letters, numbers and dashes for the name.');
const validCli = (cli) => need(cli === 'claude' || cli === 'codex', 'Unknown CLI.');
const CLI_LABEL = { claude: 'Claude Code', codex: 'Codex' };

function ensureData(r) {
  mkdirSync(join(r.data, 'trash'), { recursive: true, mode: 0o700 });
}

function readJournal(r) {
  try { return JSON.parse(readFileSync(join(r.data, 'journal.json'), 'utf8')); } catch { return []; }
}
function writeJournal(r, entries) {
  ensureData(r);
  const path = join(r.data, 'journal.json');
  writeFileSync(`${path}.tmp`, JSON.stringify(entries.slice(0, JOURNAL_LIMIT), null, 2), { mode: 0o600 });
  renameSync(`${path}.tmp`, path);
}
export function record(r, label, ops) {
  const entry = { id: randomUUID(), at: new Date().toISOString(), label, ops };
  writeJournal(r, [entry, ...readJournal(r)]);
  return entry;
}
export const history = (r) => readJournal(r).map(({ id, at, label, undone, ops }) => ({ id, at, label, undone: !!undone, count: ops.length }));

function trashSlot(r, name) {
  const dir = join(r.data, 'trash', `${Date.now()}-${randomUUID().slice(0, 8)}`);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  return join(dir, name);
}

function moveToTrash(r, path) {
  const to = trashSlot(r, basename(path));
  renameSync(path, to);
  return { type: 'moved', from: path, to };
}

// Removing a link never touches what it points at.
function removePath(r, path) {
  const st = lstatSync(path);
  if (st.isSymbolicLink()) {
    const target = readlinkSync(path);
    unlinkSync(path);
    return { type: 'link-removed', path, target };
  }
  return moveToTrash(r, path);
}

function updateJson(r, file, change) {
  let raw = '{}';
  if (existsSync(file)) raw = readFileSync(file, 'utf8');
  let config;
  try { config = JSON.parse(raw); } catch { throw new UserError(`${file} is not valid JSON. Nothing was changed.`, 409); }
  const real = existsSync(file) ? realpathSync(file) : file;
  const mode = existsSync(real) ? statSync(real).mode & 0o777 : 0o644;
  const nextConfig = change(structuredClone(config));
  if (existsSync(real)) cpSync(real, trashSlot(r, basename(real)));
  const tmp = `${real}.reins-${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(nextConfig, null, 2)}\n`, { mode });
  renameSync(tmp, real);
}

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

// Writes bytes next to the target and renames over it, so a reader never sees half a file.
// `validate` gets the text read back from the temp file; throwing aborts before the rename.
function atomicWrite(real, data, mode, validate) {
  const tmp = `${real}.reins-${process.pid}.tmp`;
  try {
    rmSync(tmp, { force: true });
    writeFileSync(tmp, data, { mode, flag: 'wx' });
    chmodSync(tmp, mode);
    if (validate) validate(readFileSync(tmp, 'utf8'));
    renameSync(tmp, real);
  } catch (e) {
    rmSync(tmp, { force: true });
    throw e;
  }
}

// Text-file edit for permission rules. `change(text | null)` returns the next text; returning
// the same text is a no-op (null result). The previous bytes go to the app's trash and the
// returned op lets undo put back exactly those bytes, or remove a file this edit created.
export function editFile(r, file, change, { validate } = {}) {
  const real = existsSync(file) ? realpathSync(file) : file;
  const existed = existsSync(real);
  const before = existed ? readFileSync(real, 'utf8') : null;
  const next = change(before);
  if (next === before) return null;
  const mode = existed ? statSync(real).mode & 0o777 : 0o600;
  let backup = null;
  if (existed) { backup = trashSlot(r, basename(real)); cpSync(real, backup); } else mkdirSync(dirname(real), { recursive: true });
  atomicWrite(real, next, mode, validate);
  return { type: 'file-edited', file: real, existed, backup, after: sha256(Buffer.from(next)) };
}

const sameGroup = (g, matcher) => (g.matcher ?? null) === (matcher ?? null);

function withHook(config, { event, matcher, hook }) {
  const hooks = { ...(config.hooks ?? {}) };
  const groups = [...(hooks[event] ?? [])];
  const i = groups.findIndex((g) => sameGroup(g, matcher) && !(g.hooks ?? []).some((h) => h.command === hook.command));
  if (i >= 0) groups[i] = { ...groups[i], hooks: [...groups[i].hooks, hook] };
  else groups.push({ ...(matcher ? { matcher } : {}), hooks: [hook] });
  return { ...config, hooks: { ...hooks, [event]: groups } };
}

function withoutHook(config, { event, matcher, command }) {
  const hooks = { ...(config.hooks ?? {}) };
  let found = null;
  const groups = [];
  for (const g of hooks[event] ?? []) {
    if (found || !sameGroup(g, matcher)) { groups.push(g); continue; }
    const i = (g.hooks ?? []).findIndex((h) => h.command === command);
    if (i < 0) { groups.push(g); continue; }
    found = g.hooks[i];
    const rest = g.hooks.filter((_, j) => j !== i);
    if (rest.length) groups.push({ ...g, hooks: rest });
  }
  if (groups.length) hooks[event] = groups; else delete hooks[event];
  return { config: { ...config, hooks }, found };
}

const yamlValue = (s) => JSON.stringify(String(s).replace(/\s+/g, ' ').trim());

function writeNew(path, text) {
  writeFileSync(path, text, { flag: 'wx' });
}

function addSkillFromForm(r, cli, { name, description, body }) {
  const dir = join(r[cli].skills, name);
  need(!existsSync(dir), `${CLI_LABEL[cli]} already has a skill named ${name}.`, 409);
  mkdirSync(dir, { recursive: true });
  writeNew(join(dir, 'SKILL.md'), `---\nname: ${name}\ndescription: ${yamlValue(description)}\n---\n\n${(body ?? '').trim()}\n`);
  return { type: 'created', path: dir };
}

function copySkillDir(r, cli, from, name) {
  const dir = join(r[cli].skills, name);
  need(!existsSync(dir), `${CLI_LABEL[cli]} already has a skill named ${name}.`, 409);
  mkdirSync(r[cli].skills, { recursive: true });
  cpSync(from, dir, { recursive: true, verbatimSymlinks: true, filter: (src) => !src.split(sep).includes('.git') });
  return { type: 'created', path: dir };
}

const tomlString = (s) => JSON.stringify(String(s));

function writeAgent(r, cli, { name, description, instructions }) {
  mkdirSync(r[cli].agents, { recursive: true });
  const path = join(r[cli].agents, `${name}.${cli === 'claude' ? 'md' : 'toml'}`);
  need(!existsSync(path), `${CLI_LABEL[cli]} already has an agent named ${name}.`, 409);
  const text = cli === 'claude'
    ? `---\nname: ${name}\ndescription: ${yamlValue(description)}\n---\n\n${(instructions ?? '').trim()}\n`
    : `name = ${tomlString(name)}\ndescription = ${tomlString(description)}\ndeveloper_instructions = ${tomlString((instructions ?? '').trim())}\n`;
  writeNew(path, text);
  return { type: 'created', path };
}

export function addSkill(r, { clis, name, description, body }) {
  validName(name);
  need(description?.trim(), 'Say when the agent should use this skill.');
  need(clis?.length, 'Pick at least one CLI.');
  clis.forEach(validCli);
  const ops = clis.map((cli) => addSkillFromForm(r, cli, { name, description, body }));
  return record(r, `Added skill ${name} to ${clis.map((c) => CLI_LABEL[c]).join(' and ')}`, ops);
}

export function addAgent(r, { clis, name, description, instructions }) {
  validName(name);
  need(description?.trim(), 'Say when this agent should be used.');
  need(clis?.length, 'Pick at least one CLI.');
  clis.forEach(validCli);
  const ops = clis.map((cli) => writeAgent(r, cli, { name, description, instructions }));
  return record(r, `Added agent ${name} to ${clis.map((c) => CLI_LABEL[c]).join(' and ')}`, ops);
}

export function addHook(r, { clis, event, matcher, command, timeout }) {
  need(command?.trim(), 'Enter the command this hook runs.');
  need(clis?.length, 'Pick at least one CLI.');
  const ops = [];
  for (const cli of clis) {
    validCli(cli);
    need(EVENTS[cli].includes(event), `${CLI_LABEL[cli]} has no ${event} event.`);
  }
  for (const cli of clis) {
    const hook = { type: 'command', command: command.trim(), ...(timeout ? { timeout: Number(timeout) } : {}) };
    const m = matcher?.trim() || null;
    updateJson(r, r[cli].hookFile, (cfg) => withHook(cfg, { event, matcher: m, hook }));
    ops.push({ type: 'hook-added', file: r[cli].hookFile, event, matcher: m, hook });
  }
  return record(r, `Added ${event} hook to ${clis.map((c) => CLI_LABEL[c]).join(' and ')}`, ops);
}

function findItem(r, id) {
  const inv = readInventory(r);
  const hit = [...inv.items, ...inv.hooks].find((x) => x.id === id);
  need(hit, 'This item no longer exists. Refresh the list.', 404);
  return hit;
}

export function removeItem(r, { id }) {
  const it = findItem(r, id);
  need(it.removable, 'This one belongs to a plugin. Remove the plugin instead.', 403);
  if (it.kind === 'hook') {
    const op = removeHookOp(r, it);
    return record(r, `Removed ${it.event} hook from ${CLI_LABEL[it.cli]}`, [op]);
  }
  const root = it.kind === 'skill' ? r[it.cli].skills : r[it.cli].agents;
  need(resolve(it.path).startsWith(resolve(root) + sep), 'Refusing a path outside the CLI folder.', 403);
  return record(r, `Removed ${it.kind} ${it.name} from ${CLI_LABEL[it.cli]}`, [removePath(r, it.path)]);
}

function removeHookOp(r, it) {
  let removed = null;
  updateJson(r, r[it.cli].hookFile, (cfg) => {
    const { config, found } = withoutHook(cfg, it);
    need(found, 'This hook has already changed. Refresh the list.', 409);
    removed = found;
    return config;
  });
  return { type: 'hook-removed', file: r[it.cli].hookFile, event: it.event, matcher: it.matcher, hook: removed };
}

export function removeDeadHooks(r, { cli }) {
  validCli(cli);
  const dead = readInventory(r).hooks.filter((h) => h.cli === cli && h.dead && h.removable);
  need(dead.length, 'No dead hooks to remove.', 409);
  const file = r[cli].hookFile;
  const ops = [];
  updateJson(r, file, (cfg) => dead.reduce((acc, h) => {
    const { config, found } = withoutHook(acc, h);
    if (found) ops.push({ type: 'hook-removed', file, event: h.event, matcher: h.matcher, hook: found });
    return config;
  }, cfg));
  return record(r, `Removed ${ops.length} dead hooks from ${CLI_LABEL[cli]}`, ops);
}

export function copyToOther(r, { id }) {
  const it = findItem(r, id);
  const to = it.cli === 'claude' ? 'codex' : 'claude';
  const baseName = it.name.split(':').pop();
  if (it.kind === 'hook') {
    need(EVENTS[to].includes(it.event), `${CLI_LABEL[to]} has no ${it.event} event.`);
    return addHook(r, { clis: [to], event: it.event, matcher: it.matcher, command: it.command, timeout: it.timeout });
  }
  validName(baseName);
  if (it.kind === 'skill') {
    return record(r, `Copied skill ${baseName} to ${CLI_LABEL[to]}`, [copySkillDir(r, to, realpathSync(it.path), baseName)]);
  }
  const text = readFileSync(it.path, 'utf8');
  const fields = it.path.endsWith('.toml')
    ? tomlFields(text)
    : { ...frontmatter(text), instructions: text.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, '') };
  return record(r, `Copied agent ${baseName} to ${CLI_LABEL[to]}`, [writeAgent(r, to, { name: baseName, description: fields.description ?? '', instructions: fields.instructions ?? '' })]);
}

function undoOp(r, op) {
  switch (op.type) {
    case 'created':
      if (existsSync(op.path)) moveToTrash(r, op.path);
      return;
    case 'moved':
      need(!existsSync(op.from), `${op.from} already exists again, so it was left alone.`, 409);
      renameSync(op.to, op.from);
      return;
    case 'link-removed':
      need(!existsSync(op.path), `${op.path} already exists again, so it was left alone.`, 409);
      symlinkSync(op.target, op.path);
      return;
    case 'hook-added':
      updateJson(r, op.file, (cfg) => withoutHook(cfg, { event: op.event, matcher: op.matcher, command: op.hook.command }).config);
      return;
    case 'hook-removed':
      updateJson(r, op.file, (cfg) => withHook(cfg, { event: op.event, matcher: op.matcher, hook: op.hook }));
      return;
    case 'file-edited': {
      const now = existsSync(op.file) ? readFileSync(op.file) : null;
      need(now && sha256(now) === op.after, `${op.file} changed since this edit, so it was left alone.`, 409);
      if (op.existed) atomicWrite(op.file, readFileSync(op.backup), statSync(op.file).mode & 0o777);
      else moveToTrash(r, op.file);
      return;
    }
    default:
      throw new UserError('Unknown history entry.');
  }
}

export function undo(r, { id }) {
  const entries = readJournal(r);
  const entry = entries.find((e) => e.id === id);
  need(entry, 'That history entry is gone.', 404);
  need(!entry.undone, 'This was already undone.', 409);
  // Batched hook removals rewrite one file once rather than once per hook.
  const hookOps = entry.ops.filter((o) => o.type === 'hook-removed');
  if (hookOps.length > 1 && hookOps.length === entry.ops.length) {
    updateJson(r, hookOps[0].file, (cfg) => hookOps.reduce((acc, op) => withHook(acc, op), cfg));
  } else {
    for (const op of [...entry.ops].reverse()) undoOp(r, op);
  }
  writeJournal(r, entries.map((e) => (e.id === id ? { ...e, undone: true } : e)));
  return { label: entry.label };
}

// --- Adding skills from a folder or a GitHub link ---

function findSkillDirs(root, depth = 3) {
  const found = [];
  const visit = (dir, level) => {
    if (existsSync(join(dir, 'SKILL.md'))) { found.push(dir); return; }
    if (level >= depth) return;
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      if (e.isDirectory() && !e.name.startsWith('.') && e.name !== 'node_modules') visit(join(dir, e.name), level + 1);
    }
  };
  visit(root, 0);
  return found;
}

const GITHUB_RE = /^https:\/\/github\.com\/([\w.-]+)\/([\w.-]+?)(?:\.git)?(?:\/tree\/([\w./-]+?))?\/?$/;

async function fetchGithub(r, url) {
  const m = GITHUB_RE.exec(url);
  need(m, 'Use a https://github.com/owner/repo link.');
  const [, owner, repo, tree] = m;
  ensureData(r);
  const tmp = mkdtempSync(join(r.data, 'fetch-'));
  const args = ['-c', 'core.symlinks=false', '-c', 'core.hooksPath=/dev/null', 'clone', '--depth', '1', '--single-branch', '--no-tags', '--', `https://github.com/${owner}/${repo}.git`, tmp];
  const branch = tree?.split('/')[0];
  if (branch) args.splice(args.indexOf('--'), 0, '--branch', branch);
  try {
    await run('git', args, { timeout: CLONE_TIMEOUT_MS, env: { ...process.env, GIT_TERMINAL_PROMPT: '0' } });
  } catch {
    rmSync(tmp, { recursive: true, force: true });
    throw new UserError('Could not download that repository. Check the link and your connection.', 502);
  }
  const sub = tree?.split('/').slice(1).join('/');
  const start = sub ? resolve(tmp, sub) : tmp;
  need(start.startsWith(tmp + sep) || start === tmp, 'That path is outside the repository.');
  need(existsSync(start), 'That folder is not in the repository.', 404);
  return { tmp, start };
}

const sources = new Map();

// Previews live only in memory, so downloads left by an earlier run can go.
export function clearOldDownloads(r) {
  ensureData(r);
  for (const e of readdirSync(r.data)) {
    if (e.startsWith('fetch-')) rmSync(join(r.data, e), { recursive: true, force: true });
  }
}

export async function previewSource(r, { source }) {
  const value = source?.trim();
  need(value, 'Paste a GitHub link or a folder path.');
  let start;
  let tmp = null;
  if (value.startsWith('https://')) ({ tmp, start } = await fetchGithub(r, value));
  else {
    start = resolve(value.replace(/^~(?=\/|$)/, process.env.HOME ?? ''));
    need(existsSync(start) && statSync(start).isDirectory(), 'That folder does not exist.', 404);
  }
  const skills = findSkillDirs(start).map((dir) => {
    const text = readFileSync(join(dir, 'SKILL.md'), 'utf8');
    const fm = frontmatter(text);
    const name = String(fm.name || basename(dir)).toLowerCase();
    return { dir, name, description: fm.description ?? '', files: readdirSync(dir).filter((f) => f !== '.git').length, text: text.slice(0, 16 * 1024), hasScripts: existsSync(join(dir, 'scripts')) };
  });
  if (!skills.length) {
    if (tmp) rmSync(tmp, { recursive: true, force: true });
    throw new UserError('No SKILL.md found there.', 404);
  }
  const sourceId = randomUUID();
  sources.set(sourceId, { tmp, skills });
  return { sourceId, skills: skills.map(({ dir: _dir, ...rest }) => rest) };
}

export function installSource(r, { sourceId, names, clis }) {
  const src = sources.get(sourceId);
  need(src, 'That preview expired. Paste the link again.', 410);
  need(clis?.length, 'Pick at least one CLI.');
  need(names?.length, 'Pick at least one skill.');
  clis.forEach(validCli);
  const ops = [];
  for (const name of names) {
    validName(name);
    const skill = src.skills.find((s) => s.name === name);
    need(skill, `${name} is not in this source.`);
    for (const cli of clis) ops.push(copySkillDir(r, cli, skill.dir, name));
  }
  if (src.tmp) rmSync(src.tmp, { recursive: true, force: true });
  sources.delete(sourceId);
  return record(r, `Added ${names.length === 1 ? `skill ${names[0]}` : `${names.length} skills`} to ${clis.map((c) => CLI_LABEL[c]).join(' and ')}`, ops);
}
