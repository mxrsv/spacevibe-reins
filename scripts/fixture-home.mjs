// Writes a SYNTHETIC Claude Code and Codex home for screenshots, demos and feature tests. Nothing is read
// from a real machine: names, counts and logs are generated here and match the Matrix mock
// (ponytail 142 sessions, impeccable 87 + 31 in Codex, two dead hooks, a broad Bash(node:*) rule, ...).
//
//   node scripts/fixture-home.mjs <dir>        write into <dir> (must not exist or be empty) and print env exports
//   import { writeFixtureHome } from './fixture-home.mjs'
//
// Layout under <dir>: .claude/ .codex/ .reins/ (Reins data) and work/spacevibe-{bench,api,academy}/ (projects
// with their own .claude/settings.json). Point the app at it with HOME, CLAUDE_CONFIG_DIR, CODEX_HOME and
// REINS_HOME (the printed exports do exactly that), then `npm run dev`, or use scripts/shots.mjs.
//
// Safety: it refuses any <dir> that is, contains or sits under the real home (os.userInfo().homedir and
// $HOME, resolved through symlinks), and any <dir> that already has files. Use os.tmpdir(); ~/scratch is
// under the real home, so it is refused too (core roots() refuses it for REINS_TEST=1 for the same reason).
//
// Extending it (feature agents): add a function `(ctx) => void` to SECTIONS at the bottom. `ctx` has
// { dir, claude, codex, work, now, put(path, text), day(n), projects }. Keep it synthetic and keep the existing names.
import { existsSync, mkdirSync, readdirSync, realpathSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { userInfo } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { agentsSection } from './fixture-agents.mjs';

const DAY = 86_400_000;
const CLAUDE_SESSIONS = 142; // the largest per-item count in the mock: every skill count fits inside this many logs
const PROJECTS = ['spacevibe-bench', 'spacevibe-api', 'spacevibe-academy'];

const real = (p) => { try { return realpathSync(p); } catch { return resolve(p); } };
const within = (p, root) => { const r = relative(root, p); return r === '' || (!r.startsWith('..') && !isAbsolute(r)); };

export function assertSafeDir(dir) {
  const target = real(dir);
  for (const home of new Set([userInfo().homedir, process.env.HOME].filter(Boolean).flatMap((h) => [resolve(h), real(h)]))) {
    if (within(target, home) || within(home, target)) {
      throw new Error(`Refusing ${dir}: it is, contains or sits under the real home. Use a folder under os.tmpdir().`);
    }
  }
  if (existsSync(dir) && readdirSync(dir).length > 0) throw new Error(`Refusing ${dir}: it is not empty.`);
}

// ---- data (same names and counts as the mock) ----
const SKILLS = [
  ['ponytail', 'Pick the laziest solution that works', 142, null],
  ['impeccable', 'Design, critique and polish a frontend interface', 87, 31],
  ['diagnosing-bugs', 'Investigate a bug before fixing it', 23, null],
  ['explain', 'Explain a concept in Vietnamese', 17, 6],
  ['kyant-kanban', 'Work with the task vault', 9, 2],
  ['tdd', 'Test-driven development', 4, null],
  ['skill-creator', 'Create and improve skills', 0, null], // fresh file: "not counted yet"
  ['review-change', 'Review a change you just made', 0, null],
  ['webapp-testing', 'Test a local web app with Playwright', 0, 0],
];
const PLUGIN_SKILL = ['neon-postgres', 'Neon Postgres guides', 11];
const AGENTS = [
  ['typescript-reviewer', 'Type safety and async correctness review', 34, null],
  ['react-reviewer', 'Hooks, render performance, a11y', 19, null],
  ['database-reviewer', 'PostgreSQL schema and query review', 6, null],
  ['security-reviewer', 'OWASP-style vulnerability review', 3, 1],
  ['architect', 'System design and trade-offs', 0, null],
];
// [event, matcher, script name or inline command, runs, errors, dead?]
const HOOKS = [
  ['PreToolUse', 'Bash', 'guard-destructive.sh', 412, 0],
  ['PreToolUse', 'Edit|Write', 'block-env-edit.sh', 96, 3],
  ['PostToolUse', 'Edit|Write', 'prettier --write "$FILE"', 1204, 17],
  ['SessionStart', null, 'load-context.sh', 58, 0],
  ['Stop', null, 'notify-done.sh', 203, 0],
  ['Stop', null, 'old-dotfiles/notify.sh', 0, 0, true],
  ['PostToolUse', 'Edit', 'tools/tsc-watch.sh', 0, 0, true],
];
const ALLOW = ['Read(*)', 'Bash(git status:*)', 'Bash(git diff:*)', 'Bash(pnpm run:*)', 'Bash(node:*)', 'WebFetch(domain:github.com)'];
const ASK = ['Bash(git push:*)', 'Bash(vercel:*)'];
const DENY = ['Bash(rm -rf:*)', 'Read(.env*)', 'Edit(~/.ssh/**)'];
const PROJECT_RULES = { 'spacevibe-bench': { allow: ['Bash(pnpm tsc:*)', 'Bash(pnpm test:*)'] }, 'spacevibe-api': { deny: ['Bash(prisma migrate reset:*)'] }, 'spacevibe-academy': {} };

export function writeFixtureHome(dir, { now = Date.now() } = {}) {
  assertSafeDir(dir);
  const root = real((mkdirSync(dir, { recursive: true }), dir));
  const claude = join(root, '.claude');
  const codex = join(root, '.codex');
  const work = join(root, 'work');
  const put = (path, text) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, text); };
  const stamp = (daysAgo, hour = 10) => new Date(now - daysAgo * DAY - (10 - hour) * 3_600_000).toISOString();
  const ctx = { dir: root, claude, codex, work, now, put, day: stamp, projects: PROJECTS };
  for (const section of SECTIONS) section(ctx);
  backdate(root, now);
  mkdirSync(join(root, '.reins'), { recursive: true });
  return {
    dir: root,
    env: { HOME: root, CLAUDE_CONFIG_DIR: claude, CODEX_HOME: codex, REINS_HOME: join(root, '.reins') },
  };
}

// Config files look old (60 days) so an item with zero runs is "never ran", not "added a moment ago";
// only skill-creator keeps its fresh mtime. Logs take the time of their own last line.
function backdate(root, now) {
  const old = new Date(now - 60 * DAY);
  const visit = (p) => {
    const st = statSync(p);
    if (st.isDirectory()) { for (const e of readdirSync(p)) visit(join(p, e)); return; }
    if (p.includes(`${sep}skill-creator${sep}`) || p.endsWith('.jsonl')) return;
    utimesSync(p, old, old);
  };
  visit(root);
}

// A hook that names a script gets an absolute path inside the fixture; the two dead ones point at files that are never created.
const hookCommand = (ctx, script) =>
  /\.sh$/.test(script) ? `sh '${join(script.startsWith('tools/') || script.startsWith('old-') ? ctx.work : join(ctx.claude, 'scripts'), script)}'` : script;

const writeSkill = (ctx, base, name, description) =>
  ctx.put(join(base, name, 'SKILL.md'), `---\nname: ${name}\ndescription: ${description}\n---\n\nSynthetic skill for screenshots.\n`);

function configSection(ctx) {
  const { claude, codex, work, put } = ctx;
  for (const [name, desc] of SKILLS) writeSkill(ctx, join(claude, 'skills'), name, desc);
  for (const [name, desc, , codexRuns] of SKILLS) if (codexRuns !== null) writeSkill(ctx, join(codex, 'skills'), name, desc);
  for (const [name, desc, , codexRuns] of AGENTS) {
    put(join(claude, 'agents', `${name}.md`), `---\nname: ${name}\ndescription: ${desc}\n---\n\nSynthetic agent.\n`);
    if (codexRuns !== null) put(join(codex, 'agents', `${name}.toml`), `name = "${name}"\ndescription = "${desc}"\ndeveloper_instructions = "Synthetic agent."\n`);
  }
  // A plugin-owned skill (read-only in the UI).
  const plugin = join(claude, 'plugins/cache/neon');
  writeSkill(ctx, join(plugin, 'skills'), PLUGIN_SKILL[0], PLUGIN_SKILL[1]);
  put(join(claude, 'plugins/installed_plugins.json'), JSON.stringify({ plugins: { 'neon@fixture-market': [{ installPath: plugin }] } }));

  const hooks = {};
  for (const [event, matcher, script, , , dead] of HOOKS) {
    if (!dead && /\.sh$/.test(script)) put(join(claude, 'scripts', script), '#!/bin/sh\nexit 0\n');
    (hooks[event] ??= []).push({ ...(matcher ? { matcher } : {}), hooks: [{ type: 'command', command: hookCommand(ctx, script) }] });
  }
  put(join(claude, 'settings.json'), JSON.stringify({
    enabledPlugins: { 'neon@fixture-market': true },
    // A fake secret: the UI must never show it.
    env: { EXAMPLE_TOKEN: 'fixture-secret-do-not-show' },
    permissions: { allow: ALLOW, ask: ASK, deny: DENY },
    hooks,
  }, null, 2));
  // Codex has the Stop hook too; it cannot be measured there.
  put(join(codex, 'hooks.json'), JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: hookCommand(ctx, 'notify-done.sh') }] }] } }));
  put(join(codex, 'config.toml'), [
    'approval_policy = "on-request"', 'sandbox_mode = "workspace-write"', '', '[sandbox_workspace_write]', 'network_access = false', '',
    ...PROJECTS.flatMap((p) => [`[projects."${join(work, p)}"]`, 'trust_level = "trusted"', '']),
  ].join('\n'));
  put(join(codex, 'rules/default.rules'), 'prefix_rule(pattern=["git", "push"], decision="prompt")\n');
  for (const p of PROJECTS) {
    const rules = PROJECT_RULES[p];
    put(join(work, p, '.claude/settings.json'), JSON.stringify({ permissions: rules }, null, 2));
  }
}

const line = (obj) => JSON.stringify(obj);

function claudeLogsSection(ctx) {
  const { claude, work, put, day } = ctx;
  for (let i = 0; i < CLAUDE_SESSIONS; i++) {
    const project = PROJECTS[i % PROJECTS.length];
    const at = day((i % 28) + 1);
    const lines = [line({ type: 'user', timestamp: at, cwd: join(work, project), message: { role: 'user', content: 'Synthetic request' } })];
    if (i % 17 === 0) lines.push(line({ type: 'ai-title', aiTitle: i === 0 ? 'Fix leaderboard rank tie' : `Synthetic session ${i}` }));
    let n = 0;
    const tool = (name, input) => lines.push(line({ type: 'assistant', timestamp: at, message: { role: 'assistant', content: [{ type: 'tool_use', id: `toolu_${i}_${n++}`, name, input }] } }));
    for (const [name, , runs] of [...SKILLS, PLUGIN_SKILL]) if (i < runs) tool('Skill', { skill: name });
    for (const [name, , runs] of AGENTS) if (i < runs) tool('Task', { subagent_type: name, description: 'Synthetic' });
    for (const h of HOOKS) {
      const [event, , , runs, errors] = h;
      for (let j = i; j < runs; j += CLAUDE_SESSIONS) {
        const failed = j < errors;
        lines.push(line({ type: 'attachment', timestamp: at, attachment: { type: failed ? 'hook_non_blocking_error' : 'hook_success', hookEvent: event, command: hookCommand(ctx, h[2]), durationMs: 20 + (j % 40), exitCode: failed ? 1 : 0, stderr: failed ? 'SyntaxError in generated/schema.ts' : '' } }));
      }
    }
    // Activity: failed commands (repeats group), passes, and edited files.
    if (project === 'spacevibe-bench' && i < 21) {
      const id = `toolu_${i}_bash`;
      lines.push(line({ type: 'assistant', timestamp: at, message: { role: 'assistant', content: [{ type: 'tool_use', id, name: 'Bash', input: { command: 'pnpm tsc --noEmit' } }] } }));
      lines.push(line({ type: 'user', timestamp: at, message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: id, is_error: true, content: 'Exit code 2\nlib/leaderboard/rank.ts(41,9): error TS2322: Type \'number | undefined\' is not assignable to type \'number\'.' }] } }));
    }
    if (project === 'spacevibe-api' && i < 6) {
      const id = `toolu_${i}_push`;
      lines.push(line({ type: 'assistant', timestamp: at, message: { role: 'assistant', content: [{ type: 'tool_use', id, name: 'Bash', input: { command: 'git push origin main' } }] } }));
      lines.push(line({ type: 'user', timestamp: at, message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: id, is_error: true, content: 'Exit code 1\n! [rejected] main -> main (non-fast-forward)' }] } }));
    }
    const edited = [join(work, 'spacevibe-bench/lib/leaderboard/rank.ts'), join(work, 'spacevibe-api/src/leaderboard/rank.ts'), join(work, 'spacevibe-academy/src/repositories/course.ts')][i % 3];
    const eid = `toolu_${i}_edit`;
    lines.push(line({ type: 'assistant', timestamp: at, message: { role: 'assistant', content: [{ type: 'tool_use', id: eid, name: 'Edit', input: { file_path: edited } }] } }));
    lines.push(line({ type: 'user', timestamp: at, message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: eid, content: 'ok' }] } }));
    const file = join(claude, 'projects', `-work-${project}`, `session-${String(i).padStart(3, '0')}.jsonl`);
    put(file, `${lines.join('\n')}\n`);
    const mtime = new Date(at);
    utimesSync(file, mtime, mtime);
  }
}

function codexLogsSection(ctx) {
  const { codex, work, put, day } = ctx;
  const sessions = 31; // impeccable is the largest Codex count
  for (let i = 0; i < sessions; i++) {
    const at = day((i % 25) + 1);
    const lines = [line({ timestamp: at, type: 'session_meta', payload: { id: `fixture-${i}`, cwd: join(work, PROJECTS[i % PROJECTS.length]) } })];
    const call = (args) => lines.push(line({ timestamp: at, type: 'response_item', payload: { type: 'function_call', name: 'shell', arguments: JSON.stringify(args), call_id: `c${i}_${lines.length}` } }));
    for (const [name, , , runs] of SKILLS) if (runs !== null && i < runs) call({ command: ['bash', '-lc', `cat ${codex}/skills/${name}/SKILL.md`] });
    for (const [name, , , runs] of AGENTS) if (runs !== null && i < runs) lines.push(line({ timestamp: at, type: 'response_item', payload: { type: 'function_call', name: 'spawn_agent', arguments: JSON.stringify({ agent_type: name }), call_id: `a${i}` } }));
    const file = join(codex, 'sessions', at.slice(0, 4), at.slice(5, 7), `rollout-${String(i).padStart(3, '0')}.jsonl`);
    put(file, `${lines.join('\n')}\n`);
    const mtime = new Date(at);
    utimesSync(file, mtime, mtime);
  }
}

// Loadout: project-level skills, agents and hooks (read-only in the UI), so the Scope select has a project to show.
function loadoutProjectSection(ctx) {
  const { work, put } = ctx;
  const base = join(work, 'spacevibe-bench', '.claude');
  writeSkill(ctx, join(base, 'skills'), 'bench-checklist', 'Release checklist for this project');
  put(join(base, 'agents', 'migration-reviewer.md'), '---\nname: migration-reviewer\ndescription: Reviews database migrations\n---\n\nSynthetic agent.\n');
  put(join(base, 'settings.local.json'), JSON.stringify({ hooks: { PostToolUse: [{ matcher: 'Edit', hooks: [{ type: 'command', command: 'echo checked' }] }] } }, null, 2));
}

// Rules: one project with whole-tool rules (so its capability cells have single values) and a local file.
// REINS_FIXTURE_CODEX=unrestricted|both rewrites the Codex config for the "unrestricted" and the "both models" states.
function rulesSection(ctx) {
  const { codex, work, put } = ctx;
  put(join(work, 'spacevibe-academy/.claude/settings.json'), JSON.stringify({ permissions: { allow: ['Read', 'Edit'], ask: ['Bash', 'WebFetch', 'WebSearch'], deny: ['Bash(git push *)'] } }, null, 2));
  put(join(work, 'spacevibe-academy/.claude/settings.local.json'), JSON.stringify({ permissions: { allow: ['Bash(pnpm dev)'] } }, null, 2));
  const variant = process.env.REINS_FIXTURE_CODEX;
  if (variant !== 'unrestricted' && variant !== 'both') return;
  put(join(codex, 'config.toml'), [
    'approval_policy = "never"', 'sandbox_mode = "danger-full-access"',
    ...(variant === 'both' ? ['default_permissions = "workspace"'] : []), '',
    ...(variant === 'both' ? ['[permissions.workspace.filesystem]', '":project_roots" = "write"', ''] : []),
    ...PROJECTS.flatMap((p) => [`[projects."${join(work, p)}"]`, 'trust_level = "trusted"', '']),
  ].join('\n'));
}

// Activity: three Claude Code sessions (running, waiting with a junk title in a worktree, idle), three Codex
// processes (running, a silent tool call, one with no rollout yet), failed commands that repeat (one with a later
// pass), and two files with the same basename. Live processes are faked: the app reads <dir>/.reins/activity-proc.json
// instead of ps/lsof when REINS_TEST=1. REINS_FIXTURE_ACTIVITY=empty writes no live session; =loading delays the
// first read by 20 s so a screenshot can catch "Reading logs…". The sessions and rollouts below add to the Claude
// and Codex session counts that Loadout shows, and use no skill, agent or hook (the usage scan counts those).
function activitySection(ctx) {
  const { claude, codex, work, now, put } = ctx;
  const variant = process.env.REINS_FIXTURE_ACTIVITY;
  const at = (agoMs) => new Date(now - agoMs).toISOString();
  const MIN = 60_000;
  const log = (path, records, agoMs) => {
    put(path, `${records.map(line).join('\n')}\n`);
    utimesSync(path, new Date(now - agoMs), new Date(now - agoMs));
  };
  const id = (prefix, n) => `${prefix}${String(n).padStart(7, '0')}-0000-4000-8000-000000000000`;
  const claudeLog = (cwd, session, records, agoMs) => log(join(claude, 'projects', `-work-${cwd.split('/work/')[1].split('/')[0]}`, `${session}.jsonl`), records, agoMs);
  const usage = (n, output) => ({ input_tokens: 4000 * n, output_tokens: output, cache_creation_input_tokens: 90_000 * n, cache_read_input_tokens: 1_200_000 * n });
  const turn = (cwd, session, n, text, tool, agoMs) => [
    { type: 'user', timestamp: at(agoMs + 30_000), cwd, sessionId: session, message: { role: 'user', content: text } },
    { type: 'assistant', timestamp: at(agoMs + 20_000), cwd, sessionId: session, message: { id: `m-${session}-${n}`, model: 'claude-sonnet-5-5', content: [{ type: 'text', text: 'On it.' }], usage: usage(n, 9000 * n) } },
    ...(tool ? [{ type: 'assistant', timestamp: at(agoMs), cwd, sessionId: session, message: { id: `m-${session}-${n}b`, model: 'claude-sonnet-5-5', content: [{ type: 'tool_use', id: `tu-${session}-${n}`, name: tool.name, input: tool.input }] } }] : []),
  ];
  const bench = join(work, 'spacevibe-bench');
  const api = join(work, 'spacevibe-api');
  const academy = join(work, 'spacevibe-academy');
  const status = (pid, session, cwd, over) => put(join(claude, 'sessions', `${pid}.json`), JSON.stringify({ pid, sessionId: session, cwd, startedAt: now - 20 * MIN, status: 'idle', name: 'work-1', nameSource: 'derived', statusUpdatedAt: now, ...over }));
  const lstart = (ms) => { const d = new Date(ms); const pad = (n) => String(n).padStart(2, '0'); return `${d.toUTCString().slice(0, 3)} ${d.toUTCString().slice(8, 11)} ${String(d.getUTCDate()).padStart(2)} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())} ${d.getUTCFullYear()}`; };

  // ---- failed commands: a finished session fails `pnpm tsc` three times, then passes once; a push is rejected
  const finished = id('c', 4);
  const bash = (n, command, ok, agoMs, output) => [
    { type: 'assistant', timestamp: at(agoMs + 5000), cwd: bench, sessionId: finished, message: { id: `fm-${n}`, model: 'claude-sonnet-5-5', content: [{ type: 'tool_use', id: `fb-${n}`, name: 'Bash', input: { command } }] } },
    { type: 'user', timestamp: at(agoMs), cwd: bench, sessionId: finished, message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: `fb-${n}`, is_error: !ok, content: output }] } },
  ];
  const tscError = "Exit code 2\nlib/leaderboard/rank.ts(41,9): error TS2322: Type 'number | undefined' is not assignable to type 'number'.";
  claudeLog(bench, finished, [
    { type: 'user', timestamp: at(100 * MIN), cwd: bench, sessionId: finished, message: { role: 'user', content: 'Tighten the rank types' } },
    ...bash(1, 'pnpm tsc --noEmit', false, 90 * MIN, tscError),
    ...bash(2, 'pnpm tsc --noEmit', false, 80 * MIN, tscError),
    ...bash(3, 'pnpm tsc --noEmit', false, 70 * MIN, tscError),
    ...bash(4, 'pnpm tsc --noEmit', true, 30 * MIN, 'ok'),
    ...bash(5, 'git push origin main', false, 26 * 60 * MIN, 'Exit code 1\n! [rejected] main -> main (non-fast-forward)'),
  ], 30 * MIN);

  // ---- Codex history: a command that fails to connect three times, and edits to files that share a name
  const done = 'a0000000-0000-4000-8000-0000000000d1';
  const rec = (agoMs, type, payload) => ({ timestamp: at(agoMs), type, payload });
  const exec = (n, agoMs, command, exit, output) => rec(agoMs, 'event_msg', { type: 'item_completed', item: { type: 'CommandExecution', id: `ce${n}`, command: ['/bin/zsh', '-lc', command], exit_code: exit, aggregated_output: output } });
  const change = (n, agoMs, path) => rec(agoMs, 'event_msg', { type: 'item_completed', item: { type: 'FileChange', id: `fc${n}`, status: 'completed', changes: { [path]: { type: 'update', unified_diff: '' } } } });
  log(join(codex, 'sessions/2026/11/02', `rollout-2026-11-02T08-00-00-${done}.jsonl`), [
    rec(3 * 60 * MIN, 'session_meta', { id: done, cwd: api, timestamp: at(3 * 60 * MIN), source: 'cli' }),
    rec(3 * 60 * MIN - 1000, 'turn_context', { model: 'gpt-6-astra' }),
    exec(1, 150 * MIN, 'curl -s localhost:3000/health', 7, 'curl: (7) Failed to connect to localhost port 3000'),
    exec(2, 40 * MIN, 'curl -s localhost:3000/health', 7, 'curl: (7) Failed to connect to localhost port 3000'),
    exec(3, 22 * MIN, 'curl -s localhost:3000/health', 7, 'curl: (7) Failed to connect to localhost port 3000'),
    change(1, 120 * MIN, join(api, 'src/leaderboard/rank.ts')),
    change(2, 100 * MIN, join(api, 'src/votes/route.ts')),
    change(3, 90 * MIN, join(academy, 'src/app/api/route.ts')),
  ], 22 * MIN);

  if (variant === 'empty') {
    put(join(ctx.dir, '.reins', 'activity-proc.json'), JSON.stringify({ alive: [], threads: [] }));
    return;
  }

  // ---- live Claude Code sessions
  const running = id('c', 1);
  claudeLog(bench, running, [{ type: 'ai-title', aiTitle: 'Fix leaderboard rank tie', sessionId: running }, ...turn(bench, running, 2, 'Fix the rank tie in the leaderboard', { name: 'Bash', input: { command: 'pnpm test' } }, 2000)], 2000);
  status(41001, running, bench, { status: 'shell', startedAt: now - 18 * MIN });
  const waiting = id('c', 2);
  const worktree = join(academy, '.claude/worktrees/lesson-order-9f2');
  claudeLog(worktree, waiting, [
    { type: 'user', timestamp: at(4 * MIN), cwd: worktree, sessionId: waiting, message: { role: 'user', content: '<command-name>/clear</command-name>' } },
    ...turn(worktree, waiting, 1, '/model opus', { name: 'AskUserQuestion', input: { question: 'Which lesson order?' } }, 3000),
  ], 3000);
  status(41002, waiting, worktree, { status: 'busy', startedAt: now - 3 * MIN });
  const idle = id('c', 3);
  claudeLog(api, idle, [{ type: 'ai-title', aiTitle: 'Add rate limit to /v1/votes', sessionId: idle }, ...turn(api, idle, 3, 'Add a rate limit to the votes route', null, 8 * MIN)], 8 * MIN);
  status(41003, idle, api, { status: 'idle', startedAt: now - 45 * MIN });

  // ---- live Codex processes: one running, one silent in a tool call (unmeasurable), one with no rollout yet
  const index = [];
  const rollout = (n, cwd, title, agoMs, pending, startedAgo) => {
    const thread = `a0000000-0000-4000-8000-00000000000${n}`;
    index.push(line({ id: thread, thread_name: title, updated_at: at(agoMs) }));
    log(join(codex, 'sessions/2026/11/02', `rollout-2026-11-02T09-00-0${n}-${thread}.jsonl`), [
      rec(startedAgo, 'session_meta', { id: thread, cwd, timestamp: at(startedAgo), source: 'cli' }),
      rec(startedAgo - 1000, 'turn_context', { model: 'gpt-6-astra' }),
      rec(startedAgo - 2000, 'event_msg', { type: 'task_started', turn_id: 't' }),
      rec(startedAgo - 3000, 'event_msg', { type: 'user_message', message: title }),
      rec(startedAgo - 4000, 'event_msg', { type: 'token_count', info: { total_token_usage: { input_tokens: 600_000 * n, cached_input_tokens: 500_000 * n, output_tokens: 18_000 * n } } }),
      ...(pending ? [rec(agoMs, 'response_item', { type: 'function_call', call_id: `p${n}`, name: 'shell', arguments: JSON.stringify({ command: ['bash', '-lc', pending] }) })] : []),
    ], agoMs);
    return thread;
  };
  const silent = rollout(1, api, 'Add /v1/leaderboard cache header', 5 * MIN, 'pnpm test --run', 9 * MIN);
  const busy = rollout(2, bench, 'Port the rank tie-break to a shared helper', 4000, null, 14 * MIN);
  put(join(codex, 'session_index.jsonl'), `${index.join('\n')}\n`);
  put(join(ctx.dir, '.reins', 'activity-proc.json'), JSON.stringify({
    alive: [41001, 41002, 41003],
    starts: { 52003: lstart(now - 2 * MIN) },
    threads: [{ pid: 52001, threadId: silent }, { pid: 52002, threadId: busy }, { pid: 52003, threadId: null }],
    ...(variant === 'loading' ? { delayMs: 20_000 } : {}),
  }));
}

// Limits: only when REINS_FIXTURE_LIMITS is set, so the golden fixture (and every count derived from it) stays as it was.
// "typical": Claude Code read 2 days ago, Codex read 4 minutes ago, Gemini CLI present but not measurable.
// "edge": no Claude Code reading, Codex 5-hour window already reset and the weekly one at 4% left, no Gemini CLI.
function limitsSection(ctx) {
  const variant = process.env.REINS_FIXTURE_LIMITS;
  if (!variant) return;
  const { claude, codex, now, put } = ctx;
  const MIN = 60_000, H = 3_600_000;
  const epoch = (ms) => Math.floor(ms / 1000);
  const edge = variant === 'edge';
  if (!edge) {
    const iso = (ms) => new Date(ms).toISOString().replace('Z', '+00:00');
    const weeklyReset = now + 2 * DAY + 22 * H;
    put(join(claude, '.claude.json'), JSON.stringify({
      numStartups: 3,
      cachedUsageUtilization: {
        fetchedAtMs: now - 2 * DAY - 2 * H,
        utilization: {
          limits: [
            { kind: 'weekly_all', group: 'weekly', percent: 8, severity: 'normal', resets_at: iso(weeklyReset), scope: null, is_active: true },
            { kind: 'weekly_scoped', group: 'weekly', percent: 0, severity: 'normal', resets_at: iso(weeklyReset), scope: { model: { id: null, display_name: 'Fable' }, surface: null }, is_active: false },
          ],
        },
      },
    }));
    mkdirSync(join(ctx.dir, '.gemini'), { recursive: true });
  }
  const readAt = edge ? now - 5 * H : now - 4 * MIN;
  const limits = edge
    ? { primary: { used_percent: 88, window_minutes: 300, resets_at: epoch(now - 26 * MIN) }, secondary: { used_percent: 96, window_minutes: 10080, resets_at: epoch(now + DAY + 3 * H) }, plan_type: 'plus' }
    : { primary: { used_percent: 23, window_minutes: 300, resets_at: epoch(now + 3 * H + 12 * MIN) }, secondary: { used_percent: 61, window_minutes: 10080, resets_at: epoch(now + 6 * DAY + 16 * H) }, plan_type: 'pro' };
  put(join(codex, 'sessions', '2026', '11', '03', 'rollout-limits.jsonl'), `${JSON.stringify({ timestamp: new Date(readAt).toISOString(), type: 'event_msg', payload: { type: 'token_count', info: null, rate_limits: limits } })}\n`);
}

// Order matters: config first (logs name its hook commands), logs after. Feature agents append here.
const SECTIONS = [configSection, claudeLogsSection, codexLogsSection, loadoutProjectSection, rulesSection, activitySection, limitsSection, agentsSection];

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const dir = process.argv[2];
  if (!dir) { console.error('Usage: node scripts/fixture-home.mjs <dir under os.tmpdir()>'); process.exit(2); }
  try {
    const { env } = writeFixtureHome(dir);
    for (const [k, v] of Object.entries(env)) console.log(`export ${k}='${v}'`);
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }
}
