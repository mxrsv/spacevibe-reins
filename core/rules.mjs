// Permissions: read and edit Claude Code rules, read (never write) the Codex permission keys.
//
// Claude Code stores concrete rules in `permissions.allow|ask|deny` of settings.json. The
// capability grid below derives one state per capability from those rules.
//
//   Rule shape                                       Capability   Role in the cell
//   ------------------------------------------------ ------------ ----------------
//   Read (bare, Read(), Read(*); Read(<path>) is not)  Read files   wide
//   Read(<path>)                                     Read files   narrow
//   Read(<path>) naming .env (Read(./.env*))         Secrets      own
//   Read (bare)                                      Secrets      wide (also hits .env)
//   Edit | Write | MultiEdit (bare)                  Edit files   wide
//   Edit | Write | MultiEdit (<path>)                Edit files   narrow
//   Bash (bare) or Bash(*)                           Run commands wide
//   Bash(<command>) except the push prefixes         Run commands narrow
//   Bash (bare) or Bash(*)                           Push+deploy  wide (also hits push)
//   Bash(git push ..) Bash(vercel ..) and the        Push+deploy  own
//     other deploy-like prefixes in PUSH_RE
//   WebFetch | WebSearch (bare)                      Network      wide
//   WebFetch(..) | WebSearch(..)                     Network      narrow
//   anything else (mcp__*, Skill, Task, ...)         no cell      -
//
// State of a cell (deny beats ask beats allow, as in Claude Code):
//   no rule at all                                   none
//   a wide deny                                      deny
//   wide ask   + narrow deny                         mixed;  wide ask   otherwise: ask
//   wide allow + narrow deny or ask                  mixed;  wide allow otherwise: allow
//   narrow rules only                                mixed   (a scoped rule is not a cell value)
//   own rules only (Push and deploy, Secrets)        their verdict when all agree, else mixed
//   wide + own rules                                 strongest verdict among all of them
// Rules from several scopes can be merged first: the same function sees one flat list.
//
// Writing a cell replaces the cell's rules in ONE settings file with canonical ones:
//   Read -> `Read`; Edit -> `Edit`; Run -> `Bash`; Network -> `WebFetch` + `WebSearch`;
//   Push and deploy -> PUSH_RULES; Secrets -> SECRET_RULES. A `mixed` cell is refused.
//
// Codex is read-only here. Only the keys named in readCodexPermissions are read: nothing under
// [mcp_servers.*], [shell_environment_policy], env tables or auth files is ever looked at.
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { isAbsolute, join, resolve } from 'node:path';
import { UserError, editFile, record } from './mutate.mjs';

export const VERDICTS = ['allow', 'ask', 'deny'];
export const CAPABILITIES = ['read', 'edit', 'run', 'network', 'push', 'secrets'];
export const CAPABILITY_LABELS = {
  read: 'Read files', edit: 'Edit files', run: 'Run commands', network: 'Network', push: 'Push and deploy', secrets: 'Secrets (.env)',
};
export const PUSH_RULES = ['Bash(git push *)', 'Bash(vercel *)'];
export const SECRET_RULES = ['Read(./.env)', 'Read(./.env.*)'];

const PUSH_RE = /^(git\s+push|vercel|netlify|firebase\s+deploy|fly\s+deploy|wrangler\s+(deploy|publish)|(npm|pnpm|yarn)\s+publish|docker\s+push|gh\s+release|gh\s+pr\s+merge)\b|\bdeploy\b/;
const ENV_RE = /(^|[/*])\.env/;
const MAX_RULE_LENGTH = 1000;
const RULE_RE = /^([A-Za-z][\w.-]*)(?:\(([\s\S]*)\))?$/;
const VERDICT_LABEL = { allow: 'Allow', ask: 'Ask', deny: 'Deny' };

const need = (cond, msg, status) => { if (!cond) throw new UserError(msg, status); };
const validVerdict = (v) => need(VERDICTS.includes(v), 'Verdict must be allow, ask or deny.');

// --- Scopes and files ---

// scope: { kind: 'global' } | { kind: 'project' | 'local', dir: '/abs/project' }
export function scopesFor(dir) {
  return dir ? [{ kind: 'global' }, { kind: 'project', dir }, { kind: 'local', dir }] : [{ kind: 'global' }];
}

export function scopeFile(r, scope) {
  need(scope && ['global', 'project', 'local'].includes(scope.kind), 'Unknown scope.');
  if (scope.kind === 'global') return r.claude.hookFile;
  need(typeof scope.dir === 'string' && isAbsolute(scope.dir), 'A project scope needs an absolute folder.');
  const dir = resolve(scope.dir);
  need(existsSync(dir) && statSync(dir).isDirectory(), 'That project folder does not exist.', 404);
  return join(dir, '.claude', scope.kind === 'project' ? 'settings.json' : 'settings.local.json');
}

// Error text never includes file content, because a parse error message can quote it.
function parseConfig(file, text) {
  if (text == null || text.trim() === '') return {};
  let config;
  try { config = JSON.parse(text); } catch { throw new UserError(`${file} is not valid JSON. Nothing was changed.`, 409); }
  need(config && typeof config === 'object' && !Array.isArray(config), `${file} does not hold a JSON object. Nothing was changed.`, 409);
  return config;
}

function permissionsOf(file, config) {
  const perms = config.permissions ?? {};
  need(perms && typeof perms === 'object' && !Array.isArray(perms), `${file} has a permissions value that is not an object. Nothing was changed.`, 409);
  for (const v of VERDICTS) {
    need(perms[v] === undefined || Array.isArray(perms[v]), `${file} has permissions.${v} that is not a list. Nothing was changed.`, 409);
  }
  return perms;
}

export function parseRule(rule) {
  if (typeof rule !== 'string') return null;
  const m = RULE_RE.exec(rule.trim());
  if (!m) return null;
  const specifier = m[2] === undefined || m[2].trim() === '' ? null : m[2];
  return { tool: m[1], specifier };
}

// --- Listing ---

export function listRules(r, scopes = [{ kind: 'global' }]) {
  const rules = [];
  const problems = [];
  for (const scope of scopes) {
    const file = scopeFile(r, scope);
    if (!existsSync(file)) continue;
    let perms;
    try { perms = permissionsOf(file, parseConfig(file, readFileSync(file, 'utf8'))); } catch (e) {
      if (e instanceof UserError) { problems.push(e.message.replace(' Nothing was changed.', '')); continue; }
      throw e;
    }
    for (const verdict of VERDICTS) {
      for (const rule of perms[verdict] ?? []) {
        if (typeof rule !== 'string') continue;
        const p = parseRule(rule);
        rules.push({ id: `${scope.kind}:${verdict}:${rule}`, scope: scope.kind, dir: scope.dir ?? null, file, verdict, rule, tool: p?.tool ?? null, specifier: p?.specifier ?? null });
      }
    }
  }
  return { rules, problems };
}

// --- Capability grid (pure) ---

function placements(p) {
  const wide = p.specifier === null || p.specifier.trim() === '*';
  switch (p.tool) {
    case 'Read':
      if (wide) return [['read', 'wide'], ['secrets', 'wide']];
      return ENV_RE.test(p.specifier) ? [['secrets', 'own']] : [['read', 'narrow']];
    case 'Edit': case 'Write': case 'MultiEdit':
      return [['edit', wide ? 'wide' : 'narrow']];
    case 'Bash':
      if (wide) return [['run', 'wide'], ['push', 'wide']];
      return PUSH_RE.test(p.specifier.trim()) ? [['push', 'own']] : [['run', 'narrow']];
    case 'WebFetch': case 'WebSearch':
      return [['network', wide ? 'wide' : 'narrow']];
    default:
      return [];
  }
}

const strongest = (set) => ['deny', 'ask', 'allow'].find((v) => set.has(v)) ?? null;
const verdictsOf = (list) => new Set(list.map((x) => x.verdict));

function cellState({ wide, own, narrow }) {
  if (!wide.length && !own.length && !narrow.length) return 'none';
  const w = verdictsOf(wide);
  if (w.has('deny')) return 'deny';
  const o = verdictsOf(own);
  if (!narrow.length) {
    if (!own.length) return strongest(w);
    if (wide.length) return strongest(new Set([...w, ...o]));
    return o.size === 1 ? [...o][0] : 'mixed';
  }
  const n = verdictsOf(narrow);
  if (w.has('ask')) return n.has('deny') ? 'mixed' : 'ask';
  if (w.has('allow')) return n.has('deny') || n.has('ask') ? 'mixed' : 'allow';
  return 'mixed';
}

// rules: [{ verdict, rule, ... }] from one or several scopes.
export function capabilityGrid(rules) {
  const cells = Object.fromEntries(CAPABILITIES.map((c) => [c, { wide: [], own: [], narrow: [] }]));
  for (const item of rules) {
    const p = parseRule(item.rule);
    if (!p || !VERDICTS.includes(item.verdict)) continue;
    for (const [cap, role] of placements(p)) cells[cap][role].push(item);
  }
  return CAPABILITIES.map((capability) => {
    const c = cells[capability];
    const state = cellState(c);
    return { capability, label: CAPABILITY_LABELS[capability], state, editable: state !== 'mixed', rules: [...c.wide, ...c.own, ...c.narrow] };
  });
}

// --- Writing ---

// Which of a cell's rules a cell write replaces, and what it writes.
const REPLACE_ROLE = { read: 'wide', edit: 'wide', run: 'wide', network: 'wide', push: 'own', secrets: 'own' };
const WRITE_RULES = { read: ['Read'], edit: ['Edit'], run: ['Bash'], network: ['WebFetch', 'WebSearch'], push: PUSH_RULES, secrets: SECRET_RULES };

function indentOf(text) {
  return /^([ \t]+)"/m.exec(text ?? '')?.[1] ?? '  ';
}

function serialize(config, previous) {
  const crlf = previous?.includes('\r\n');
  const out = JSON.stringify(config, null, indentOf(previous));
  const withEol = crlf ? out.replaceAll('\n', '\r\n') : out;
  return previous == null || previous.endsWith('\n') || previous.trim() === '' ? `${withEol}${crlf ? '\r\n' : '\n'}` : withEol;
}

// Pure: returns a new config plus whether anything changed. Does not touch the input.
function withRules(file, config, { remove = [], add = [] }) {
  const perms = permissionsOf(file, config);
  const next = { ...perms };
  let changed = false;
  for (const v of VERDICTS) {
    const drop = new Set(remove.filter((x) => x.verdict === v).map((x) => x.rule));
    const put = add.filter((x) => x.verdict === v).map((x) => x.rule);
    if (!drop.size && !put.length) continue;
    const kept = (perms[v] ?? []).filter((x) => !(typeof x === 'string' && drop.has(x)));
    const fresh = put.filter((x, i) => !kept.includes(x) && put.indexOf(x) === i);
    if (kept.length !== (perms[v] ?? []).length || fresh.length) changed = true;
    next[v] = [...kept, ...fresh];
  }
  return { config: changed ? { ...config, permissions: next } : config, changed };
}

function editRules(r, scope, change, label) {
  const file = scopeFile(r, scope);
  const op = editFile(r, file, (text) => {
    const config = parseConfig(file, text);
    const res = change(file, config);
    return res.changed ? serialize(res.config, text) : text;
  }, { validate: (text) => parseConfig(file, text) });
  return op ? record(r, label, [op]) : null;
}

const scopeLabel = (scope) => (scope.kind === 'global' ? 'global' : `${scope.kind} ${scope.dir}`);

function checkRule(rule) {
  need(typeof rule === 'string' && rule.trim(), 'Enter a rule such as Bash(npm test *).');
  const text = rule.trim();
  need(text.length <= MAX_RULE_LENGTH && !/[\r\n]/.test(text) && parseRule(text), 'That is not a valid rule. Use Tool or Tool(pattern) on one line.');
  return text;
}

function findRule(perms, rule) {
  return VERDICTS.find((v) => (perms[v] ?? []).includes(rule)) ?? null;
}

export function addRule(r, { scope, verdict, rule }) {
  validVerdict(verdict);
  const text = checkRule(rule);
  return editRules(r, scope, (file, config) => {
    const at = findRule(permissionsOf(file, config), text);
    need(!at, `${text} is already in ${at}. Change its verdict instead.`, 409);
    return withRules(file, config, { add: [{ verdict, rule: text }] });
  }, `Added ${verdict} rule ${text} (${scopeLabel(scope)})`);
}

export function removeRule(r, { scope, verdict, rule }) {
  validVerdict(verdict);
  return editRules(r, scope, (file, config) => {
    need((permissionsOf(file, config)[verdict] ?? []).includes(rule), 'This rule has already changed. Refresh the list.', 409);
    return withRules(file, config, { remove: [{ verdict, rule }] });
  }, `Removed ${verdict} rule ${rule} (${scopeLabel(scope)})`);
}

export function changeVerdict(r, { scope, rule, from, to }) {
  validVerdict(from);
  validVerdict(to);
  need(from !== to, 'The rule already has that verdict.');
  return editRules(r, scope, (file, config) => {
    const perms = permissionsOf(file, config);
    need((perms[from] ?? []).includes(rule), 'This rule has already changed. Refresh the list.', 409);
    return withRules(file, config, { remove: [{ verdict: from, rule }], add: [{ verdict: to, rule }] });
  }, `Changed ${rule} from ${from} to ${to} (${scopeLabel(scope)})`);
}

// --- Capability cell writes ---

function planCapability(r, { scope, capability, verdict }) {
  need(CAPABILITIES.includes(capability), 'Unknown capability.');
  validVerdict(verdict);
  const file = scopeFile(r, scope);
  const { rules, problems } = listRules(r, [scope]);
  need(!problems.length, `${problems[0] ?? ''}. Nothing was changed.`, 409);
  const cell = capabilityGrid(rules).find((c) => c.capability === capability);
  need(cell.state !== 'mixed', `${CAPABILITY_LABELS[capability]} has rules for specific paths or commands here, so it has no single value. Edit the individual rules instead.`, 409);
  const role = REPLACE_ROLE[capability];
  const replaces = rules.filter((x) => { const p = parseRule(x.rule); return p && placements(p).some(([c, ro]) => c === capability && ro === role); });
  const writes = WRITE_RULES[capability].map((rule) => ({ verdict, rule }));
  const kept = rules.filter((x) => !replaces.includes(x));
  const resulting = capabilityGrid([...kept, ...writes]).find((c) => c.capability === capability).state;
  return {
    capability, verdict, scope, file, current: cell.state, resulting,
    replaces: replaces.map(({ verdict: v, rule }) => ({ verdict: v, rule })), writes,
  };
}

// What a cell write would remove and write. `resulting` differs from `verdict` when a rule that is
// kept (for example a bare Bash deny for Push and deploy) still wins.
export function previewSetCapability(r, args) {
  return planCapability(r, args);
}

export function setCapability(r, args) {
  const plan = planCapability(r, args);
  return editRules(r, plan.scope, (file, config) => withRules(file, config, { remove: plan.replaces, add: plan.writes }),
    `Set ${CAPABILITY_LABELS[plan.capability]} to ${VERDICT_LABEL[plan.verdict]} (${scopeLabel(plan.scope)})`);
}

// --- Codex (read-only) ---

function stripComment(line) {
  let quote = null;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quote) {
      if (quote === '"' && ch === '\\') i++;
      else if (ch === quote) quote = null;
    } else if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '#') return line.slice(0, i);
  }
  return line;
}

function depthOf(line) {
  let depth = 0;
  let quote = null;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quote) {
      if (quote === '"' && ch === '\\') i++;
      else if (ch === quote) quote = null;
    } else if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '[' || ch === '{') depth++;
    else if (ch === ']' || ch === '}') depth--;
  }
  return depth;
}

const unquoteKey = (s) => {
  if (s.startsWith('"')) { try { return JSON.parse(s); } catch { return s.slice(1, -1); } }
  return s.startsWith("'") ? s.slice(1, -1) : s;
};

function splitHeader(line) {
  const t = stripComment(line).trim();
  if (t.startsWith('[[')) return ['[[array]]'];
  if (!t.startsWith('[') || !t.endsWith(']')) return null;
  const body = t.slice(1, -1);
  const parts = body.match(/"(?:[^"\\]|\\.)*"|'[^']*'|[^.\s"']+/g);
  return parts ? parts.map(unquoteKey) : null;
}

// Small TOML value reader for strings, numbers, booleans, arrays and inline tables.
function parseValue(src) {
  let i = 0;
  const ws = () => { while (i < src.length && /\s/.test(src[i])) i++; };
  const value = () => {
    ws();
    const ch = src[i];
    if (ch === '"') {
      const m = /^"(?:[^"\\]|\\.)*"/.exec(src.slice(i));
      if (!m) return undefined;
      i += m[0].length;
      try { return JSON.parse(m[0]); } catch { return m[0].slice(1, -1); }
    }
    if (ch === "'") {
      const end = src.indexOf("'", i + 1);
      if (end < 0) return undefined;
      const out = src.slice(i + 1, end);
      i = end + 1;
      return out;
    }
    if (ch === '[') {
      i++;
      const out = [];
      for (;;) {
        ws();
        if (src[i] === ']') { i++; return out; }
        const v = value();
        if (v === undefined) return undefined;
        out.push(v);
        ws();
        if (src[i] === ',') i++;
      }
    }
    if (ch === '{') {
      i++;
      const out = {};
      for (;;) {
        ws();
        if (src[i] === '}') { i++; return out; }
        const m = /^("(?:[^"\\]|\\.)*"|'[^']*'|[\w.-]+)\s*=/.exec(src.slice(i));
        if (!m) return undefined;
        i += m[0].length;
        const v = value();
        if (v === undefined) return undefined;
        out[unquoteKey(m[1])] = v;
        ws();
        if (src[i] === ',') i++;
      }
    }
    const m = /^[^\s,\]}]+/.exec(src.slice(i));
    if (!m) return undefined;
    i += m[0].length;
    if (m[0] === 'true') return true;
    if (m[0] === 'false') return false;
    return /^[+-]?\d[\d_]*(\.\d+)?$/.test(m[0]) ? Number(m[0].replaceAll('_', '')) : m[0];
  };
  return value();
}

// Calls visit(table, key, getValue) for every key line. The value is parsed only when asked for.
function scanToml(text, visit) {
  const lines = text.split(/\r?\n/);
  let table = [];
  for (let i = 0; i < lines.length; i++) {
    const header = splitHeader(lines[i]);
    if (header) { table = header; continue; }
    const kv = /^\s*("(?:[^"\\]|\\.)*"|'[^']*'|[\w.-]+)\s*=\s*(.*)$/.exec(lines[i]);
    if (!kv) continue;
    let raw = kv[2];
    const multi = /^("""|''')/.exec(raw.trim());
    if (multi && !raw.trim().slice(3).includes(multi[1])) {
      while (i + 1 < lines.length) { i++; if (lines[i].includes(multi[1])) break; }
      visit(table, unquoteKey(kv[1]), () => undefined);
      continue;
    }
    raw = stripComment(raw);
    let depth = depthOf(raw);
    while (depth > 0 && i + 1 < lines.length) { i++; const more = stripComment(lines[i]); raw += `\n${more}`; depth += depthOf(more); }
    visit(table, unquoteKey(kv[1]), () => parseValue(raw));
  }
}

const eqPath = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const asStrings = (v) => (Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []);

function summarizeCodexRules(dir) {
  const out = { files: 0, allow: 0, prompt: 0, forbidden: 0, other: 0 };
  let names = [];
  try { names = readdirSync(dir).filter((f) => f.endsWith('.rules')); } catch { return out; }
  for (const name of names) {
    let text;
    try { text = readFileSync(join(dir, name), 'utf8'); } catch { continue; }
    out.files++;
    const code = text.split(/\r?\n/).filter((l) => !l.trimStart().startsWith('#')).join('\n');
    for (const chunk of code.split(/\bprefix_rule\s*\(/).slice(1)) {
      const d = /decision\s*=\s*["'](\w+)["']/.exec(chunk)?.[1] ?? 'allow';
      if (d in out && d !== 'files' && d !== 'other') out[d]++; else out.other++;
    }
  }
  return out;
}

export function readCodexPermissions(r) {
  const file = join(r.codex.root, 'config.toml');
  const out = {
    present: false, file, model: 'legacy', unrestricted: false, warnings: [],
    approval_policy: null, sandbox_mode: null, sandbox_workspace_write: null, default_permissions: null, approvals_reviewer: null,
    profiles: [], projects: [], rules: summarizeCodexRules(join(r.codex.root, 'rules')),
  };
  let text = null;
  try { text = readFileSync(file, 'utf8'); } catch { /* no config yet */ }
  if (text != null) {
    out.present = true;
    const profiles = new Map();
    const projects = new Map();
    const sww = {};
    const granular = {};
    const profile = (name) => { if (!profiles.has(name)) profiles.set(name, { name, filesystemEntries: 0, networkEntries: 0, networkFlags: {} }); return profiles.get(name); };
    scanToml(text, (table, key, get) => {
      const top = table.length === 0;
      if (top && ['approval_policy', 'sandbox_mode', 'default_permissions', 'approvals_reviewer'].includes(key)) out[key] = get() ?? null;
      else if (top && key === 'sandbox_workspace_write') Object.assign(sww, get() ?? {});
      else if (eqPath(table, ['sandbox_workspace_write']) && (key === 'network_access' || key === 'writable_roots')) sww[key] = get();
      else if (eqPath(table, ['approval_policy', 'granular'])) { if (typeof get() === 'boolean') granular[key] = get(); }
      else if (table[0] === 'permissions' && table.length >= 2) {
        const p = profile(table[1]);
        if (table[2] === 'filesystem') p.filesystemEntries++;
        else if (table[2] === 'network') {
          p.networkEntries++;
          const v = get();
          if (['boolean', 'string', 'number'].includes(typeof v) && /^[\w-]+$/.test(key)) p.networkFlags[key] = v;
        }
      } else if (table[0] === 'projects' && table.length === 2 && key === 'trust_level') projects.set(table[1], get());
      else if (eqPath(table, ['projects']) && typeof get()?.trust_level === 'string') projects.set(key, get().trust_level);
    });
    if (Object.keys(granular).length && (out.approval_policy == null || typeof out.approval_policy === 'object')) out.approval_policy = { granular };
    out.profiles = [...profiles.values()];
    out.projects = [...projects].map(([path, trust_level]) => ({ path, trust_level: typeof trust_level === 'string' ? trust_level : null }));
    if (Object.keys(sww).length) {
      out.sandbox_workspace_write = {
        network_access: typeof sww.network_access === 'boolean' ? sww.network_access : null,
        writable_roots: asStrings(sww.writable_roots),
      };
    }
  }
  const hasProfiles = out.default_permissions != null;
  const hasLegacy = out.sandbox_mode != null;
  out.model = hasProfiles && hasLegacy ? 'both' : hasProfiles ? 'profiles' : 'legacy';
  if (out.model === 'both') out.warnings.push('Both default_permissions and sandbox_mode are set. Codex expects only one of them.');
  out.unrestricted = out.sandbox_mode === 'danger-full-access';
  return out;
}
