// Activity tests. Every log, status file and lock is generated inside a temporary HOME; the real
// ~/.claude and ~/.codex are never read, and ps/lsof/kill are replaced by an injected adapter. The one exception
// is a Stop test that signals a child process this file spawned itself.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, before, test } from 'node:test';
import { zstdCompressSync } from 'node:zlib';
import { ENDED_KEEP_MS, TOOL_QUIET_MS, UNMEASURABLE, estimateCost, readActivity, stopSession } from './activity.mjs';
import { shortestLabels } from './activity-groups.mjs';
import { sha, roots } from './inventory.mjs';
import { foldCodex, newState } from './activity-fold.mjs';
import { parseCodexPids, parseLockFds, systemProc } from './process-adapter.mjs';
import { isJunkTitle, pickTitle, projectName } from './session-titles.mjs';

const tmp = mkdtempSync(join(tmpdir(), 'reins-activity-'));
const saved = {};
const ENV_KEYS = ['HOME', 'CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'REINS_HOME'];
let counter = 0;

before(() => { for (const k of ENV_KEYS) saved[k] = process.env[k]; });
after(() => {
  for (const k of ENV_KEYS) { if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k]; }
  rmSync(tmp, { recursive: true, force: true });
});

/** A fresh HOME with all four config variables pointing inside it. */
function sandbox() {
  const home = join(tmp, `home-${++counter}`);
  const env = { HOME: home, CLAUDE_CONFIG_DIR: join(home, '.claude'), CODEX_HOME: join(home, '.codex'), REINS_HOME: join(home, '.reins') };
  Object.assign(process.env, env);
  mkdirSync(home, { recursive: true });
  return { home, r: roots(env) };
}

const now = Date.parse('2026-11-02T12:00:00Z');
const iso = (ms) => new Date(ms).toISOString();
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const sid = (n) => `${String(n).padStart(8, 'a')}-0000-4000-8000-000000000000`;
const jsonl = (records) => `${records.map((x) => JSON.stringify(x)).join('\n')}\n`;
function put(path, text, ageMs = 0) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
  const t = (now - ageMs) / 1000;
  utimesSync(path, t, t);
}
const fakeProc = ({ alive = [], starts = {}, threads = [] } = {}) => ({
  alive: (pid) => alive.includes(pid),
  startOf: (pid) => starts[pid] ?? null,
  codexThreads: async () => threads,
});
const run = (r, proc = fakeProc(), extra = {}) => readActivity(r, { now, proc, cache: new Map(), ...extra });

// ---- Claude fixtures ----
const claudeLog = (r, cwd, session, records, ageMs = 0) => {
  const project = '-' + cwd.replace(/[/.]/g, '-');
  put(join(r.claude.logs, project, `${session}.jsonl`), jsonl(records), ageMs);
};
const status = (r, pid, over) => {
  put(join(r.claude.root, 'sessions', `${pid}.json`), JSON.stringify({ pid, sessionId: sid(pid), cwd: '/work/app', startedAt: now - 3_600_000, procStart: 'Mon Nov  2 11:00:00 2026', status: 'idle', name: 'app-1', nameSource: 'derived', statusUpdatedAt: now - 3_000_000, ...over }));
};
const cl = (cwd, session) => ({
  user: (text, at) => ({ type: 'user', timestamp: iso(at), cwd, sessionId: session, message: { role: 'user', content: text } }),
  tool: (id, name, input, at, extra = {}) => ({ type: 'assistant', timestamp: iso(at), cwd, sessionId: session, message: { id: `msg-${id}`, model: extra.model ?? 'claude-sonnet-4-6', content: [{ type: 'tool_use', id, name, input }], usage: extra.usage } }),
  result: (id, text, isError, at) => ({ type: 'user', timestamp: iso(at), cwd, sessionId: session, message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: id, is_error: isError, content: text }] } }),
  hookFail: (n, event, command, at) => ({ type: 'attachment', uuid: uuid(n), timestamp: iso(at), cwd, sessionId: session, attachment: { type: 'hook_non_blocking_error', hookEvent: event, hookName: event, command, exitCode: 1, stderr: 'check failed\nsecond line', toolUseID: `tu-${n}` } }),
});

// ---- Codex fixtures ----
const codexLog = (r, id, records, ageMs = 0) => {
  put(join(r.codex.logs, '2026', '11', '02', `rollout-2026-11-02T01-00-00-${id}.jsonl`), jsonl(records), ageMs);
};
const cx = (id) => {
  const rec = (at, type, payload) => ({ timestamp: iso(at), type, payload });
  return {
    meta: (at, cwd, extra = {}) => rec(at, 'session_meta', { id, cwd, timestamp: iso(at), source: 'cli', ...extra }),
    model: (at, model) => rec(at, 'turn_context', { model }),
    started: (at) => rec(at, 'event_msg', { type: 'task_started', turn_id: 't' }),
    done: (at) => rec(at, 'event_msg', { type: 'task_complete', turn_id: 't' }),
    aborted: (at) => rec(at, 'event_msg', { type: 'turn_aborted', turn_id: 't' }),
    say: (at, text) => rec(at, 'event_msg', { type: 'item_completed', item: { type: 'UserMessage', id: `u${at}`, content: [{ type: 'text', text }] } }),
    call: (at, callId, name, args) => rec(at, 'response_item', { type: name.startsWith('custom') ? 'custom_tool_call' : 'function_call', call_id: callId, name, arguments: JSON.stringify(args) }),
    output: (at, callId) => rec(at, 'response_item', { type: 'function_call_output', call_id: callId, output: 'ok' }),
    exec: (at, n, command, exit, output = '') => rec(at, 'event_msg', { type: 'item_completed', item: { type: 'CommandExecution', id: `ce${n}`, command: ['/bin/zsh', '-lc', command], cwd: '/work', exit_code: exit, aggregated_output: output } }),
    patch: (at, n, paths, status = 'completed') => rec(at, 'event_msg', { type: 'item_completed', item: { type: 'FileChange', id: `fc${n}`, status, changes: Object.fromEntries(paths.map((p) => [p, { type: 'update', unified_diff: '' }])) } }),
    tokens: (at, input, cached, output) => rec(at, 'event_msg', { type: 'token_count', info: { total_token_usage: { input_tokens: input, cached_input_tokens: cached, output_tokens: output } } }),
  };
};

const byId = (a, id) => a.sessions.find((s) => s.id === id);

// ---- Claude states ----

test('Claude: each state comes from the status file and the transcript tail', async () => {
  const { r } = sandbox();
  const cwd = '/work/app';
  const open = (n, extra = {}) => {
    const c = cl(cwd, sid(n));
    return [c.user('Build the thing', now - 60_000), c.tool(`b${n}`, 'Bash', { command: 'sleep 1' }, now - 50_000, extra)];
  };
  // running: busy with an open tool, written just now
  status(r, 1, { status: 'busy' }); claudeLog(r, cwd, sid(1), open(1), 1_000);
  // unmeasurable: busy, open tool, silent for longer than the threshold
  status(r, 2, { status: 'busy' }); claudeLog(r, cwd, sid(2), open(2), TOOL_QUIET_MS + 60_000);
  // waiting: an open AskUserQuestion
  const q = cl(cwd, sid(3));
  status(r, 3, { status: 'busy' }); claudeLog(r, cwd, sid(3), [q.user('Plan it', now - 9000), q.tool('q3', 'AskUserQuestion', { question: 'Which one?' }, now - 8000)], 5_000);
  // idle: tool left open by an interrupted turn does not matter once the status is idle
  status(r, 4, { status: 'idle' }); claudeLog(r, cwd, sid(4), open(4), 400_000);
  // shell
  status(r, 5, { status: 'shell' }); claudeLog(r, cwd, sid(5), open(5), 2_000);
  // ended: process gone, written a minute ago -> listed; gone and old -> dropped
  status(r, 6, { status: 'busy' }); claudeLog(r, cwd, sid(6), open(6), 60_000);
  status(r, 7, { status: 'busy' }); claudeLog(r, cwd, sid(7), open(7), ENDED_KEEP_MS + 60_000);
  // pid reused by another process: the start time differs from the status file
  status(r, 8, { status: 'busy', procStart: 'Mon Nov  2 11:00:00 2026' }); claudeLog(r, cwd, sid(8), open(8), 2_000);
  const a = await run(r, fakeProc({ alive: [1, 2, 3, 4, 5, 8], starts: { 8: 'Tue Nov  3 01:00:00 2026' } }));

  assert.equal(byId(a, sid(1)).state, 'running');
  assert.equal(byId(a, sid(1)).currentTool.name, 'Bash');
  const quiet = byId(a, sid(2));
  assert.equal(quiet.state, 'unmeasurable');
  assert.equal(quiet.reasonCode, 'claude-prompt-vs-busy');
  assert.equal(quiet.stateReason, UNMEASURABLE['claude-prompt-vs-busy']);
  assert.equal(byId(a, sid(3)).state, 'waiting');
  assert.equal(byId(a, sid(4)).state, 'idle');
  assert.equal(byId(a, sid(4)).currentTool, null);
  assert.equal(byId(a, sid(5)).state, 'running');
  assert.equal(byId(a, sid(6)).state, 'ended');
  assert.equal(byId(a, sid(7)), undefined);
  assert.equal(byId(a, sid(8)).state, 'ended');
  // age comes from the transcript's last write, not from the stale statusUpdatedAt
  assert.equal(byId(a, sid(1)).lastWriteAgoMs, 1_000);
  assert.equal(byId(a, sid(1)).ageMs, 3_600_000);
});

test('Claude: a session with no transcript yet is listed from its status file', async () => {
  const { r } = sandbox();
  status(r, 9, { status: 'idle', statusUpdatedAt: now - 5000 });
  const s = byId(await run(r, fakeProc({ alive: [9] })), sid(9));
  assert.equal(s.state, 'idle');
  assert.equal(s.cost, null);
  assert.equal(s.title, `2026-11-02 · ${sid(9).slice(0, 8)}`);
});

// ---- titles and project names ----

test('junk titles fall back to the first meaningful request, then to date and short id', async () => {
  for (const junk of ['', '  ', '/clear', '/model opus', '<command-name>/clear</command-name>', 'Caveat: The messages below were generated by the user', '<local-command-stdout></local-command-stdout>', '[Request interrupted by user]']) {
    assert.equal(isJunkTitle(junk), true, JSON.stringify(junk));
  }
  assert.equal(isJunkTitle('/Users/me/app/file.ts is broken'), false);
  assert.equal(isJunkTitle('Fix the login redirect'), false);
  assert.equal(pickTitle([null, 'Caveat: x'], { startedAt: Date.parse('2026-10-31T10:00:00Z'), id: 'abcdef1234' }), '2026-10-31 · abcdef12');

  const { r } = sandbox();
  const c = cl('/work/app', sid(21));
  status(r, 21, { status: 'idle', name: 'work-app-3', nameSource: 'derived' });
  claudeLog(r, '/work/app', sid(21), [
    { type: 'ai-title', aiTitle: 'Caveat: The messages below were generated by the user while running local commands', sessionId: sid(21) },
    c.user('<command-name>/clear</command-name><command-args></command-args>', now - 9000),
    c.user('Fix the login redirect', now - 8000),
  ]);
  const c2 = cl('/work/app', sid(22));
  status(r, 22, { status: 'idle' });
  claudeLog(r, '/work/app', sid(22), [{ type: 'custom-title', customTitle: 'My renamed session', sessionId: sid(22) }, { type: 'ai-title', aiTitle: 'Generated one', sessionId: sid(22) }, c2.user('hello there', now - 8000)]);
  status(r, 23, { status: 'idle', name: 'work-app-5', nameSource: 'derived', startedAt: Date.parse('2026-10-31T10:00:00Z') });
  claudeLog(r, '/work/app', sid(23), [cl('/work/app', sid(23)).user('/review', now - 8000)]);
  const a = await run(r, fakeProc({ alive: [21, 22, 23] }));
  assert.equal(byId(a, sid(21)).title, 'Fix the login redirect');
  assert.equal(byId(a, sid(22)).title, 'My renamed session');
  assert.equal(byId(a, sid(23)).title, `2026-10-31 · ${sid(23).slice(0, 8)}`);
});

test('a worktree slug is never the project name', async () => {
  const { home, r } = sandbox();
  assert.equal(projectName(join(home, 'proj/.claude/worktrees/lucky-fox')), 'proj');
  assert.equal(projectName(join(home, 'proj/.claude/worktrees/lucky-fox/src')), 'proj');
  assert.equal(projectName(join(home, '.codex/worktrees/a1b2/my-repo')), 'my-repo');
  // a real linked worktree: `.git` is a file that points into the main repo
  mkdirSync(join(home, 'wt-checkout'), { recursive: true });
  writeFileSync(join(home, 'wt-checkout/.git'), `gitdir: ${join(home, 'mainrepo/.git/worktrees/wt1')}\n`);
  assert.equal(projectName(join(home, 'wt-checkout')), 'mainrepo');
  assert.equal(projectName(join(home, 'wt-checkout/sub/dir')), 'mainrepo');
  // a normal checkout keeps its own name
  mkdirSync(join(home, 'plain/.git'), { recursive: true });
  assert.equal(projectName(join(home, 'plain')), 'plain');
  // the original cwd that Claude records beats a path that tells nothing
  assert.equal(projectName('/x/odd-slug', { hint: '/home/me/realrepo' }), 'realrepo');

  const c = cl(join(home, 'proj/.claude/worktrees/lucky-fox'), sid(31));
  status(r, 31, { status: 'idle', cwd: join(home, 'proj/.claude/worktrees/lucky-fox') });
  claudeLog(r, join(home, 'proj/.claude/worktrees/lucky-fox'), sid(31), [c.user('Work', now - 5000)]);
  codexLog(r, uuid(32), [cx(uuid(32)).meta(now - 5000, join(home, '.codex/worktrees/a1b2/my-repo')), cx(uuid(32)).done(now - 4000)]);
  const a = await run(r, fakeProc({ alive: [31], threads: [{ pid: 3200, threadId: uuid(32) }] }));
  assert.equal(byId(a, sid(31)).project, 'proj');
  assert.equal(byId(a, uuid(32)).project, 'my-repo');
});

// ---- Codex ----

test('Codex: process maps to its rollout by thread lock; state from the rollout tail', async () => {
  const { r } = sandbox();
  const mk = (n, records, ageMs) => { codexLog(r, uuid(n), records, ageMs); return { pid: 4000 + n, threadId: uuid(n) }; };
  const c = (n) => cx(uuid(n));
  const threads = [
    mk(41, [c(41).meta(now - 90_000, '/work/a'), c(41).started(now - 80_000), c(41).say(now - 79_000, 'Run the suite'), c(41).call(now - 70_000, 'k1', 'exec_command', { cmd: 'npm test' })], 2_000), // running, tool open, fresh
    mk(42, [c(42).meta(now - 90_000, '/work/b'), c(42).started(now - 80_000), c(42).call(now - 70_000, 'k2', 'exec_command', { cmd: 'npm test' })], TOOL_QUIET_MS + 90_000), // silent tool
    mk(43, [c(43).meta(now - 90_000, '/work/c'), c(43).started(now - 80_000), c(43).say(now - 79_000, 'Hi'), c(43).done(now - 70_000)], 70_000), // idle
    mk(44, [c(44).meta(now - 90_000, '/work/d'), c(44).started(now - 80_000), c(44).call(now - 70_000, 'k4', 'exec_command', { cmd: 'x' }), c(44).aborted(now - 60_000)], 60_000), // aborted -> idle, open tool dropped
    mk(45, [c(45).meta(now - 90_000, '/work/e'), c(45).started(now - 80_000), c(45).call(now - 79_000, 'k5', 'request_user_input', { q: 'which?' })], 5_000), // waiting
    mk(46, [c(46).meta(now - 90_000, '/work/f', { parent_thread_id: uuid(41), source: { subagent: { thread_spawn: { parent_thread_id: uuid(41) } } } }), c(46).started(now - 80_000)], 1_000), // child thread: not a session
    { pid: 4047, threadId: uuid(47) }, // lock held, rollout file does not exist yet
    { pid: 4048, threadId: null }, // live process with no lock at all
  ];
  const a = await run(r, fakeProc({ threads, starts: { 4047: 'Mon Nov  2 11:00:00 2026' } }));
  const state = (n) => byId(a, uuid(n)).state;
  assert.equal(state(41), 'running');
  assert.equal(byId(a, uuid(41)).currentTool.name, 'exec_command');
  assert.equal(byId(a, uuid(41)).title, 'Run the suite');
  assert.equal(state(42), 'unmeasurable');
  assert.equal(byId(a, uuid(42)).reasonCode, 'codex-tool-silent');
  assert.equal(byId(a, uuid(42)).stateReason, UNMEASURABLE['codex-tool-silent']);
  assert.equal(state(43), 'idle');
  assert.equal(state(44), 'idle');
  assert.equal(byId(a, uuid(44)).currentTool, null);
  assert.equal(state(45), 'waiting');
  assert.equal(byId(a, uuid(46)), undefined);
  assert.equal(state(47), 'unmeasurable');
  assert.equal(byId(a, uuid(47)).reasonCode, 'codex-no-rollout');
  assert.equal(byId(a, uuid(47)).ageMs, 3_600_000); // from the process start: no rollout exists yet
  assert.equal(byId(a, uuid(47)).title, `2026-11-02 · ${uuid(47).slice(0, 8)}`);
  const bare = a.sessions.find((s) => s.id === 'pid:4048');
  assert.equal(bare.reasonCode, 'codex-no-rollout');
  assert.equal(byId(a, uuid(41)).lastWriteAgoMs, 2_000);
  assert.equal(byId(a, uuid(41)).ageMs, 90_000);
});

test('Codex: thread name from the session index, junk names fall back to the first request', async () => {
  const { r } = sandbox();
  put(join(r.codex.root, 'session_index.jsonl'), jsonl([{ id: uuid(51), thread_name: 'Greet user' }, { id: uuid(52), thread_name: '/review' }]));
  for (const n of [51, 52]) codexLog(r, uuid(n), [cx(uuid(n)).meta(now - 9000, '/work/x'), cx(uuid(n)).started(now - 8000), cx(uuid(n)).say(now - 7000, 'Explain the build'), cx(uuid(n)).done(now - 6000)]);
  const a = await run(r, fakeProc({ threads: [{ pid: 1, threadId: uuid(51) }, { pid: 2, threadId: uuid(52) }] }));
  assert.equal(byId(a, uuid(51)).title, 'Greet user');
  assert.equal(byId(a, uuid(52)).title, 'Explain the build');
});

// ---- cost ----

test('cost: estimated from logged tokens, deduplicated, and null when the model has no price', async () => {
  const { r } = sandbox();
  const c = cl('/work/app', sid(61));
  const usage = { input_tokens: 1000, output_tokens: 2000, cache_creation_input_tokens: 4000, cache_read_input_tokens: 10_000 };
  status(r, 61, { status: 'idle' });
  claudeLog(r, '/work/app', sid(61), [
    c.user('go', now - 9000),
    c.tool('a', 'Read', { file_path: '/x' }, now - 8000, { usage }),
    { ...c.tool('a2', 'Read', { file_path: '/y' }, now - 7900, { usage }), message: { ...c.tool('a2', 'Read', { file_path: '/y' }, 0, { usage }).message, id: 'msg-a' } }, // same message id: streamed block
    c.tool('b', 'Read', { file_path: '/z' }, now - 7000, { usage: { input_tokens: 500, output_tokens: 100 } }),
  ]);
  status(r, 62, { status: 'idle' });
  claudeLog(r, '/work/app', sid(62), [cl('/work/app', sid(62)).tool('a', 'Read', { file_path: '/x' }, now - 8000, { model: 'claude-mystery-9', usage })]);
  const t = (n) => cx(uuid(n));
  codexLog(r, uuid(63), [t(63).meta(now - 9000, '/work/x'), t(63).model(now - 8900, 'gpt-6.1-sol'), t(63).started(now - 8000),
    t(63).tokens(now - 7000, 10_000, 4000, 500), t(63).tokens(now - 6000, 12_000, 5000, 800), t(63).done(now - 5000)]);
  const a = await run(r, fakeProc({ alive: [61, 62], threads: [{ pid: 63, threadId: uuid(63) }] }));
  const claude = byId(a, sid(61));
  assert.equal(claude.cost.estimated, true);
  // (1000*3 + 2000*15 + 4000*3.75 + 10000*0.3 + 500*3 + 100*15) per million at claude-sonnet-4-6 prices
  assert.ok(Math.abs(claude.cost.usd - 0.054) < 1e-9, String(claude.cost.usd));
  assert.equal(byId(a, sid(62)).cost, null);
  assert.match(byId(a, sid(62)).costNote, /No price for model "claude-mystery-9"/);
  // gpt-6.1-sol: uncached input 7000*2 + cached 5000*0.1 + output 800*10 per million
  assert.ok(Math.abs(byId(a, uuid(63)).cost.usd - 0.0225) < 1e-9);
  assert.equal(byId(a, uuid(63)).cost.estimated, true);
  assert.equal(estimateCost({ 'claude-sonnet-4-6[1m]': { input: 1_000_000 } }, { 'claude-sonnet-4-6': { input: 3, output: 0, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0 } }).usd, 3);
});

test('cost: a log too large to read in full gives no estimate rather than a partial sum', async () => {
  const { r } = sandbox();
  const c = cl('/work/app', sid(71));
  status(r, 71, { status: 'idle' });
  const filler = Array.from({ length: 40 }, (_, i) => c.tool(`f${i}`, 'Read', { file_path: `/f/${i}` }, now - 100_000 + i, { usage: { input_tokens: 5, output_tokens: 5 } }));
  claudeLog(r, '/work/app', sid(71), filler);
  const s = byId(await run(r, fakeProc({ alive: [71] }), { liveTailBytes: 1500 }), sid(71));
  assert.equal(s.cost, null);
  assert.match(s.costNote, /too large/);
});

test('cost: subagent transcripts count toward the session cost', async () => {
  const { r } = sandbox();
  const c = cl('/work/app', sid(72));
  status(r, 72, { status: 'idle' });
  claudeLog(r, '/work/app', sid(72), [c.user('go', now - 9000), c.tool('m1', 'Read', { file_path: '/x' }, now - 8000, { usage: { input_tokens: 1_000_000 } })]);
  const sub = { ...c.tool('s1', 'Read', { file_path: '/y' }, now - 7000, { usage: { output_tokens: 1_000_000 } }), isSidechain: true };
  put(join(r.claude.logs, '--work-app', sid(72), 'subagents', 'agent-1.jsonl'), jsonl([sub]), 7000);
  const s = byId(await run(r, fakeProc({ alive: [72] })), sid(72));
  assert.ok(Math.abs(s.cost.usd - (3 + 15)) < 1e-9, String(s.cost?.usd)); // 1M input + 1M output at sonnet-4-6 prices
});

test('many subagent transcripts: the newest write decides liveness, not readdir order', async () => {
  const { r } = sandbox();
  const c = cl('/work/app', sid(73));
  status(r, 73, { status: 'busy' });
  claudeLog(r, '/work/app', sid(73), [c.user('go', now - 900_000), c.tool('t1', 'Agent', { description: 'delegate' }, now - 800_000)], 800_000);
  const dir = join(r.claude.logs, '--work-app', sid(73), 'subagents');
  for (let i = 0; i < 60; i++) put(join(dir, `agent-${String(i).padStart(2, '0')}.jsonl`), jsonl([{ type: 'user', isSidechain: true, message: { role: 'user', content: 'x' } }]), i === 59 ? 2_000 : 600_000);
  const s = byId(await run(r, fakeProc({ alive: [73] })), sid(73));
  assert.equal(s.lastWriteAgoMs, 2_000);
  assert.equal(s.state, 'running'); // an open tool, but a subagent wrote 2 s ago
});

// ---- failures ----

test('failed commands group by command with a count, one title form, and a neutral laterPass', async () => {
  const { home, r } = sandbox();
  const marker = join(home, 'must-not-exist');
  const A = cl('/work/app-a', sid(81));
  const B = cl('/work/app-b', sid(82));
  const t = (min) => now - min * 60_000;
  claudeLog(r, '/work/app-a', sid(81), [
    A.user('run it', t(60)),
    A.tool('a1', 'Bash', { command: 'npm test' }, t(50)), A.result('a1', 'Exit code 1\nTAP\nError: boom in suite', true, t(49)),
    A.tool('a2', 'Bash', { command: 'cd /work/app-a && npm  test' }, t(40)), A.result('a2', 'Exit code 1\nError: boom in suite', true, t(39)),
    A.tool('a3', 'Bash', { command: 'npm test' }, t(10)), A.result('a3', 'all green', false, t(9)),
    A.tool('a4', 'Bash', { command: 'make deploy' }, t(70)), A.result('a4', 'done', false, t(69)),
    A.tool('a5', 'Bash', { command: 'make deploy' }, t(30)), A.result('a5', 'Exit code 2\nmake: *** Error 2', true, t(29)),
    A.tool('a6', 'Bash', { command: 'grep nothing file.txt' }, t(20)), A.result('a6', 'Exit code 1', true, t(19)),
    A.tool('a7', 'Bash', { command: 'rm -rf build' }, t(18)), A.result('a7', "The user doesn't want to proceed with this tool use.", true, t(17)),
    A.tool('a8', 'Bash', { command: `touch ${marker} && false` }, t(15)), A.result('a8', 'Exit code 1', true, t(14)),
    A.hookFail(1, 'Stop', 'sh /h/check.sh', t(45)), A.hookFail(2, 'Stop', 'sh /h/check.sh', t(25)),
  ]);
  claudeLog(r, '/work/app-b', sid(82), [
    B.user('again', t(55)),
    B.tool('b1', 'Bash', { command: 'npm test' }, t(5)), B.result('b1', 'Exit code 1\nError: boom in suite', true, t(4)),
  ]);
  const x = cx(uuid(83));
  codexLog(r, uuid(83), [x.meta(t(60), '/work/app-a'), x.exec(t(35), 1, 'npm test', 1, 'running\nerror: codex side')]);
  const a = await run(r);

  const npmClaude = a.failures.find((f) => f.cli === 'claude' && f.title === 'npm test');
  assert.equal(npmClaude.count, 3);
  assert.equal(npmClaude.sessions, 2);
  assert.deepEqual(npmClaude.projects, ['app-a', 'app-b']);
  assert.equal(npmClaude.exit, 1);
  assert.equal(npmClaude.first, iso(t(49)));
  assert.equal(npmClaude.last, iso(t(4)));
  // the pass at t(9) is before the last failure at t(4): no later pass
  assert.equal(npmClaude.laterPass, null);
  const deploy = a.failures.find((f) => f.title === 'make deploy');
  assert.equal(deploy.count, 1);
  assert.equal(deploy.reason, 'make: *** Error 2');
  assert.equal(deploy.laterPass, null); // the pass at t(69) came before the failure
  const codexRow = a.failures.find((f) => f.cli === 'codex');
  assert.equal(codexRow.title, 'npm test');
  assert.equal(codexRow.count, 1);
  assert.equal(codexRow.reason, 'error: codex side');
  assert.equal(codexRow.laterPass, null);
  assert.equal(a.failures.some((f) => f.title.startsWith('grep')), false, 'exploratory commands are not failures');
  assert.equal(a.failures.some((f) => f.title.startsWith('rm -rf')), false, 'a rejected tool call is not a failed command');
  const hook = a.failures.find((f) => f.kind === 'hook');
  assert.equal(hook.count, 2);
  assert.equal(hook.title, 'sh /h/check.sh');
  assert.deepEqual(hook.hook, { hash: sha('Stop|sh /h/check.sh'), event: 'Stop' });
  assert.equal(hook.reason, 'check failed');
  // the recorded command was parsed, never run
  assert.equal(a.failures.some((f) => f.title.includes('touch')), true);
  assert.equal(existsSync(marker), false);
  assert.ok(!('fixed' in npmClaude) && !Object.keys(npmClaude).some((k) => /fix|resolved/i.test(k)));
});

test('laterPass is the first passing run after the last failure of the same command', async () => {
  const { r } = sandbox();
  const A = cl('/work/app-a', sid(91));
  const t = (min) => now - min * 60_000;
  claudeLog(r, '/work/app-a', sid(91), [
    A.user('go', t(60)),
    A.tool('a1', 'Bash', { command: 'pnpm lint' }, t(50)), A.result('a1', 'Exit code 1\nerror: bad', true, t(49)),
    A.tool('a2', 'Bash', { command: 'pnpm lint' }, t(30)), A.result('a2', 'clean', false, t(29)),
    A.tool('a3', 'Bash', { command: 'pnpm lint' }, t(20)), A.result('a3', 'clean', false, t(19)),
  ]);
  const row = (await run(r)).failures.find((f) => f.title === 'pnpm lint');
  assert.equal(row.laterPass, iso(t(29)));
});

// ---- files ----

test('file history: edits across sessions and CLIs, with labels that keep two rank.ts apart', async () => {
  const { r } = sandbox();
  const A = cl('/work/app-a', sid(101));
  const B = cl('/work/app-b', sid(102));
  const t = (min) => now - min * 60_000;
  claudeLog(r, '/work/app-a', sid(101), [
    A.user('edit', t(60)),
    A.tool('e1', 'Edit', { file_path: '/work/app-a/src/rank.ts' }, t(50)), A.result('e1', 'ok', false, t(49)),
    A.tool('e2', 'Edit', { file_path: '/work/app-a/src/rank.ts' }, t(40)), A.result('e2', 'ok', false, t(39)),
    A.tool('e3', 'Write', { file_path: '/work/app-a/README.md' }, t(30)), A.result('e3', 'ok', false, t(29)),
    A.tool('e4', 'Edit', { file_path: '/work/app-a/nope.ts' }, t(20)), A.result('e4', 'String not found', true, t(19)),
  ]);
  claudeLog(r, '/work/app-b', sid(102), [B.user('edit', t(60)), B.tool('e5', 'Edit', { file_path: '/work/app-b/src/rank.ts' }, t(10)), B.result('e5', 'ok', false, t(9))]);
  const x = cx(uuid(103));
  codexLog(r, uuid(103), [x.meta(t(60), '/work/app-a'), x.patch(t(5), 1, ['/work/app-a/src/rank.ts']), x.patch(t(4), 2, ['/work/app-a/failed.ts'], 'failed')]);
  const a = await run(r);

  const rankA = a.files.find((f) => f.path === '/work/app-a/src/rank.ts');
  assert.equal(rankA.edits, 3);
  assert.equal(rankA.sessions, 2);
  assert.deepEqual(rankA.clis, ['claude', 'codex']);
  assert.equal(rankA.last, iso(t(5)));
  assert.equal(rankA.label, 'app-a/src/rank.ts');
  assert.equal(a.files.find((f) => f.path === '/work/app-b/src/rank.ts').label, 'app-b/src/rank.ts');
  assert.equal(a.files.find((f) => f.path === '/work/app-a/README.md').label, 'README.md');
  assert.equal(a.files.some((f) => /nope|failed/.test(f.path)), false, 'failed edits are not history');
  assert.equal(new Set(a.files.map((f) => f.label)).size, a.files.length);
});

test('older Codex rollouts that record patches only as tool text still give file history', async () => {
  const { r } = sandbox();
  const x = cx(uuid(111));
  const patch = '*** Begin Patch\n*** Update File: src/old.ts\n@@\n*** Add File: /abs/new.ts\n*** End Patch';
  codexLog(r, uuid(111), [x.meta(now - 9000, '/work/app-a'), { timestamp: iso(now - 8000), type: 'response_item', payload: { type: 'custom_tool_call', name: 'exec', call_id: 'p1', input: patch } }]);
  const files = (await run(r)).files;
  assert.deepEqual(files.map((f) => f.path).sort(), ['/abs/new.ts', '/work/app-a/src/old.ts']);
});

test('shortestLabels: shortest unique suffix, a path that is a suffix of another keeps its whole path', () => {
  assert.deepEqual(shortestLabels(['/a/x/rank.ts', '/b/x/rank.ts', '/a/y/other.ts']), ['a/x/rank.ts', 'b/x/rank.ts', 'other.ts']);
  assert.deepEqual(shortestLabels(['/p/q/c.ts', 'q/c.ts']), ['p/q/c.ts', 'q/c.ts']);
  assert.deepEqual(shortestLabels(['/only/one.ts']), ['one.ts']);
});

// ---- limits, incremental reads, adapter parsers ----

test('unmeasurable limits are listed even when nothing is running', async () => {
  const { r } = sandbox();
  const a = await run(r);
  assert.deepEqual(a.sessions, []);
  assert.deepEqual(new Set(a.unmeasurable.map((l) => l.code)), new Set(['claude-prompt-vs-busy', 'codex-tool-silent', 'codex-no-rollout', 'codex-hook-runs']));
  assert.ok(a.unmeasurable.every((l) => l.text === UNMEASURABLE[l.code] && ['claude', 'codex'].includes(l.cli)));
});

test('a second call with the same cache reads only appended bytes and sees the new state', async () => {
  const { r } = sandbox();
  const c = cl('/work/app', sid(121));
  status(r, 121, { status: 'busy' });
  const first = [c.user('start', now - 9000), c.tool('i1', 'Bash', { command: 'make' }, now - 8000)];
  claudeLog(r, '/work/app', sid(121), first, 1000);
  const cache = new Map();
  const proc = fakeProc({ alive: [121] });
  const a1 = await readActivity(r, { now, proc, cache });
  assert.equal(byId(a1, sid(121)).currentTool.name, 'Bash');
  const path = [...cache.keys()][0];
  const before = cache.get(path).reader.offset;
  put(path, jsonl([...first, c.result('i1', 'Exit code 1\nError: nope', true, now - 500)]), 0);
  const a2 = await readActivity(r, { now, proc, cache });
  assert.equal(byId(a2, sid(121)).currentTool, null);
  assert.ok(cache.get(path).reader.offset > before);
  assert.equal(a2.failures[0].title, 'make');
  assert.equal(statSync(path).size, cache.get(path).reader.offset);
});

test('process adapter parsers read ps and lsof output', () => {
  const ps = [
    '  100 /Users/me/.local/bin/codex --no-daemon -c tui.animations=false',
    '  101 /Applications/Codex.app/codex app-server --listen stdio',
    '  102 /usr/bin/node /x/not-codex.js',
    '  103 codex',
  ].join('\n');
  assert.deepEqual(parseCodexPids(ps), [100, 103]);
  const lsof = ['p100', 'n/Users/me/.codex/.sqlite-maintenance.lock', `n/Users/me/.codex/thread-writer-locks/${uuid(1)}.lock`, 'p103', 'n/etc/hosts'].join('\n');
  assert.deepEqual(parseLockFds(lsof), [{ pid: 100, threadId: uuid(1) }]);
});

// ---- compressed rollouts ----

test('a compressed rollout gives failures and file history like a plain one, and is read only once', async () => {
  const { r } = sandbox();
  const id = sid(40);
  const c = cx(id);
  const text = jsonl([c.meta(now - 90_000, '/work/app'), c.exec(now - 80_000, 1, 'npm run build', 1, 'error: boom'), c.patch(now - 70_000, 2, ['/work/app/a.ts'])]);
  const path = join(r.codex.logs, '2026', '10', '20', `rollout-2026-10-20T01-00-00-${id}.jsonl.zst`);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, zstdCompressSync(Buffer.from(text)));
  utimesSync(path, (now - 60_000) / 1000, (now - 60_000) / 1000);
  const cache = new Map();
  const a = await run(r, fakeProc(), { cache });
  assert.deepEqual(a.failures.map((f) => [f.cli, f.title]), [['codex', 'npm run build']]);
  assert.deepEqual(a.files.map((f) => f.path), ['/work/app/a.ts']);
  const b = await run(r, fakeProc(), { cache });
  assert.equal(b.failures[0].count, 1, 'a second read must not fold the same lines again');
});

test('a compressed rollout larger than the limit keeps only its tail and says it was cut', async () => {
  const { r } = sandbox();
  const id = sid(41);
  const c = cx(id);
  const text = jsonl([c.tokens(now - 90_000, 1000, 0, 100), c.exec(now - 80_000, 1, 'first-cmd', 1, 'error: a'), c.exec(now - 70_000, 2, 'last-cmd', 1, 'error: b')]);
  const path = join(r.codex.logs, '2026', '10', '20', `rollout-2026-10-20T01-00-00-${id}.jsonl.zst`);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, zstdCompressSync(Buffer.from(text)));
  utimesSync(path, (now - 60_000) / 1000, (now - 60_000) / 1000);
  const a = await run(r, fakeProc(), { historyTailBytes: 300 });
  assert.deepEqual(a.failures.map((f) => f.title), ['last-cmd']);
  assert.equal(a.stats.truncated, 1);
});

// ---- Codex token totals ----

test('Codex tokens: interleaved streams, repeated totals and an inherited first total do not inflate the count', () => {
  const event = (total, last) => JSON.stringify({ timestamp: iso(now), type: 'event_msg', payload: { type: 'token_count', info: { total_token_usage: total, ...(last ? { last_token_usage: last } : {}) } } });
  const usage = (input, output) => ({ input_tokens: input, cached_input_tokens: 0, output_tokens: output });
  const metrics = (lines) => {
    const st = newState('codex', '/x');
    for (const line of lines) foldCodex(st, line);
    return st.metrics.unknown;
  };
  // A parent at 1000, an embedded reviewer's own total at 50, the parent again at 1100, and a repeat of that total.
  const m = metrics([event(usage(1000, 100), usage(1000, 100)), event(usage(50, 5), usage(50, 5)), event(usage(1100, 110), usage(100, 10)), event(usage(1100, 110), usage(100, 10))]);
  assert.deepEqual([m.input, m.output], [1150, 115]);
  // A forked rollout starts from the parent's total: only the turn's own usage belongs to it.
  const fork = metrics([event(usage(90_000, 9000), usage(200, 20))]);
  assert.deepEqual([fork.input, fork.output], [200, 20]);
  // Rollouts with no per-turn usage still work from the difference, and a lower total is a restart.
  const old = metrics([event(usage(1000, 100)), event(usage(1500, 150)), event(usage(40, 4))]);
  assert.deepEqual([old.input, old.output], [1540, 154]);
});

// ---- Stop ----

const stopProc = (over = {}) => {
  const killed = [];
  const alive = new Set(over.alive ?? []);
  return {
    killed,
    alive: (pid) => alive.has(pid),
    startOf: (pid) => over.starts?.[pid] ?? null,
    codexThreads: async () => over.threads ?? [],
    terminate(pid) {
      if (over.terminateError) throw Object.assign(new Error('no'), { code: over.terminateError });
      killed.push(pid);
      if (!over.ignoresSignal) alive.delete(pid);
    },
  };
};
const START = 'Mon Nov  2 11:00:00 2026';
const fast = { waitMs: 30, pollMs: 5 };

test('Stop signals the Claude process that the status file names, and reports that it exited', async () => {
  const { r } = sandbox();
  status(r, 11, { procStart: START });
  const proc = stopProc({ alive: [11], starts: { 11: 'Mon Nov  2  11:00:00  2026' } });
  assert.deepEqual(await stopSession(r, { cli: 'claude', id: sid(11) }, { proc, ...fast }), { exited: true });
  assert.deepEqual(proc.killed, [11]);
});

test('Stop refuses a reused pid, a dead process and an unknown session, and signals nothing', async () => {
  const { r } = sandbox();
  status(r, 12, { procStart: START });
  status(r, 13, { procStart: START });
  const reused = stopProc({ alive: [12], starts: { 12: 'Tue Nov  3 01:00:00 2026' } });
  await assert.rejects(stopSession(r, { cli: 'claude', id: sid(12) }, { proc: reused, ...fast }), { status: 404 });
  const unknownStart = stopProc({ alive: [12] });
  await assert.rejects(stopSession(r, { cli: 'claude', id: sid(12) }, { proc: unknownStart, ...fast }), { status: 404 });
  const dead = stopProc({ starts: { 13: START } });
  await assert.rejects(stopSession(r, { cli: 'claude', id: sid(13) }, { proc: dead, ...fast }), { status: 404 });
  const none = stopProc();
  await assert.rejects(stopSession(r, { cli: 'codex', id: sid(99) }, { proc: none, ...fast }), { status: 404 });
  assert.deepEqual([...reused.killed, ...unknownStart.killed, ...dead.killed, ...none.killed], []);
});

test('Stop finds a Codex process by its thread lock, or by pid before the first prompt', async () => {
  const { r } = sandbox();
  const threads = [{ pid: 21, threadId: sid(21) }, { pid: 22, threadId: null }];
  const byThread = stopProc({ alive: [21, 22], threads });
  assert.deepEqual(await stopSession(r, { cli: 'codex', id: sid(21) }, { proc: byThread, ...fast }), { exited: true });
  assert.deepEqual(byThread.killed, [21]);
  const byPid = stopProc({ alive: [21, 22], threads });
  assert.deepEqual(await stopSession(r, { cli: 'codex', id: 'pid:22' }, { proc: byPid, ...fast }), { exited: true });
  assert.deepEqual(byPid.killed, [22]);
  // A pid that holds a thread is not reachable through the bare-pid form.
  const held = stopProc({ alive: [21], threads });
  await assert.rejects(stopSession(r, { cli: 'codex', id: 'pid:21' }, { proc: held, ...fast }), { status: 404 });
});

test('Stop says when the process ignored the signal, and turns a permission error into a plain message', async () => {
  const { r } = sandbox();
  status(r, 14, { procStart: START });
  const stubborn = stopProc({ alive: [14], starts: { 14: START }, ignoresSignal: true });
  assert.deepEqual(await stopSession(r, { cli: 'claude', id: sid(14) }, { proc: stubborn, ...fast }), { exited: false });
  const denied = stopProc({ alive: [14], starts: { 14: START }, terminateError: 'EPERM' });
  await assert.rejects(stopSession(r, { cli: 'claude', id: sid(14) }, { proc: denied, ...fast }), { status: 403 });
  const gone = stopProc({ alive: [14], starts: { 14: START }, terminateError: 'ESRCH' });
  assert.deepEqual(await stopSession(r, { cli: 'claude', id: sid(14) }, { proc: gone, ...fast }), { exited: true });
});

test('Stop through the real adapter ends the process the status file names, matched by its real start time', async () => {
  const { r } = sandbox();
  const child = spawn('sleep', ['30'], { stdio: 'ignore' });
  const gone = new Promise((resolve) => { child.once('exit', (_code, signal) => resolve(signal)); });
  try {
    const proc = systemProc();
    status(r, child.pid, { sessionId: sid(50), procStart: await proc.startOf(child.pid) });
    assert.deepEqual(await stopSession(r, { cli: 'claude', id: sid(50) }, { proc }), { exited: true });
    assert.equal(await gone, 'SIGTERM');
  } finally {
    child.kill('SIGKILL');
  }
});
