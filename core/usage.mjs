// Counts real usage from session logs. Runs in a worker because logs reach several GB.
// Only names, dates, hook hashes and durations are stored in the cache, never log text.
import { createReadStream, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { parentPort, workerData } from 'node:worker_threads';
import { bare, roots, sha } from './inventory.mjs';

const TS = /"timestamp":"(\d{4}-\d{2}-\d{2})T/;
const SKILL_TOOL = /"name":"Skill","input":\{"skill":"([^"]+)"/g;
const SLASH = /<command-name>\/([\w:-]+)<\/command-name>/g;
const SUBAGENT = /"subagent_type":"([^"]+)"/g;
const CODEX_SKILL = /skills\/([\w-]+)\/SKILL\.md/g;
const CODEX_AGENT = /\\?"agent_type\\?":\s*\\?"([\w-]+)/g;
const CODEX_CALL = /"type":"(function_call|custom_tool_call)"|"CommandExecution"/;

function walk(dir, out = []) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.isFile() && e.name.endsWith('.jsonl')) out.push(p);
  }
  return out;
}

async function eachLine(file, fn) {
  let rest = '';
  for await (const chunk of createReadStream(file, { encoding: 'utf8', highWaterMark: 1 << 20 })) {
    const lines = (rest + chunk).split('\n');
    rest = lines.pop();
    for (const line of lines) fn(line);
  }
  if (rest) fn(rest);
}

function sessionOf(file) {
  const parts = file.split('/');
  const i = parts.lastIndexOf('subagents');
  return i > 0 ? parts[i - 1] : basename(file, '.jsonl');
}

const note = (rec, group, name, day) => {
  rec[group][name] ??= [];
  if (day && !rec[group][name].includes(day)) rec[group][name].push(day);
};

function scanClaudeLine(line, rec, fallbackDay) {
  const hasSkill = line.includes('"name":"Skill"');
  const hasSlash = line.includes('<command-name>') && line.includes('"type":"user"');
  const hasAgent = line.includes('"subagent_type":"');
  const hasHook = line.includes('"attachment"') && line.includes('"hook');
  if (!hasSkill && !hasSlash && !hasAgent && !hasHook) return;
  const day = TS.exec(line)?.[1] ?? fallbackDay;
  if (hasSkill) for (const m of line.matchAll(SKILL_TOOL)) note(rec, 'skill', bare(m[1]), day);
  if (hasSlash) for (const m of line.matchAll(SLASH)) note(rec, 'skill', bare(m[1]), day);
  if (hasAgent) for (const m of line.matchAll(SUBAGENT)) note(rec, 'agent', bare(m[1]), day);
  if (hasHook) {
    let a;
    try { a = JSON.parse(line).attachment; } catch { return; }
    if (!a || typeof a.command !== 'string' || !String(a.type).startsWith('hook_')) return;
    const key = sha(`${a.hookEvent}|${a.command}`);
    const h = (rec.hook[key] ??= { runs: 0, ms: 0, timed: 0, errors: 0, last: null });
    h.runs++;
    if (Number.isFinite(a.durationMs)) { h.ms += a.durationMs; h.timed++; }
    if (/error/.test(a.type) || (Number.isFinite(a.exitCode) && a.exitCode !== 0)) h.errors++;
    if (day && (!h.last || day > h.last)) h.last = day;
  }
}

function scanCodexLine(line, rec, fallbackDay) {
  const hasSkill = line.includes('SKILL.md');
  const hasAgent = line.includes('agent_type');
  if ((!hasSkill && !hasAgent) || !CODEX_CALL.test(line)) return;
  const day = TS.exec(line)?.[1] ?? fallbackDay;
  if (hasSkill) for (const m of line.matchAll(CODEX_SKILL)) note(rec, 'skill', m[1], day);
  if (hasAgent) for (const m of line.matchAll(CODEX_AGENT)) note(rec, 'agent', m[1], day);
}

export function emptyTotals() {
  return { claude: { skill: {}, agent: {}, hook: {} }, codex: { skill: {}, agent: {}, hook: {} } };
}

export function aggregate(files) {
  const t = emptyTotals();
  const sessions = { claude: new Set(), codex: new Set() };
  for (const f of Object.values(files)) {
    const bucket = t[f.cli];
    sessions[f.cli].add(f.session);
    for (const group of ['skill', 'agent']) {
      for (const [name, days] of Object.entries(f.rec[group])) {
        const u = (bucket[group][name] ??= { sessionSet: new Set(), days: new Set() });
        u.sessionSet.add(f.session);
        for (const d of days) u.days.add(d);
      }
    }
    for (const [key, h] of Object.entries(f.rec.hook)) {
      const u = (bucket.hook[key] ??= { runs: 0, ms: 0, timed: 0, errors: 0, last: null });
      u.runs += h.runs; u.ms += h.ms; u.timed += h.timed; u.errors += h.errors;
      if (h.last && (!u.last || h.last > u.last)) u.last = h.last;
    }
  }
  for (const cli of ['claude', 'codex']) {
    for (const group of ['skill', 'agent']) {
      for (const [name, u] of Object.entries(t[cli][group])) {
        const days = [...u.days].sort();
        t[cli][group][name] = { sessions: u.sessionSet.size, days, last: days.at(-1) ?? null };
      }
    }
  }
  return { totals: t, sessions: { claude: sessions.claude.size, codex: sessions.codex.size } };
}

export async function scan(r, onProgress = () => {}) {
  const cachePath = join(r.data, 'usage-cache.json');
  let cache = {};
  if (existsSync(cachePath)) { try { cache = JSON.parse(readFileSync(cachePath, 'utf8')); } catch { cache = {}; } }
  const targets = [
    ...walk(r.claude.logs).map((file) => ({ file, cli: 'claude' })),
    ...walk(r.codex.logs).map((file) => ({ file, cli: 'codex' })),
  ];
  const next = {};
  let done = 0;
  for (const { file, cli } of targets) {
    let st;
    try { st = statSync(file); } catch { done++; continue; }
    const stamp = `${st.size}:${Math.floor(st.mtimeMs)}`;
    if (cache[file]?.stamp === stamp) next[file] = cache[file];
    else {
      const rec = { skill: {}, agent: {}, hook: {} };
      const fallbackDay = st.mtime.toISOString().slice(0, 10);
      const onLine = cli === 'claude' ? (l) => scanClaudeLine(l, rec, fallbackDay) : (l) => scanCodexLine(l, rec, fallbackDay);
      try { await eachLine(file, onLine); } catch { done++; continue; }
      next[file] = { stamp, cli, session: sessionOf(file), rec };
    }
    done++;
    if (done % 200 === 0) onProgress(done, targets.length);
  }
  mkdirSync(dirname(cachePath), { recursive: true, mode: 0o700 });
  writeFileSync(cachePath, JSON.stringify(next), { mode: 0o600 });
  return { ...aggregate(next), files: targets.length };
}

if (parentPort && workerData?.usageScan) {
  const r = roots(workerData.env);
  scan(r, (done, total) => parentPort.postMessage({ type: 'progress', done, total }))
    .then((result) => parentPort.postMessage({ type: 'done', result }))
    .catch((err) => parentPort.postMessage({ type: 'error', message: err.message }));
}
