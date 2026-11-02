// Golden section "activity": what readActivity() of core/activity.mjs returns, for the Swift core to match.
//
//   node scripts/make-golden.mjs activity
//
// Two cases, both with a fixed "now" and a fake process list (no ps, lsof or kill):
//   shared  the shared fixture HOME (Fixtures/home) with the process list the fixture itself describes
//           (home/.reins/activity-proc.json), which covers a running, a waiting and an idle Claude session, a running
//           Codex session, one with a silent tool call, one with no rollout yet, grouped failures with a later pass,
//           and two files that share a name.
//   extra   a second, section-specific HOME written by this script to Fixtures/activity-home (so scripts/fixture-home.mjs
//           and the shared tree stay untouched). It adds what the shared tree lacks: ended and reused-pid sessions, an
//           unknown status, junk and renamed titles, worktrees, priced and unpriced models, subagent transcripts, hook
//           failures, a recorded `touch` command that must never run, child and compressed Codex rollouts, and legacy
//           patch text.
//
// Outputs (synthetic only, AGENTS.md R2):
//   Fixtures/golden/activity.json        { now, shared, extra }: each is the Node report with its lists sorted by a stable key
//   Fixtures/golden/activity-proc.json   { shared, extra }: the fake process list each case ran with
//   Fixtures/activity-home/              the extra HOME (relative paths, no absolute path inside)
//   Fixtures/activity-home/mtimes.json   { now, mtimes: { relativePath: ms } } because git does not keep mtimes
//
// The Swift test (ActivityGoldenTests) rebuilds the extra HOME from these files in a temporary folder, replays the same
// process lists through its fake adapter, and compares with FixtureHome.firstDifference.
import { mkdirSync, mkdtempSync, readFileSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { zstdCompressSync } from 'node:zlib';
import { readActivity } from '../../core/activity.mjs';
import { roots } from '../../core/inventory.mjs';

export const name = 'activity';

const FIXTURES = resolve(import.meta.dirname, '../../Tests/ReinsCoreTests/Fixtures');
const EXTRA_HOME = join(FIXTURES, 'activity-home');
const NOW = Date.parse('2026-11-02T12:00:00Z');
const MIN = 60_000;
const iso = (ms) => new Date(ms).toISOString();
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const sid = (n) => `${String(n).padStart(8, 'a')}-0000-4000-8000-000000000000`;
const jsonl = (records) => `${records.map((x) => JSON.stringify(x)).join('\n')}\n`;
const MARKER = '/nonexistent-reins-marker/must-not-exist';

// ---- the extra HOME ---------------------------------------------------------------------------------------------

function buildExtraHome() {
  const files = new Map(); // relative path -> { data, ageMs }
  const put = (rel, data, ageMs = 0) => files.set(rel, { data, ageMs });
  const alive = [];
  const starts = {};
  const threads = [];

  // Claude Code transcripts and status files.
  const cl = (cwd, session) => ({
    user: (text, at) => ({ type: 'user', timestamp: iso(at), cwd, sessionId: session, message: { role: 'user', content: text } }),
    tool: (id, toolName, input, at, extra = {}) => ({ type: 'assistant', timestamp: iso(at), cwd, sessionId: session, message: { id: `msg-${id}`, model: extra.model ?? 'claude-sonnet-4-6', content: [{ type: 'tool_use', id, name: toolName, input }], usage: extra.usage } }),
    result: (id, text, isError, at) => ({ type: 'user', timestamp: iso(at), cwd, sessionId: session, message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: id, is_error: isError, content: text }] } }),
    hookFail: (n, event, command, at) => ({ type: 'attachment', uuid: uuid(n), timestamp: iso(at), cwd, sessionId: session, attachment: { type: 'hook_non_blocking_error', hookEvent: event, hookName: event, command, exitCode: 1, stderr: 'check failed\nsecond line', toolUseID: `tu-${n}` } }),
  });
  const claudeLog = (cwd, session, records, ageMs = 0) => put(`.claude/projects/-${cwd.replace(/[/.]/g, '-').replace(/^-/, '')}/${session}.jsonl`, jsonl(records), ageMs);
  const status = (pid, over = {}, { live = true, start = 'Mon Nov  2 11:00:00 2026' } = {}) => {
    put(`.claude/sessions/${pid}.json`, JSON.stringify({ pid, sessionId: sid(pid), cwd: '/work/app', startedAt: NOW - 60 * MIN, procStart: 'Mon Nov  2 11:00:00 2026', status: 'idle', name: 'app-1', nameSource: 'derived', statusUpdatedAt: NOW - 50 * MIN, ...over }));
    if (live) alive.push(pid);
    if (start) starts[pid] = start;
  };
  const open = (n, extra = {}) => { const c = cl('/work/app', sid(n)); return [c.user('Build the thing', NOW - 60_000), c.tool(`b${n}`, 'Bash', { command: 'sleep 1' }, NOW - 50_000, extra)]; };

  status(1, { status: 'busy' }); claudeLog('/work/app', sid(1), open(1), 1000); // running, open tool
  status(2, { status: 'busy' }); claudeLog('/work/app', sid(2), open(2), 90_000); // busy, open tool, silent: unmeasurable
  const q = cl('/work/app', sid(3));
  status(3, { status: 'busy' }); claudeLog('/work/app', sid(3), [q.user('Plan it', NOW - 9000), q.tool('q3', 'AskUserQuestion', { question: 'Which one?' }, NOW - 8000)], 5000); // waiting
  status(4, { status: 'idle' }); claudeLog('/work/app', sid(4), open(4), 400_000);
  status(5, { status: 'shell' }); claudeLog('/work/app', sid(5), open(5), 2000);
  status(6, { status: 'busy' }, { live: false }); claudeLog('/work/app', sid(6), open(6), 60_000); // ended, still listed
  status(7, { status: 'busy' }, { live: false }); claudeLog('/work/app', sid(7), open(7), 16 * MIN); // ended long ago: dropped
  status(8, { status: 'busy' }, { start: 'Tue Nov  3 01:00:00 2026' }); claudeLog('/work/app', sid(8), open(8), 2000); // pid reused by another process
  status(9, { status: 'thinking-hard' }); claudeLog('/work/app', sid(9), open(9), 2000); // a status this app does not know
  status(10, { status: 'idle', statusUpdatedAt: NOW - 5000 }); // no transcript yet
  const junk = cl('/work/app', sid(11));
  status(11, { status: 'idle', name: 'work-app-3' });
  claudeLog('/work/app', sid(11), [
    { type: 'ai-title', aiTitle: 'Caveat: The messages below were generated by the user while running local commands', sessionId: sid(11) },
    junk.user('<command-name>/clear</command-name><command-args></command-args>', NOW - 9000), junk.user('Fix the login redirect', NOW - 8000),
  ], 30_000);
  status(12, { status: 'idle' });
  claudeLog('/work/app', sid(12), [{ type: 'custom-title', customTitle: 'My renamed session', sessionId: sid(12) }, { type: 'ai-title', aiTitle: 'Generated one', sessionId: sid(12) }, cl('/work/app', sid(12)).user('hello there', NOW - 8000)], 30_000);
  status(13, { status: 'idle', startedAt: Date.parse('2026-10-31T10:00:00Z') });
  claudeLog('/work/app', sid(13), [cl('/work/app', sid(13)).user('/review', NOW - 8000)], 30_000); // only a slash command: date and short id
  const wt = '/work/proj/.claude/worktrees/lucky-fox';
  status(14, { status: 'idle', cwd: wt });
  claudeLog(wt, sid(14), [cl(wt, sid(14)).user('Work on the thing', NOW - 5000)], 30_000); // worktree slug is not the project
  const usage = { input_tokens: 1000, output_tokens: 2000, cache_creation_input_tokens: 4000, cache_read_input_tokens: 10_000 };
  const priced = cl('/work/app', sid(15));
  status(15, { status: 'idle' });
  claudeLog('/work/app', sid(15), [
    priced.user('go', NOW - 9000), priced.tool('a', 'Read', { file_path: '/x' }, NOW - 8000, { usage }),
    { ...priced.tool('a2', 'Read', { file_path: '/y' }, NOW - 7900, { usage }), message: { ...priced.tool('a2', 'Read', { file_path: '/y' }, 0, { usage }).message, id: 'msg-a' } }, // streamed block: same message id
    priced.tool('b', 'Read', { file_path: '/z' }, NOW - 7000, { usage: { input_tokens: 500, output_tokens: 100 } }),
  ], 30_000);
  status(16, { status: 'idle' });
  claudeLog('/work/app', sid(16), [cl('/work/app', sid(16)).tool('a', 'Read', { file_path: '/x' }, NOW - 8000, { model: 'claude-mystery-9', usage })], 30_000); // no price: no estimate
  const sub = cl('/work/app', sid(17));
  status(17, { status: 'busy' });
  claudeLog('/work/app', sid(17), [sub.user('go', NOW - 900_000), sub.tool('m1', 'Agent', { description: 'delegate' }, NOW - 800_000, { usage: { input_tokens: 1_000_000 } })], 800_000);
  for (const [i, ageMs] of [[0, 600_000], [1, 2000], [2, 700_000]]) {
    put(`.claude/projects/-work-app/${sid(17)}/subagents/agent-${i}.jsonl`, jsonl([{ ...sub.tool(`s${i}`, 'Read', { file_path: '/y' }, NOW - 7000, { usage: { output_tokens: 1_000_000 } }), isSidechain: true }]), ageMs);
  }
  status(18, { status: 'idle', name: 'My named session', nameSource: 'user' }); // the status file's own name

  // Failures and file history, from logs of sessions that are not live.
  const A = cl('/work/app-a', sid(81));
  const B = cl('/work/app-b', sid(82));
  const t = (min) => NOW - min * MIN;
  claudeLog('/work/app-a', sid(81), [
    A.user('run it', t(60)),
    A.tool('a1', 'Bash', { command: 'npm test' }, t(50)), A.result('a1', 'Exit code 1\nTAP\nError: boom in suite', true, t(49)),
    A.tool('a2', 'Bash', { command: 'cd /work/app-a && npm  test' }, t(40)), A.result('a2', 'Exit code 1\nError: boom in suite', true, t(39)),
    A.tool('a3', 'Bash', { command: 'npm test' }, t(10)), A.result('a3', 'all green', false, t(9)),
    A.tool('a4', 'Bash', { command: 'make deploy' }, t(70)), A.result('a4', 'done', false, t(69)),
    A.tool('a5', 'Bash', { command: 'make deploy' }, t(30)), A.result('a5', 'Exit code 2\nmake: *** Error 2', true, t(29)),
    A.tool('a6', 'Bash', { command: 'grep nothing file.txt' }, t(20)), A.result('a6', 'Exit code 1', true, t(19)),
    A.tool('a7', 'Bash', { command: 'rm -rf build' }, t(18)), A.result('a7', "The user doesn't want to proceed with this tool use.", true, t(17)),
    A.tool('a8', 'Bash', { command: `touch ${MARKER} && false` }, t(15)), A.result('a8', 'Exit code 1', true, t(14)),
    A.hookFail(1, 'Stop', 'sh /h/check.sh', t(45)), A.hookFail(2, 'Stop', 'sh /h/check.sh', t(25)),
    A.tool('a9', 'Bash', { command: 'pnpm lint' }, t(48)), A.result('a9', 'Exit code 1\nerror: bad', true, t(47)),
    A.tool('a10', 'Bash', { command: 'pnpm lint' }, t(32)), A.result('a10', 'clean', false, t(31)),
    A.tool('a11', 'Bash', { command: 'pnpm lint' }, t(22)), A.result('a11', 'clean', false, t(21)),
    A.tool('e1', 'Edit', { file_path: '/work/app-a/src/rank.ts' }, t(55)), A.result('e1', 'ok', false, t(54)),
    A.tool('e2', 'Edit', { file_path: '/work/app-a/src/rank.ts' }, t(53)), A.result('e2', 'ok', false, t(52)),
    A.tool('e3', 'Write', { file_path: '/work/app-a/README.md' }, t(51)), A.result('e3', 'ok', false, t(50)),
    A.tool('e4', 'Edit', { file_path: '/work/app-a/nope.ts' }, t(46)), A.result('e4', 'String not found', true, t(45)),
  ], 60 * MIN);
  claudeLog('/work/app-b', sid(82), [
    B.user('again', t(55)),
    B.tool('b1', 'Bash', { command: 'npm test' }, t(5)), B.result('b1', 'Exit code 1\nError: boom in suite', true, t(4)),
    B.tool('e5', 'Edit', { file_path: '/work/app-b/src/rank.ts' }, t(10)), B.result('e5', 'ok', false, t(9)),
  ], 5 * MIN);

  // Codex rollouts. A thread is "live" when it appears in the process list below.
  const rec = (at, type, payload) => ({ timestamp: iso(at), type, payload });
  const cx = (id) => ({
    meta: (at, cwd, extra = {}) => rec(at, 'session_meta', { id, cwd, timestamp: iso(at), source: 'cli', ...extra }),
    model: (at, model) => rec(at, 'turn_context', { model }),
    started: (at) => rec(at, 'event_msg', { type: 'task_started', turn_id: 't' }),
    done: (at) => rec(at, 'event_msg', { type: 'task_complete', turn_id: 't' }),
    aborted: (at) => rec(at, 'event_msg', { type: 'turn_aborted', turn_id: 't' }),
    say: (at, text) => rec(at, 'event_msg', { type: 'item_completed', item: { type: 'UserMessage', id: `u${at}`, content: [{ type: 'text', text }] } }),
    call: (at, callId, toolName, args) => rec(at, 'response_item', { type: toolName.startsWith('custom') ? 'custom_tool_call' : 'function_call', call_id: callId, name: toolName, arguments: JSON.stringify(args) }),
    exec: (at, n, command, exit, output = '') => rec(at, 'event_msg', { type: 'item_completed', item: { type: 'CommandExecution', id: `ce${n}`, command: ['/bin/zsh', '-lc', command], cwd: '/work', exit_code: exit, aggregated_output: output } }),
    patch: (at, n, paths, state = 'completed') => rec(at, 'event_msg', { type: 'item_completed', item: { type: 'FileChange', id: `fc${n}`, status: state, changes: Object.fromEntries(paths.map((p) => [p, { type: 'update', unified_diff: '' }])) } }),
    tokens: (at, input, cached, output) => rec(at, 'event_msg', { type: 'token_count', info: { total_token_usage: { input_tokens: input, cached_input_tokens: cached, output_tokens: output } } }),
  });
  const codexPath = (id, ext = 'jsonl') => `.codex/sessions/2026/11/02/rollout-2026-11-02T01-00-00-${id}.${ext}`;
  const thread = (n, records, ageMs, { ext = 'jsonl', pid = 4000 + n } = {}) => {
    put(codexPath(uuid(n), ext), ext === 'jsonl' ? jsonl(records) : zstdCompressSync(Buffer.from(jsonl(records))), ageMs);
    threads.push({ pid, threadId: uuid(n) });
  };
  const c = (n) => cx(uuid(n));
  thread(41, [c(41).meta(NOW - 90_000, '/work/a'), c(41).started(NOW - 80_000), c(41).say(NOW - 79_000, 'Run the suite'), c(41).call(NOW - 70_000, 'k1', 'exec_command', { cmd: 'npm test' })], 2000); // running
  thread(42, [c(42).meta(NOW - 90_000, '/work/b'), c(42).started(NOW - 80_000), c(42).call(NOW - 70_000, 'k2', 'exec_command', { cmd: 'npm test' })], 120_000); // silent tool
  thread(43, [c(43).meta(NOW - 90_000, '/work/c'), c(43).started(NOW - 80_000), c(43).say(NOW - 79_000, 'Hi'), c(43).done(NOW - 70_000)], 70_000); // idle
  thread(44, [c(44).meta(NOW - 90_000, '/work/d'), c(44).started(NOW - 80_000), c(44).call(NOW - 70_000, 'k4', 'exec_command', { cmd: 'x' }), c(44).aborted(NOW - 60_000)], 60_000); // aborted
  thread(45, [c(45).meta(NOW - 90_000, '/work/e'), c(45).started(NOW - 80_000), c(45).call(NOW - 79_000, 'k5', 'request_user_input', { q: 'which?' })], 5000); // waiting
  thread(46, [c(46).meta(NOW - 90_000, '/work/f', { parent_thread_id: uuid(41), source: { subagent: { thread_spawn: { parent_thread_id: uuid(41) } } } }), c(46).started(NOW - 80_000)], 1000); // child: not a session
  threads.push({ pid: 4047, threadId: uuid(47) }); starts[4047] = 'Mon Nov  2 11:00:00 2026'; // lock held, rollout missing
  threads.push({ pid: 4048, threadId: null }); // no lock at all
  thread(49, [c(49).meta(NOW - 90_000, '/work/g'), c(49).model(NOW - 89_000, 'gpt-6.1-sol'), c(49).started(NOW - 80_000), c(49).say(NOW - 79_000, 'Compressed and live'), c(49).tokens(NOW - 70_000, 10_000, 4000, 500), c(49).tokens(NOW - 60_000, 12_000, 5000, 800)], 3000, { ext: 'jsonl.zst' });
  thread(50, [c(50).meta(NOW - 90_000, '/work/h', { parent_thread_id: uuid(49) }), c(50).started(NOW - 80_000)], 3000, { ext: 'jsonl.zst' }); // compressed child
  thread(51, [c(51).meta(NOW - 90_000, '/work/i'), c(51).model(NOW - 89_000, 'gpt-6-unlisted'), c(51).started(NOW - 80_000), c(51).tokens(NOW - 70_000, 1000, 0, 100), c(51).done(NOW - 60_000)], 60_000); // no price
  put('.codex/session_index.jsonl', jsonl([{ id: uuid(41), thread_name: 'Greet user' }, { id: uuid(43), thread_name: '/review' }, { id: uuid(47), thread_name: 'Waiting for a rollout' }]), 60 * MIN);

  // Codex history (not live): a failing command and a patch in a compressed rollout, and a legacy tool-text patch.
  put(`.codex/sessions/2026/10/20/rollout-2026-10-20T01-00-00-${uuid(60)}.jsonl.zst`, zstdCompressSync(Buffer.from(jsonl([
    cx(uuid(60)).meta(NOW - 3 * 3_600_000, '/work/app-a'), cx(uuid(60)).exec(NOW - 3 * 3_600_000 + 1000, 1, 'npm run build', 1, 'error: boom'),
    cx(uuid(60)).exec(NOW - 3 * 3_600_000 + 2000, 2, 'npm run build', 1, 'error: boom again'), cx(uuid(60)).patch(NOW - 3 * 3_600_000 + 3000, 3, ['/work/app-a/src/rank.ts', '/work/app-a/a.ts']),
  ]))), 3 * 3_600_000);
  const legacy = '*** Begin Patch\n*** Update File: src/old.ts\n@@\n*** Add File: /abs/new.ts\n*** End Patch';
  put(`.codex/sessions/2026/10/21/rollout-2026-10-21T01-00-00-${uuid(61)}.jsonl`, jsonl([
    cx(uuid(61)).meta(NOW - 4 * 3_600_000, '/work/app-a'),
    { timestamp: iso(NOW - 4 * 3_600_000 + 1000), type: 'response_item', payload: { type: 'custom_tool_call', name: 'exec', call_id: 'p1', input: legacy } },
    cx(uuid(61)).patch(NOW - 4 * 3_600_000 + 2000, 9, ['/work/app-b/src/rank.ts'], 'failed'),
  ]), 4 * 3_600_000);
  return { files, proc: { alive, starts, threads } };
}

function writeExtraHome(files) {
  const mtimes = {};
  rmSync(EXTRA_HOME, { recursive: true, force: true });
  for (const [rel, { data, ageMs }] of [...files].sort(([a], [b]) => (a < b ? -1 : 1))) {
    const target = join(EXTRA_HOME, rel);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, data);
    mtimes[rel] = NOW - ageMs;
  }
  writeFileSync(join(EXTRA_HOME, 'mtimes.json'), `${JSON.stringify({ now: NOW, mtimes }, null, 2)}\n`);
  return mtimes;
}

// ---- running the Node core ---------------------------------------------------------------------------------------

// proc spec -> the process adapter shape core/process-adapter.mjs describes
const fakeProc = (spec) => ({
  alive: (pid) => (spec.alive ?? []).includes(pid),
  startOf: (pid) => spec.starts?.[pid] ?? null,
  codexThreads: async () => spec.threads ?? [],
});

const OPTIONS = { maxHistoryFiles: 100_000 }; // no tie-breaking by directory order at the history cap
const sortBy = (list, key) => [...list].sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0));

// The lists whose order is not part of the contract are sorted; limits keep their (fixed) order.
function canonical(report) {
  return {
    sessions: sortBy(report.sessions, (s) => `${s.cli}|${s.id}`),
    failures: sortBy(report.failures, (f) => `${f.cli}|${f.kind}|${f.key}`),
    files: sortBy(report.files, (f) => f.path),
    unmeasurable: report.unmeasurable,
    stats: report.stats,
  };
}

export default async function activity(ctx) {
  // shared fixture HOME
  const h = await ctx.home();
  const sharedProc = JSON.parse(readFileSync(join(h.root, '.reins/activity-proc.json'), 'utf8'));
  const shared = canonical(await readActivity(h.r, { now: h.now, proc: fakeProc(sharedProc), cache: new Map(), ...OPTIONS }));

  // extra HOME: written to the repo, then read back from a temporary copy so the Node run sees what Swift sees
  const { files, proc: extraProc } = buildExtraHome();
  const mtimes = writeExtraHome(files);
  const tmp = mkdtempSync(join(tmpdir(), 'reins-activity-extra-'));
  let extra;
  try {
    for (const rel of Object.keys(mtimes)) {
      const target = join(tmp, rel);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, readFileSync(join(EXTRA_HOME, rel)));
      utimesSync(target, mtimes[rel] / 1000, mtimes[rel] / 1000);
    }
    const r = roots({ HOME: tmp, CLAUDE_CONFIG_DIR: join(tmp, '.claude'), CODEX_HOME: join(tmp, '.codex'), REINS_HOME: join(tmp, '.reins'), REINS_TEST: '1' });
    extra = canonical(await readActivity(r, { now: NOW, proc: fakeProc(extraProc), cache: new Map(), ...OPTIONS }));
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
  if (JSON.stringify(extra).includes(tmp)) throw new Error('the extra report contains the temporary folder path');
  if (relative(FIXTURES, EXTRA_HOME).startsWith('..')) throw new Error('unexpected fixtures path');

  ctx.writeGolden('activity', { now: NOW, shared, extra });
  ctx.writeGolden('activity-proc', { shared: sharedProc, extra: extraProc });
}
