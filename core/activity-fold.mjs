// Folds one session log (Claude transcript or Codex rollout) into a small state object, one line
// at a time. Read-only: it parses recorded text and never runs a recorded command or hook (R4).
// The state is mutated in place on purpose: logs reach hundreds of MB and a copy per line is too slow.
import { sha } from './inventory.mjs';
import { cleanTitle, isJunkTitle } from './session-titles.mjs';

const PREVIEW = 160;
const PASSES_PER_COMMAND = 50;
const QUESTION_TOOL = /(?:^|__|\.)(AskUserQuestion|request_user_input(?:_async)?)$/;
const EDIT_TOOLS = new Set(['Edit', 'MultiEdit', 'Write', 'NotebookEdit']);
const EXPLORE_RE = /^(cat|ls|rg|grep|find|sed|head|tail|wc|echo|pwd|which|stat|file|du|diff|git\s+(status|log|diff|show|branch|rev-parse|ls-files|grep|check-ignore)|gh\s+\S+\s+(view|list)|test\s|\[)/;
const ERROR_LINE_RE = /(\berror\b|\bfailed\b|\bfail\b|exception|cannot|could not|couldn't|not found|denied|panic|fatal|unexpected|undefined is|is not a function|✗|×)/i;
const PATCH_FILE_RE = /\*\*\* (?:Update|Add|Delete) File: ([^\n\\"]+)/g;

export const preview = (s, n = PREVIEW) => (typeof s === 'string' ? s.replace(/\s+/g, ' ').trim().slice(0, n) : '');
const stripCd = (cmd) => String(cmd ?? '').trim().replace(/^cd\s+\S+\s*(&&|;)\s*/, '');
export const normalizeCommand = (cmd) => stripCd(cmd).replace(/\s+/g, ' ').slice(0, 400);
// grep/ls/diff exit non-zero by design, so they are not failures.
const isExploratory = (cmd) => EXPLORE_RE.test(stripCd(cmd));

/** The line a person would quote from a failure, not the runner's preamble. */
export function errorLine(output) {
  const lines = String(output ?? '').split('\n').map((l) => l.trim()).filter((l) => l && !/^Exit code \d+$/.test(l));
  return (lines.find((l) => ERROR_LINE_RE.test(l) && !/\b0 (failed|errors?)\b/i.test(l)) ?? '').slice(0, PREVIEW);
}

const textOf = (content) => {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map((b) => (typeof b === 'string' ? b : b?.text ?? b?.input_text ?? '')).filter(Boolean).join('\n');
};

export function newState(cli, path) {
  return {
    cli, path, invalid: 0,
    id: null, cwd: null, startedAt: null, parent: false, worktreeOriginal: null,
    customTitle: null, aiTitle: null, firstPrompt: null,
    model: 'unknown', metrics: {}, usageSeen: new Map(), cumulative: null, costState: null,
    status: null, pending: new Map(), questions: new Set(),
    bash: new Map(), editsPending: new Map(),
    failures: [], hookFailures: [], passes: new Map(), edits: [], legacyEdits: [], sawFileChange: false,
  };
}

const metricFor = (st, model) => (st.metrics[model] ??= { input: 0, output: 0, cacheWrite: 0, cacheWriteLong: 0, cacheRead: 0 });
const count = (v) => (Number.isFinite(v) && v >= 0 ? v : 0);
const atOf = (r) => Date.parse(r.timestamp) || 0;

function recordOutcome(st, { id, cmd, at, exit, output }) {
  const command = normalizeCommand(cmd);
  if (!command) return;
  const key = sha(command);
  if (exit === 0) {
    const list = st.passes.get(key) ?? [];
    list.push(at);
    if (list.length > PASSES_PER_COMMAND) list.shift();
    st.passes.set(key, list);
  } else if (Number.isInteger(exit) && !isExploratory(cmd)) {
    st.failures.push({ id, key, cmd: command, at, exit, reason: errorLine(output) || `Exit ${exit}` });
  }
}

function addPrompt(st, text) {
  const plain = text.trim();
  if (isJunkTitle(plain)) return false;
  st.pending.clear();
  st.questions.clear();
  st.firstPrompt ??= cleanTitle(plain);
  return true;
}

function addPending(st, id, name, target, at, track) {
  if (!id) return;
  st.pending.set(id, { name: preview(name), target: preview(target), at, track });
  if (QUESTION_TOOL.test(name ?? '')) st.questions.add(id);
}

function finishPending(st, id, failed) {
  const pending = st.pending.get(id);
  st.pending.delete(id);
  // request_user_input_async answers immediately; the wait ends at the next user message instead.
  if (st.questions.has(id) && (failed || !pending?.name.endsWith('request_user_input_async'))) st.questions.delete(id);
}

// ---- Claude Code transcript ----

function claudeToolResult(st, block, at) {
  const id = block.tool_use_id;
  const failed = block.is_error === true;
  finishPending(st, id, failed);
  const bash = st.bash.get(id);
  if (bash) {
    st.bash.delete(id);
    const output = textOf(block.content);
    const exit = failed ? Number(/^Exit code (\d+)/.exec(output)?.[1] ?? NaN) : 0;
    if (!failed || Number.isInteger(exit)) recordOutcome(st, { id, cmd: bash.cmd, at, exit, output });
  }
  const edit = st.editsPending.get(id);
  if (edit) {
    st.editsPending.delete(id);
    if (!failed) for (const path of edit.paths) st.edits.push({ id: `${id}:${path}`, path, at: edit.at });
  }
}

function claudeHookFailure(st, r, a) {
  const blocking = a.type === 'hook_blocking_error';
  const command = blocking ? a.blockingError?.command : a.command;
  if (typeof command !== 'string' || typeof a.hookEvent !== 'string') return;
  const raw = blocking ? a.blockingError?.blockingError : a.stderr || a.stdout;
  const exit = Number.isInteger(a.exitCode) ? a.exitCode : null;
  st.hookFailures.push({ id: r.uuid ?? `${a.toolUseID}:${a.hookEvent}:${command}`, event: a.hookEvent, command, at: atOf(r), exit, reason: preview(String(raw ?? '').split('\n').find((l) => l.trim()) ?? '') || (exit == null ? 'Hook failed' : `Exit ${exit}`) });
}

function claudeAssistant(st, r) {
  const m = r.message ?? {};
  if (typeof m.model === 'string' && m.model !== '<synthetic>') st.model = m.model;
  const at = atOf(r);
  if (m.usage && !r.isSidechain) {
    // Streaming blocks repeat the message usage, so keep the maximum per message id.
    const u = m.usage;
    const values = { input: count(u.input_tokens), output: count(u.output_tokens), cacheWrite: count(u.cache_creation_input_tokens), cacheRead: count(u.cache_read_input_tokens), cacheWriteLong: count(u.cache_creation?.ephemeral_1h_input_tokens) };
    const key = `${st.model}:${m.id ?? r.uuid}`;
    const prev = st.usageSeen.get(key) ?? {};
    const metric = metricFor(st, st.model);
    for (const [k, v] of Object.entries(values)) metric[k] += Math.max(0, v - (prev[k] ?? 0));
    st.usageSeen.set(key, Object.fromEntries(Object.entries(values).map(([k, v]) => [k, Math.max(v, prev[k] ?? 0)])));
  }
  for (const b of Array.isArray(m.content) ? m.content : []) {
    if (b?.type !== 'tool_use') continue;
    const input = b.input ?? {};
    const isBash = b.name === 'Bash' && typeof input.command === 'string';
    const file = input.file_path ?? input.notebook_path;
    addPending(st, b.id, b.name, input.file_path ?? input.command ?? input.description ?? input.pattern ?? '', at, isBash || EDIT_TOOLS.has(b.name) || QUESTION_TOOL.test(b.name));
    if (isBash) st.bash.set(b.id, { cmd: input.command });
    if (EDIT_TOOLS.has(b.name) && typeof file === 'string') st.editsPending.set(b.id, { paths: [file], at });
  }
}

export function foldClaude(st, line) {
  const resultLine = line.includes('"tool_result"');
  if (resultLine && !line.includes('"type":"assistant"')) {
    // Most result lines are big file reads nobody needs: skip them unless a tracked tool owns them.
    const ids = [...line.matchAll(/"tool_use_id":"([^"]+)"/g)].map((m) => m[1]);
    if (ids.length && !ids.some((id) => st.pending.get(id)?.track)) { for (const id of ids) finishPending(st, id, false); return; }
  }
  const attachment = line.includes('"type":"attachment"');
  const wanted = resultLine || line.includes('"type":"user"') || line.includes('"type":"assistant"')
    || line.includes('"type":"ai-title"') || line.includes('"type":"custom-title"') || line.includes('"type":"worktree-state"')
    || line.includes('"type":"cost-state"') || (attachment && (line.includes('hook_non_blocking_error') || line.includes('hook_blocking_error')));
  if (!wanted) return;
  let r;
  try { r = JSON.parse(line); } catch { st.invalid++; return; }
  if (r.cwd && !st.cwd) st.cwd = r.cwd;
  if (!st.startedAt) st.startedAt = Date.parse(r.timestamp) || null;
  switch (r.type) {
    case 'ai-title': st.aiTitle = r.aiTitle ?? st.aiTitle; return;
    case 'custom-title': st.customTitle = r.customTitle ?? st.customTitle; return;
    case 'worktree-state': st.worktreeOriginal = r.worktreeSession?.originalCwd ?? st.worktreeOriginal; return;
    case 'cost-state': st.costState = r.modelUsage ?? st.costState; return;
    case 'attachment':
      if (r.attachment?.type === 'hook_non_blocking_error' || r.attachment?.type === 'hook_blocking_error') claudeHookFailure(st, r, r.attachment);
      return;
    case 'assistant': claudeAssistant(st, r); return;
    case 'user': {
      const c = r.message?.content;
      const at = atOf(r);
      let text = '';
      for (const b of Array.isArray(c) ? c : [{ type: 'text', text: c }]) {
        if (b?.type === 'tool_result') claudeToolResult(st, b, at);
        else if (b?.type === 'text' && typeof b.text === 'string') text += `${b.text}\n`;
      }
      if (text && !r.isMeta && !r.isCompactSummary && !r.isSidechain) addPrompt(st, text);
      return;
    }
    default:
  }
}

// ---- Codex rollout ----

function codexUsage(st, info, model) {
  const u = info?.total_token_usage;
  if (!u) return;
  const values = { input: count(u.input_tokens), output: count(u.output_tokens), cacheRead: count(u.cached_input_tokens ?? u.cache_read_input_tokens) };
  const prior = st.cumulative ?? { input: 0, output: 0, cacheRead: 0 };
  const delta = Object.fromEntries(Object.entries(values).map(([k, v]) => [k, v >= prior[k] ? v - prior[k] : v]));
  const metric = metricFor(st, model);
  // Codex input includes cached tokens and output includes reasoning tokens.
  metric.input += Math.max(0, delta.input - delta.cacheRead);
  metric.cacheRead += delta.cacheRead;
  metric.output += delta.output;
  st.cumulative = values;
}

function codexItem(st, item, at) {
  if (item.type === 'UserMessage') {
    const text = textOf((item.content ?? []).filter((b) => b?.type === 'text'));
    if (text) { st.questions.clear(); if (!isJunkTitle(text)) st.firstPrompt ??= cleanTitle(text); }
  } else if (item.type === 'CommandExecution') {
    const cmd = Array.isArray(item.command) ? item.command.at(-1) : item.command;
    if (typeof cmd === 'string' && Number.isInteger(item.exit_code)) recordOutcome(st, { id: item.id, cmd, at, exit: item.exit_code, output: item.aggregated_output });
  } else if (item.type === 'FileChange') {
    st.sawFileChange = true;
    if (item.status && !/complete|success/i.test(item.status)) return;
    for (const path of Object.keys(item.changes ?? {})) st.edits.push({ id: `${item.id}:${path}`, path, at });
  }
}

function codexResponse(st, p, at) {
  if (p.type === 'function_call' || p.type === 'custom_tool_call') {
    const raw = p.arguments ?? p.input ?? '';
    let target = '';
    try { const a = JSON.parse(raw); target = Array.isArray(a.command) ? a.command.at(-1) : a.cmd ?? a.command ?? ''; } catch { target = ''; }
    addPending(st, p.call_id, p.name, target, at, QUESTION_TOOL.test(p.name ?? ''));
    // Older rollouts record patches only as tool text; used when no FileChange item exists in the file.
    if (typeof raw === 'string' && raw.includes('*** ')) {
      let n = 0;
      for (const m of raw.matchAll(PATCH_FILE_RE)) st.legacyEdits.push({ id: `${p.call_id}:${n++}`, path: m[1].trim(), at });
    }
  } else if (p.type === 'function_call_output' || p.type === 'custom_tool_call_output') {
    finishPending(st, p.call_id, false);
  }
}

export function foldCodex(st, line) {
  const wanted = line.includes('"type":"session_meta"') || line.includes('"type":"turn_context"')
    || (line.includes('"type":"event_msg"') && /"type":"(task_started|task_complete|turn_aborted|token_count|item_completed|user_message)"/.test(line)
      && (!line.includes('"type":"item_completed"') || /"type":"(UserMessage|CommandExecution|FileChange)"/.test(line)))
    || (line.includes('"type":"response_item"') && /"type":"(function_call|custom_tool_call)/.test(line));
  if (!wanted) return;
  let r;
  try { r = JSON.parse(line); } catch { st.invalid++; return; }
  const p = r.payload ?? {};
  const at = atOf(r);
  if (r.type === 'session_meta') {
    st.id ??= p.id ?? p.session_id ?? null;
    st.cwd ??= p.cwd ?? null;
    st.startedAt ??= Date.parse(p.timestamp) || at || null;
    st.parent = Boolean(p.parent_thread_id || p.source?.subagent);
  } else if (r.type === 'turn_context') {
    if (typeof p.model === 'string') st.model = p.model;
    st.cwd ??= p.cwd ?? null;
  } else if (r.type === 'event_msg') {
    if (p.type === 'task_started') { st.status = 'busy'; st.questions.clear(); }
    else if (p.type === 'task_complete' || p.type === 'turn_aborted') { st.status = 'idle'; st.pending.clear(); st.questions.clear(); }
    else if (p.type === 'item_completed' && p.item) codexItem(st, p.item, at);
    else if (p.type === 'user_message') { st.questions.clear(); if (typeof p.message === 'string' && !isJunkTitle(p.message)) st.firstPrompt ??= cleanTitle(p.message); }
    else if (p.type === 'token_count') codexUsage(st, p.info, st.model);
  } else if (r.type === 'response_item') codexResponse(st, p, at);
}

/** Edits of one file state, preferring FileChange items over the older tool-text patches. */
export function editsOf(st) {
  if (st.cli !== 'codex' || st.sawFileChange) return st.edits;
  const base = st.cwd ?? '';
  return st.legacyEdits.map((e) => ({ ...e, path: e.path.startsWith('/') || !base ? e.path : `${base.replace(/\/$/, '')}/${e.path}` }));
}

export const foldLine = (st, line) => (st.cli === 'claude' ? foldClaude(st, line) : foldCodex(st, line));

/** Hook failures use the inventory hash: sha(event|command). */
export const hookHash = (event, command) => sha(`${event}|${command}`);
