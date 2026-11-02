// Reads what is installed for Claude Code and Codex. Never executes anything and
// never keeps settings values other than hooks, plugin flags and skill overrides.
import { createHash } from 'node:crypto';
import { existsSync, lstatSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { isAbsolute, join } from 'node:path';

export const CLIS = ['claude', 'codex'];
export const SYSTEM_DIRS = /^[._]/;

export const EVENTS = {
  claude: ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'PostToolUseFailure', 'Notification', 'SubagentStart', 'SubagentStop', 'Elicitation', 'ElicitationResult', 'TeammateIdle', 'PreCompact', 'PostCompact', 'Stop', 'StopFailure', 'SessionEnd'],
  codex: ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'SubagentStart', 'SubagentStop', 'Interrupt', 'Stop', 'SessionEnd'],
};

export function roots(env = process.env) {
  const home = env.HOME || homedir();
  const claude = env.CLAUDE_CONFIG_DIR || join(home, '.claude');
  const codex = env.CODEX_HOME || join(home, '.codex');
  return {
    claude: { root: claude, skills: join(claude, 'skills'), agents: join(claude, 'agents'), hookFile: join(claude, 'settings.json'), logs: join(claude, 'projects') },
    codex: { root: codex, skills: join(codex, 'skills'), agents: join(codex, 'agents'), hookFile: join(codex, 'hooks.json'), logs: join(codex, 'sessions') },
    data: env.REINS_HOME || join(home, '.reins'),
  };
}

export const sha = (s) => createHash('sha1').update(s).digest('hex').slice(0, 12);
export const bare = (name) => name.split(':').pop();

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

function skillsIn(dir, cli, owner) {
  const out = [];
  for (const entry of list(dir)) {
    if (SYSTEM_DIRS.test(entry)) continue;
    const path = join(dir, entry);
    const text = safeRead(join(path, 'SKILL.md'));
    if (text == null) continue;
    const fm = frontmatter(text);
    out.push({
      id: `${cli}:skill:${owner ?? 'local'}:${entry}`, cli, kind: 'skill', name: fm.name || entry, entry,
      description: fm.description ?? '', owner: owner ?? ownerOf(path), path, file: join(path, 'SKILL.md'), removable: !owner,
    });
  }
  return out;
}

function agentsIn(dir, cli, owner) {
  const out = [];
  for (const entry of list(dir)) {
    const isMd = entry.endsWith('.md');
    if ((!isMd && !entry.endsWith('.toml')) || SYSTEM_DIRS.test(entry)) continue;
    const path = join(dir, entry);
    const text = safeRead(path);
    if (text == null) continue;
    const f = isMd ? frontmatter(text) : tomlFields(text);
    out.push({
      id: `${cli}:agent:${owner ?? 'local'}:${entry}`, cli, kind: 'agent', name: f.name || entry.replace(/\.(md|toml)$/, ''), entry,
      description: f.description ?? '', owner: owner ?? ownerOf(path), path, file: path, removable: !owner,
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

function hooksFrom(config, cli, owner, sourceFile) {
  const out = [];
  for (const [event, groups] of Object.entries(config?.hooks ?? {})) {
    if (!Array.isArray(groups)) continue;
    groups.forEach((g) => (g.hooks ?? []).forEach((hook) => {
      if (typeof hook.command !== 'string') return;
      const paths = scriptPaths(hook.command);
      const dead = paths.length > 0 && !paths.some((p) => existsSync(p));
      out.push({
        id: `${cli}:hook:${sha(`${owner ?? ''}|${event}|${g.matcher ?? ''}|${hook.command}`)}`, cli, kind: 'hook', event,
        matcher: g.matcher ?? null, command: hook.command, timeout: hook.timeout ?? null, async: hook.async ?? false,
        owner: owner ?? 'user', removable: !owner, dead, paths, hash: sha(`${event}|${hook.command}`), file: sourceFile,
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
  const overrides = jsonFile(r.claude.hookFile)?.skillOverrides ?? {};
  for (const it of items) {
    if (it.cli === 'claude' && it.kind === 'skill') it.override = overrides[it.name] ?? null;
  }
  const names = new Map();
  for (const it of items) names.set(`${it.cli}:${it.kind}:${bare(it.name)}`, true);
  for (const it of items) {
    const other = it.cli === 'claude' ? 'codex' : 'claude';
    it.inOther = names.has(`${other}:${it.kind}:${bare(it.name)}`);
  }
  return { items, hooks, problems, events: EVENTS, roots: { claude: r.claude.root, codex: r.codex.root } };
}

export function readItemFile(file) {
  const st = statSync(file);
  const text = safeRead(file) ?? '';
  return { size: st.size, text: text.slice(0, 64 * 1024), truncated: text.length > 64 * 1024 };
}
