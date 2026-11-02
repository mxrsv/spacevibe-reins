// Reads what is installed for Claude Code and Codex. Never executes anything and
// never keeps settings values other than hooks, plugin flags and skill overrides.
import { createHash } from 'node:crypto';
import { closeSync, existsSync, lstatSync, openSync, readdirSync, readFileSync, readSync, realpathSync, statSync } from 'node:fs';
import { homedir, userInfo } from 'node:os';
import { isAbsolute, join, resolve, sep } from 'node:path';

export const CLIS = ['claude', 'codex'];
export const SYSTEM_DIRS = /^[._]/;

export const EVENTS = {
  claude: ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'PostToolUseFailure', 'Notification', 'SubagentStart', 'SubagentStop', 'Elicitation', 'ElicitationResult', 'TeammateIdle', 'PreCompact', 'PostCompact', 'Stop', 'StopFailure', 'SessionEnd'],
  codex: ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'SubagentStart', 'SubagentStop', 'Interrupt', 'Stop', 'SessionEnd'],
};

const realPath = (p) => { const abs = resolve(p); try { return realpathSync(abs); } catch { return abs; } };
const isUnder = (p, dir) => p === dir || p.startsWith(dir + sep);

// AC3: with REINS_TEST=1 a root under the real home is a test about to touch real config, so refuse.
function assertTempRoots(found) {
  const real = userInfo().homedir;
  const homes = [resolve(real), realPath(real)];
  for (const [label, path] of Object.entries(found)) {
    const candidates = [resolve(path), realPath(path)];
    if (candidates.some((c) => homes.some((h) => isUnder(c, h)))) {
      throw new Error(`REINS_TEST=1: the ${label} root ${path} is under the real home. Point HOME, CLAUDE_CONFIG_DIR, CODEX_HOME and REINS_HOME at a temporary folder.`);
    }
  }
}

export function roots(env = process.env) {
  const home = env.HOME || homedir();
  const claude = env.CLAUDE_CONFIG_DIR || join(home, '.claude');
  const codex = env.CODEX_HOME || join(home, '.codex');
  if (env.REINS_TEST === '1') assertTempRoots({ claude, codex, data: env.REINS_HOME || join(home, '.reins') });
  return {
    claude: { root: claude, skills: join(claude, 'skills'), agents: join(claude, 'agents'), hookFile: join(claude, 'settings.json'), logs: join(claude, 'projects') },
    codex: { root: codex, skills: join(codex, 'skills'), agents: join(codex, 'agents'), hookFile: join(codex, 'hooks.json'), logs: join(codex, 'sessions') },
    data: env.REINS_HOME || join(home, '.reins'),
  };
}

export const sha = (s) => createHash('sha1').update(s).digest('hex').slice(0, 12);
export const bare = (name) => name.split(':').pop();
// One matrix row: the same skill or agent name (or the same hook) in the same project, whichever CLI holds it.
export const rowKey = (x) => (x.kind === 'hook' ? `hook:${x.project ?? ''}:${x.hash}` : `${x.kind}:${x.project ?? ''}:${bare(x.name)}`);

function unquote(v) {
  const t = v.trim();
  if (t.startsWith('"')) { try { return JSON.parse(t); } catch { return t.slice(1, -1); } }
  if (t.startsWith("'") && t.endsWith("'")) return t.slice(1, -1).replaceAll("''", "'");
  return t;
}

export function frontmatter(text) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
  if (!m) return {};
  const out = {};
  const lines = m[1].split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const kv = /^([A-Za-z][\w-]*):\s*(.*)$/.exec(lines[i]);
    if (!kv) continue;
    const [, key, raw] = kv;
    if (/^[>|][+-]?$/.test(raw.trim())) {
      const block = [];
      while (i + 1 < lines.length && (/^\s/.test(lines[i + 1]) || !lines[i + 1])) block.push(lines[++i].trim());
      out[key] = block.join(raw.trim()[0] === '>' ? ' ' : '\n').trim();
    } else out[key] = unquote(raw);
  }
  return out;
}

export function tomlFields(text) {
  const out = {};
  for (const key of ['name', 'description']) {
    const m = new RegExp(`^${key}\\s*=\\s*("(?:[^"\\\\]|\\\\.)*"|'[^']*')`, 'm').exec(text);
    if (m) out[key] = unquote(m[1]);
  }
  const body = /^developer_instructions\s*=\s*("""|''')([\s\S]*?)\1/m.exec(text);
  if (body) out.instructions = body[2].replace(/^\n/, '');
  else {
    const line = /^developer_instructions\s*=\s*("(?:[^"\\]|\\.)*")/m.exec(text);
    if (line) out.instructions = unquote(line[1]);
  }
  return out;
}

const safeRead = (p) => { try { return readFileSync(p, 'utf8'); } catch { return null; } };
const list = (p) => { try { return readdirSync(p); } catch { return []; } };
const jsonFile = (p) => { const t = safeRead(p); if (t == null) return null; try { return JSON.parse(t); } catch { return undefined; } };

function ownerOf(path) {
  try { return lstatSync(path).isSymbolicLink() ? 'link' : 'user'; } catch { return 'user'; }
}

// `project` is the absolute path of the project that owns the folder, or null for user-level config.
const scopeOf = (project) => ({ scope: project ? 'project' : 'global', project: project ?? null });
const idTag = (owner, project) => (project ? `project:${sha(project)}` : owner ?? 'local');

function skillsIn(dir, cli, owner, project = null) {
  const out = [];
  for (const entry of list(dir)) {
    if (SYSTEM_DIRS.test(entry)) continue;
    const path = join(dir, entry);
    const text = safeRead(join(path, 'SKILL.md'));
    if (text == null) continue;
    const fm = frontmatter(text);
    out.push({
      id: `${cli}:skill:${idTag(owner, project)}:${entry}`, cli, kind: 'skill', name: fm.name || entry, entry,
      description: fm.description ?? '', owner: owner ?? ownerOf(path), path, file: join(path, 'SKILL.md'), removable: !owner && !project, ...scopeOf(project),
    });
  }
  return out;
}

function agentsIn(dir, cli, owner, project = null) {
  const out = [];
  for (const entry of list(dir)) {
    const isMd = entry.endsWith('.md');
    if ((!isMd && !entry.endsWith('.toml')) || SYSTEM_DIRS.test(entry)) continue;
    const path = join(dir, entry);
    const text = safeRead(path);
    if (text == null) continue;
    const f = isMd ? frontmatter(text) : tomlFields(text);
    out.push({
      id: `${cli}:agent:${idTag(owner, project)}:${entry}`, cli, kind: 'agent', name: f.name || entry.replace(/\.(md|toml)$/, ''), entry,
      description: f.description ?? '', owner: owner ?? ownerOf(path), path, file: path, removable: !owner && !project, ...scopeOf(project),
    });
  }
  return out;
}

// Absolute paths a hook command points at. A command is dead only when it names
// at least one script path and none of them exists any more.
const SCRIPT_RE = /\.(sh|bash|zsh|js|mjs|cjs|ts|py|rb)$/;

export function scriptPaths(command) {
  const found = new Set();
  const re = /'(\/[^']+)'|"(\/[^"$]+)"|(?:^|\s)(\/[^\s'";|&)]+)/g;
  for (const m of command.matchAll(re)) {
    const p = m[1] ?? m[2] ?? m[3];
    if (isAbsolute(p) && SCRIPT_RE.test(p)) found.add(p);
  }
  return [...found];
}

function hooksFrom(config, cli, owner, sourceFile, project = null) {
  const out = [];
  for (const [event, groups] of Object.entries(config?.hooks ?? {})) {
    if (!Array.isArray(groups)) continue;
    groups.forEach((g) => (g.hooks ?? []).forEach((hook) => {
      if (typeof hook.command !== 'string') return;
      const paths = scriptPaths(hook.command);
      const dead = paths.length > 0 && !paths.some((p) => existsSync(p));
      out.push({
        // Global ids stay as they were; a project hook also hashes its file, so the same hook in two files has two ids.
        id: `${cli}:hook:${sha(`${owner ?? ''}|${event}|${g.matcher ?? ''}|${hook.command}${project ? `|${sourceFile}` : ''}`)}`, cli, kind: 'hook', event,
        matcher: g.matcher ?? null, command: hook.command, timeout: hook.timeout ?? null, async: hook.async ?? false,
        owner: owner ?? 'user', removable: !owner && !project, dead, paths, hash: sha(`${event}|${hook.command}`), file: sourceFile, ...scopeOf(project),
      });
    }));
  }
  return out;
}

function pluginEntries(r) {
  const installed = jsonFile(join(r.claude.root, 'plugins', 'installed_plugins.json'));
  const settings = jsonFile(r.claude.hookFile) ?? {};
  const out = [];
  for (const [key, versions] of Object.entries(installed?.plugins ?? {})) {
    if (settings.enabledPlugins?.[key] !== true) continue;
    const path = versions?.[0]?.installPath;
    if (path && existsSync(path)) out.push({ name: key.split('@')[0], path });
  }
  return out;
}

// Project discovery. Claude Code keeps no list of projects, so Reins looks where a path is already recorded:
//  - the `cwd` in the head of the newest session logs of each folder under claude/projects (the folder name is a
//    lossy encoding of the path and cannot be decoded), and
//  - the `[projects."<path>"]` keys of Codex config.toml.
// A path counts only if it still exists and has a `.claude` folder of its own. The home folder is skipped (its
// `.claude` is the global one), and so are paths inside `.claude/worktrees/` (copies of a project already listed).
// Bounded: at most 3 log files per folder, 64 KB each, at most MAX_PROJECTS folders, newest first.
// Trade-off: a project never opened with either CLI is not found, and one whose first records fall outside the
// first 64 KB of its 3 newest logs is missed.
export const MAX_PROJECTS = 300;
const HEAD_BYTES = 64 * 1024;
const CWD_RE = /"cwd":"((?:[^"\\]|\\.)*)"/;

function headOf(file) {
  try {
    const fd = openSync(file, 'r');
    try {
      const buf = Buffer.alloc(HEAD_BYTES);
      return buf.toString('utf8', 0, readSync(fd, buf, 0, HEAD_BYTES, 0));
    } finally { closeSync(fd); }
  } catch { return ''; }
}

function logCwds(logsDir) {
  const found = [];
  for (const dir of list(logsDir)) {
    const base = join(logsDir, dir);
    const logs = list(base).filter((f) => f.endsWith('.jsonl')).map((f) => {
      try { return { file: join(base, f), mtime: statSync(join(base, f)).mtimeMs }; } catch { return null; }
    }).filter(Boolean).sort((a, b) => b.mtime - a.mtime).slice(0, 3);
    for (const { file, mtime } of logs) {
      const m = CWD_RE.exec(headOf(file));
      if (!m) continue;
      try { found.push({ path: JSON.parse(`"${m[1]}"`), mtime }); } catch { /* unreadable path, skip */ }
      break;
    }
  }
  return found.sort((a, b) => b.mtime - a.mtime).slice(0, MAX_PROJECTS).map((f) => f.path);
}

function codexProjectKeys(configFile) {
  const text = safeRead(configFile) ?? '';
  const out = [];
  for (const m of text.matchAll(/^\[projects\.(?:("(?:[^"\\]|\\.)*")|'([^']*)')\]/gm)) out.push(m[2] ?? unquote(m[1]));
  return out;
}

export function discoverProjects(r = roots()) {
  const globalClaude = realPath(r.claude.root);
  const seen = new Set();
  for (const p of [...logCwds(r.claude.logs), ...codexProjectKeys(join(r.codex.root, 'config.toml'))]) {
    if (!isAbsolute(p) || p.includes(`${sep}.claude${sep}worktrees${sep}`)) continue;
    const dir = join(p, '.claude');
    try { if (!statSync(dir).isDirectory() || realPath(dir) === globalClaude) continue; } catch { continue; }
    seen.add(resolve(p));
    if (seen.size >= MAX_PROJECTS) break;
  }
  return [...seen];
}

function addProject(path, items, hooks, problems) {
  const dir = join(path, '.claude');
  items.push(...skillsIn(join(dir, 'skills'), 'claude', undefined, path), ...agentsIn(join(dir, 'agents'), 'claude', undefined, path));
  for (const name of ['settings.json', 'settings.local.json']) {
    const file = join(dir, name);
    const cfg = jsonFile(file);
    if (cfg === undefined) problems.push(`${file} is not valid JSON, so its hooks cannot be shown.`);
    else if (cfg) hooks.push(...hooksFrom(cfg, 'claude', null, file, path));
  }
}

export function readInventory(r = roots()) {
  const items = [];
  const hooks = [];
  const problems = [];
  for (const cli of CLIS) {
    if (!existsSync(r[cli].root)) continue;
    items.push(...skillsIn(r[cli].skills, cli), ...agentsIn(r[cli].agents, cli));
    const cfg = jsonFile(r[cli].hookFile);
    if (cfg === undefined) problems.push(`${r[cli].hookFile} is not valid JSON, so its hooks cannot be shown or changed.`);
    else hooks.push(...hooksFrom(cfg, cli, null, r[cli].hookFile));
  }
  for (const p of pluginEntries(r)) {
    items.push(...skillsIn(join(p.path, 'skills'), 'claude', p.name), ...agentsIn(join(p.path, 'agents'), 'claude', p.name));
    const cfg = jsonFile(join(p.path, 'hooks', 'hooks.json'));
    if (cfg) hooks.push(...hooksFrom(cfg, 'claude', p.name, join(p.path, 'hooks', 'hooks.json')));
  }
  for (const path of discoverProjects(r)) addProject(path, items, hooks, problems);
  const overrides = jsonFile(r.claude.hookFile)?.skillOverrides ?? {};
  for (const it of items) {
    if (it.cli === 'claude' && it.kind === 'skill' && it.scope === 'global') it.override = overrides[it.name] ?? null;
  }
  const names = new Map();
  for (const it of items) names.set(`${it.cli}:${rowKey(it)}`, true);
  for (const it of items) {
    const other = it.cli === 'claude' ? 'codex' : 'claude';
    it.inOther = names.has(`${other}:${rowKey(it)}`);
  }
  return { items, hooks, problems, events: EVENTS, roots: { claude: r.claude.root, codex: r.codex.root } };
}

export function readItemFile(file) {
  const st = statSync(file);
  const text = safeRead(file) ?? '';
  return { size: st.size, text: text.slice(0, 64 * 1024), truncated: text.length > 64 * 1024 };
}

// ---- Usage cells for the Matrix ------------------------------------------------------------------------------
// Cell = { state: 'counted' | 'pending' | 'unmeasurable' | 'missing', runs?, errors?, last?, reason? }
//   counted      runs is how many times it ran (hooks) or how many sessions used it (skills, agents); 0 = never ran
//                inside the scanned logs. `errors` is set for hooks.
//   pending      installed, but no scanned log can have covered it yet (see isPending)
//   unmeasurable the CLI does not log it (Codex hooks), `reason` says why
//   missing      not installed in that CLI
export const PENDING_GRACE_MS = 24 * 3600 * 1000;
const CODEX_HOOKS_REASON = 'Codex does not log hook runs';

// HEURISTIC, not a fact: the age of an item is unknowable, so the mtime of its file stands in for "installed at"
// (SKILL.md, the agent file, or the settings file that holds the hook; any edit of that file moves it).
// An item with zero runs is "pending" instead of "never ran" when
//   1. its CLI has no scanned logs at all, or
//   2. it changed within the last 24 hours, or
//   3. it changed after the newest scanned log, so no session could have used it yet.
function pendingReason(addedMs, window, now) {
  if (window && window.files === 0) return 'No logs scanned for this CLI yet';
  if (addedMs != null && now - addedMs < PENDING_GRACE_MS) return 'Added in the last 24 hours';
  if (addedMs != null && window?.newest != null && addedMs > window.newest) return 'Added after the newest log';
  return null;
}

function cellFor(x, cli, usage, now, addedAt) {
  if (!x) return { state: 'missing' };
  if (x.kind === 'hook' && cli === 'codex') return { state: 'unmeasurable', reason: CODEX_HOOKS_REASON };
  if (!usage?.totals) return { state: 'pending', reason: 'Usage scan has not finished' };
  const u = usage.totals[cli]?.[x.kind]?.[x.kind === 'hook' ? x.hash : bare(x.name)];
  const runs = (x.kind === 'hook' ? u?.runs : u?.sessions) ?? 0;
  if (runs === 0) {
    const reason = pendingReason(addedAt(x.file), usage.windows?.[cli], now);
    if (reason) return { state: 'pending', reason };
  }
  return x.kind === 'hook' ? { state: 'counted', runs, errors: u?.errors ?? 0, last: u?.last ?? null } : { state: 'counted', runs, last: u?.last ?? null };
}

// Pure. `usage` is the server's usage state: { state, totals, windows } where totals and windows come from scan().
// Adds `key` and `cells: { claude, codex }` to every item and hook, and `usage` (runs, avgMs, totalMs, errors,
// last; null when unknown or not logged) to every hook. Hook runs are keyed by event plus command, so the same
// hook in a global and a project file shares one count: the log does not say which file it came from.
export function attachUsage(inv, usage, { now = Date.now() } = {}) {
  const groups = new Map();
  for (const x of [...inv.items, ...inv.hooks]) {
    const g = groups.get(rowKey(x)) ?? {};
    g[x.cli] = x;
    groups.set(rowKey(x), g);
  }
  const mtimes = new Map();
  const addedAt = (file) => {
    if (!mtimes.has(file)) { try { mtimes.set(file, statSync(file).mtimeMs); } catch { mtimes.set(file, null); } }
    return mtimes.get(file);
  };
  const withCells = (x) => {
    const g = groups.get(rowKey(x));
    return { ...x, key: rowKey(x), cells: Object.fromEntries(CLIS.map((cli) => [cli, cellFor(g[cli], cli, usage, now, addedAt)])) };
  };
  const hooks = inv.hooks.map((h) => {
    const u = usage?.totals?.[h.cli]?.hook?.[h.hash];
    const measured = h.cli === 'claude' && usage?.totals;
    return { ...withCells(h), usage: measured ? { runs: u?.runs ?? 0, avgMs: u?.timed ? Math.round(u.ms / u.timed) : null, totalMs: u?.ms ?? 0, errors: u?.errors ?? 0, last: u?.last ?? null } : null };
  });
  return { ...inv, items: inv.items.map(withCells), hooks };
}

// Counts for the filter chips. Rows are deduplicated by key, so a skill in both CLIs counts once.
// neverRan: it ran in no CLI that logs it, and at least one CLI counted it; a dead hook is counted only under dead.
// dead: a hook whose script is gone.
export function filterCounts(rows) {
  const seen = new Map();
  for (const x of rows) {
    const key = x.key ?? rowKey(x);
    const row = seen.get(key) ?? { clis: new Set(), cells: [], dead: false };
    for (const cli of CLIS) {
      const c = x.cells?.[cli];
      if (c ? c.state !== 'missing' : cli === x.cli || x.inOther) row.clis.add(cli);
      if (c && c.state !== 'missing' && !row.cells.some((o) => o.cli === cli)) row.cells.push({ cli, ...c });
    }
    row.dead ||= x.dead === true;
    seen.set(key, row);
  }
  const out = { all: seen.size, only: { claude: 0, codex: 0 }, neverRan: 0, dead: 0 };
  for (const row of seen.values()) {
    if (row.clis.size === 1) out.only[[...row.clis][0]]++;
    const counted = row.cells.filter((c) => c.state === 'counted');
    if (!row.dead && counted.length > 0 && counted.every((c) => c.runs === 0)) out.neverRan++;
    if (row.dead) out.dead++;
  }
  return out;
}
