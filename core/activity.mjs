// Activity tab data: running sessions of both CLIs, failed commands and file history.
// Read-only on logs; it never executes a recorded command or hook (AGENTS.md R4).
//
//   readActivity(r, { now, proc, cache, prices, historyDays, maxHistoryFiles, ... }) => Promise<{
//     sessions: Session[], failures: Failure[], files: FileRow[], unmeasurable: Limit[], stats }>
//
//   r       roots() from inventory.mjs.
//   now     epoch ms; every age is computed against it (default Date.now()).
//   proc    process adapter, see process-adapter.mjs (default: the real ps/lsof/kill -0).
//   cache   Map that keeps per-log read offsets and folded state between calls, so a repeated call
//           reads only appended bytes. Default is one shared module-level Map.
//   prices  pricing table, default core/pricing.json (per million tokens, API-equivalent).
//
//   Session  { cli: 'claude'|'codex', id, title, project, pid,
//              state: 'running'|'waiting'|'idle'|'ended'|'unmeasurable',
//              stateReason, reasonCode: string|null (set when unmeasurable, key of UNMEASURABLE),
//              currentTool: { name, target }|null,
//              ageMs      since the session started,
//              lastWriteAgoMs  since the transcript (or a subagent transcript) was last written;
//                         this is the age to show, because Claude's statusUpdatedAt goes stale,
//              cost: { usd, estimated: true }|null, costNote: string|null }
//   Failure  { kind: 'command'|'hook', cli, key, title, count, exit, reason, projects, sessions,
//              first, last (ISO), laterPass (ISO|null), hook: { hash, event }|null }
//   FileRow  { path, label, edits, sessions, last (ISO), clis, projects }
//   Limit    { cli, code, text }   what cannot be measured, listed even when no session is live
import { closeSync, fstatSync, openSync, readFileSync, readSync, readdirSync, statSync } from 'node:fs';
import { basename, join, relative, sep } from 'node:path';
import { foldLine, newState } from './activity-fold.mjs';
import { groupFailures, groupFiles } from './activity-groups.mjs';
import { systemProc } from './process-adapter.mjs';
import { pickTitle, projectName } from './session-titles.mjs';
import { TailReader } from './tail-reader.mjs';

const MB = 1024 * 1024;
export const TOOL_QUIET_MS = 30_000; // an open tool call with no log write for this long is ambiguous
export const ENDED_KEEP_MS = 15 * 60_000; // a dead Claude session is listed as "ended" for this long
const DAY_MS = 86_400_000;
const CHILD_HEAD_BYTES = 64 * 1024;
const INDEX_TAIL_BYTES = 1 * MB;
const MAX_SUBAGENT_LOGS = 50;
const UUID_FILE = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/;

/** Reasons a state cannot be known. The wording is Activity's own: the plan only lists the facts. */
export const UNMEASURABLE = {
  'codex-no-rollout': 'Codex writes no log until the first prompt is sent, so this session cannot be read yet.',
  'codex-tool-silent': 'Codex logs nothing while a tool runs and does not record approval waits, so a long command and a wait for approval look the same.',
  'claude-prompt-vs-busy': 'Claude Code does not record permission prompts, so a long tool run and a wait for approval look the same.',
  'claude-unknown-status': 'The Claude Code status file reports a status this app does not know.',
  'codex-hook-runs': 'Codex does not log hook runs, so failed hooks are not shown for Codex.',
};
const LIMIT_CODES = [['claude', 'claude-prompt-vs-busy'], ['codex', 'codex-tool-silent'], ['codex', 'codex-no-rollout'], ['codex', 'codex-hook-runs']];
const limits = () => LIMIT_CODES.map(([cli, code]) => ({ cli, code, text: UNMEASURABLE[code] }));

const sharedCache = new Map();
let defaultPrices;
const loadPrices = () => (defaultPrices ??= JSON.parse(readFileSync(new URL('./pricing.json', import.meta.url), 'utf8')).models);

// ---- log discovery ----

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

function listLogs(r) {
  const files = [];
  const claudeMain = new Map();
  const claudeSubs = new Map();
  const codexById = new Map();
  for (const path of walk(r.claude.logs)) {
    const rel = relative(r.claude.logs, path).split(sep);
    const sub = rel.length >= 4 && rel[2] === 'subagents';
    const session = sub ? rel[1] : basename(path, '.jsonl');
    let st;
    try { st = statSync(path); } catch { continue; }
    const f = { path, cli: 'claude', session, sub, mtimeMs: st.mtimeMs };
    files.push(f);
    if (sub) claudeSubs.set(session, [...(claudeSubs.get(session) ?? []), f]);
    else if (rel.length === 2) claudeMain.set(session, f);
  }
  for (const path of walk(r.codex.logs)) {
    if (!basename(path).startsWith('rollout-')) continue;
    const id = UUID_FILE.exec(path)?.[1];
    if (!id) continue;
    let st;
    try { st = statSync(path); } catch { continue; }
    const f = { path, cli: 'codex', session: id, sub: false, mtimeMs: st.mtimeMs };
    files.push(f);
    codexById.set(id, f);
  }
  return { files, claudeMain, claudeSubs, codexById };
}

const readJson = (p) => { try { return JSON.parse(readFileSync(p, 'utf8')); } catch { return null; } };

function readHead(path, bytes) {
  let fd;
  try {
    fd = openSync(path, 'r');
    const buf = Buffer.alloc(Math.min(bytes, fstatSync(fd).size));
    readSync(fd, buf, 0, buf.length, 0);
    return buf.toString('utf8');
  } catch { return ''; } finally { if (fd != null) closeSync(fd); }
}

/** Codex subagent rollouts name their parent thread in session_meta (first 64 KB is enough). */
const isChildRollout = (path) => /"source":\{"subagent"|"parent_thread_id":"[0-9a-f]/.test(readHead(path, CHILD_HEAD_BYTES));

function codexThreadNames(r) {
  const path = join(r.codex.root, 'session_index.jsonl');
  const names = new Map();
  let fd;
  try {
    fd = openSync(path, 'r');
    const size = fstatSync(fd).size;
    const start = Math.max(0, size - INDEX_TAIL_BYTES);
    const buf = Buffer.alloc(size - start);
    readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift();
    for (const line of lines) {
      try { const j = JSON.parse(line); if (j.id && typeof j.thread_name === 'string') names.set(j.id, j.thread_name); } catch { /* partial or foreign line */ }
    }
  } catch { /* no index: titles fall back to the first request */ } finally { if (fd != null) closeSync(fd); }
  return names;
}

// ---- incremental folding ----

async function advance(cache, f, maxBytes) {
  let e = cache.get(f.path);
  if (!e) { e = { reader: new TailReader(f.path, { maxBytes }), st: newState(f.cli, f.path), truncated: false }; cache.set(f.path, e); }
  const res = await e.reader.read((line) => foldLine(e.st, line), () => { e.st = newState(f.cli, f.path); });
  if (res.missing) { cache.delete(f.path); return null; }
  e.truncated = res.truncated;
  return e;
}

// ---- cost ----

function priceFor(model, prices) {
  const clean = String(model).replace(/\[[^\]]*\]$/, '').replace(/-\d{8}$/, '');
  return prices[model] ?? prices[clean] ?? null;
}

/** metrics: { [model]: { input, output, cacheWrite, cacheWriteLong, cacheRead } } -> { usd } | { note } */
export function estimateCost(metrics, prices) {
  let usd = 0;
  let any = false;
  for (const [model, m] of Object.entries(metrics)) {
    const tokens = (m.input ?? 0) + (m.output ?? 0) + (m.cacheWrite ?? 0) + (m.cacheRead ?? 0);
    if (!tokens) continue;
    const rate = priceFor(model, prices);
    if (!rate) return { note: `No price for model "${model}", so no estimate.` };
    const long = Math.min(m.cacheWrite ?? 0, m.cacheWriteLong ?? 0);
    usd += ((m.input ?? 0) * rate.input + (m.output ?? 0) * rate.output + (m.cacheRead ?? 0) * rate.cacheRead
      + ((m.cacheWrite ?? 0) - long) * rate.cacheWrite + long * rate.cacheWriteLong) / 1_000_000;
    any = true;
  }
  return any ? { usd } : { note: 'No token usage logged yet.' };
}

function mergeMetrics(states) {
  const out = {};
  for (const st of states) {
    for (const [model, m] of Object.entries(st.metrics)) {
      const o = (out[model] ??= { input: 0, output: 0, cacheWrite: 0, cacheWriteLong: 0, cacheRead: 0 });
      for (const k of Object.keys(o)) o[k] += m[k] ?? 0;
    }
  }
  return out;
}

// A log read only from its tail has partial usage, and a partial sum would look like a real cost.
function costFor(entries, prices) {
  if (entries.some((e) => e.truncated)) return { cost: null, costNote: 'The log is too large to read in full, so no estimate.' };
  const est = estimateCost(mergeMetrics(entries.map((e) => e.st)), prices);
  return est.usd == null ? { cost: null, costNote: est.note } : { cost: { usd: est.usd, estimated: true }, costNote: null };
}

// ---- states ----

const lastPending = (st) => {
  const p = [...(st?.pending.values() ?? [])].at(-1);
  return p ? { name: p.name, target: p.target } : null;
};
const unmeasurable = (code) => ({ state: 'unmeasurable', reasonCode: code, stateReason: UNMEASURABLE[code], currentTool: null });

function claudeState({ alive, status, st, lastWriteAgoMs }) {
  if (!alive) return { state: 'ended', reasonCode: null, stateReason: 'The process has exited.', currentTool: null };
  const tool = lastPending(st);
  if (status === 'idle') return { state: 'idle', reasonCode: null, stateReason: 'Turn finished, waiting for the next prompt.', currentTool: null };
  if (status === 'shell') return { state: 'running', reasonCode: null, stateReason: 'Running a shell command.', currentTool: tool };
  if (status !== 'busy') return unmeasurable('claude-unknown-status');
  if (st?.questions.size) return { state: 'waiting', reasonCode: null, stateReason: 'Waiting for your answer to a question.', currentTool: tool };
  if (tool && lastWriteAgoMs > TOOL_QUIET_MS) return { ...unmeasurable('claude-prompt-vs-busy'), currentTool: tool };
  return { state: 'running', reasonCode: null, stateReason: tool ? 'A tool call is open.' : 'Turn in progress.', currentTool: tool };
}

function codexState({ st, lastWriteAgoMs }) {
  const tool = lastPending(st);
  if (st.status === 'busy') {
    if (st.questions.size) return { state: 'waiting', reasonCode: null, stateReason: 'Waiting for your answer to a question.', currentTool: tool };
    if (tool && lastWriteAgoMs > TOOL_QUIET_MS) return { ...unmeasurable('codex-tool-silent'), currentTool: tool };
    return { state: 'running', reasonCode: null, stateReason: tool ? 'A tool call is open.' : 'Turn in progress.', currentTool: tool };
  }
  const reason = st.status === 'idle' ? 'Turn finished or aborted, waiting for the next prompt.' : 'No turn recorded yet.';
  return { state: 'idle', reasonCode: null, stateReason: reason, currentTool: null };
}

// ---- readActivity ----

export async function readActivity(r, opts = {}) {
  const {
    now = Date.now(), proc = systemProc(), cache = sharedCache, prices = loadPrices(),
    historyDays = 14, maxHistoryFiles = 200, historyTailBytes = 4 * MB, liveTailBytes = 64 * MB,
    failureLimit = 200, fileLimit = 300,
  } = opts;
  const index = listLogs(r);
  const memo = new Map();

  // 1. Live processes.
  const claudeLive = [];
  const sessionsDir = join(r.claude.root, 'sessions');
  let names = [];
  try { names = readdirSync(sessionsDir).filter((n) => /^\d+\.json$/.test(n)); } catch { /* no Claude sessions folder */ }
  for (const n of names) {
    const s = readJson(join(sessionsDir, n));
    if (!s || !Number.isInteger(s.pid) || typeof s.sessionId !== 'string') continue;
    let alive = Boolean(await proc.alive(s.pid));
    if (alive && s.procStart && proc.startOf) {
      const started = await proc.startOf(s.pid);
      // A reused pid has a different start time; two readings that disagree mean another process.
      if (started && started.replace(/\s+/g, ' ') !== String(s.procStart).replace(/\s+/g, ' ')) alive = false;
    }
    claudeLive.push({ s, alive, main: index.claudeMain.get(s.sessionId) ?? null, subs: (index.claudeSubs.get(s.sessionId) ?? []).sort((x, y) => y.mtimeMs - x.mtimeMs) });
  }
  const threads = await proc.codexThreads();
  const codexPids = new Set(threads.filter((t) => t.threadId).map((t) => t.pid));

  // 2. Which logs to fold: live ones in full, the rest only if recent.
  const live = new Set();
  for (const c of claudeLive) for (const f of [c.main, ...c.subs.slice(0, MAX_SUBAGENT_LOGS)]) if (f) live.add(f.path);
  for (const t of threads) { const f = t.threadId && index.codexById.get(t.threadId); if (f) live.add(f.path); }
  const recent = index.files.filter((f) => f.mtimeMs >= now - historyDays * DAY_MS && !live.has(f.path))
    .sort((a, b) => b.mtimeMs - a.mtimeMs).slice(0, maxHistoryFiles);
  const targets = [...index.files.filter((f) => live.has(f.path)), ...recent];
  const folded = new Map();
  for (const f of targets) {
    try {
      const e = await advance(cache, f, live.has(f.path) ? liveTailBytes : historyTailBytes);
      if (e) folded.set(f.path, e);
    } catch { /* an unreadable log stays out of the lists */ }
  }
  const wanted = new Set(targets.map((f) => f.path));
  for (const p of cache.keys()) if (!wanted.has(p)) cache.delete(p);

  // 3. Sessions.
  const sessions = [];
  const lastWrite = (files) => Math.max(0, ...files.filter(Boolean).map((f) => f.mtimeMs));
  for (const c of claudeLive) {
    const e = c.main ? folded.get(c.main.path) : null;
    const st = e?.st ?? null;
    const written = lastWrite([c.main, ...c.subs]) || c.s.statusUpdatedAt || c.s.startedAt || now;
    const lastWriteAgoMs = Math.max(0, now - written);
    if (!c.alive && lastWriteAgoMs > ENDED_KEEP_MS) continue;
    const startedAt = c.s.startedAt ?? st?.startedAt ?? null;
    const subEntries = c.subs.slice(0, MAX_SUBAGENT_LOGS).map((f) => folded.get(f.path)).filter(Boolean);
    sessions.push({
      cli: 'claude', id: c.s.sessionId, pid: c.s.pid,
      title: pickTitle([st?.customTitle, st?.aiTitle, c.s.nameSource === 'derived' ? null : c.s.name, st?.firstPrompt], { startedAt, id: c.s.sessionId }),
      project: projectName(c.s.cwd ?? st?.cwd, { hint: st?.worktreeOriginal }, memo),
      ...claudeState({ alive: c.alive, status: c.s.status, st, lastWriteAgoMs }),
      ageMs: startedAt ? Math.max(0, now - startedAt) : null, lastWriteAgoMs,
      ...(e ? costFor([e, ...subEntries], prices) : { cost: null, costNote: 'No transcript found for this session.' }),
    });
  }
  const threadNames = codexThreadNames(r);
  const utc = (text) => (text ? Date.parse(`${text} UTC`) || null : null);
  for (const t of threads) {
    const f = t.threadId ? index.codexById.get(t.threadId) : null;
    if (t.threadId && f && isChildRollout(f.path)) continue;
    if (!t.threadId && codexPids.has(t.pid)) continue;
    const e = f ? folded.get(f.path) : null;
    if (!e) {
      const startedAt = utc(await proc.startOf?.(t.pid)); // the rollout does not exist yet, so the process start is the only clock
      sessions.push({
        cli: 'codex', id: t.threadId ?? `pid:${t.pid}`, pid: t.pid, title: pickTitle([threadNames.get(t.threadId)], { startedAt, id: t.threadId ?? `pid ${t.pid}` }),
        project: null, ...unmeasurable('codex-no-rollout'), ageMs: startedAt ? Math.max(0, now - startedAt) : null, lastWriteAgoMs: null, cost: null, costNote: UNMEASURABLE['codex-no-rollout'],
      });
      continue;
    }
    const lastWriteAgoMs = Math.max(0, now - f.mtimeMs);
    sessions.push({
      cli: 'codex', id: t.threadId, pid: t.pid,
      title: pickTitle([threadNames.get(t.threadId), e.st.firstPrompt], { startedAt: e.st.startedAt, id: t.threadId }),
      project: projectName(e.st.cwd, {}, memo),
      ...codexState({ st: e.st, lastWriteAgoMs }),
      ageMs: e.st.startedAt ? Math.max(0, now - e.st.startedAt) : null, lastWriteAgoMs, ...costFor([e], prices),
    });
  }
  sessions.sort((a, b) => a.cli.localeCompare(b.cli) || (a.lastWriteAgoMs ?? Infinity) - (b.lastWriteAgoMs ?? Infinity));

  // 4. Cross-session lists.
  const byPath = new Map(index.files.map((f) => [f.path, f]));
  const logs = [...folded.entries()].map(([path, e]) => {
    return { st: e.st, session: `${e.st.cli}:${byPath.get(path)?.session ?? path}`, project: projectName(e.st.cwd, { hint: e.st.worktreeOriginal }, memo) };
  });
  return {
    sessions, failures: groupFailures(logs, { limit: failureLimit }), files: groupFiles(logs, { limit: fileLimit }),
    unmeasurable: limits(), stats: { logs: folded.size, truncated: [...folded.values()].filter((e) => e.truncated).length },
  };
}
