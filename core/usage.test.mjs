// Hook records are generated here in the shape Claude Code writes them; nothing is copied from real logs.
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { roots, sha } from './inventory.mjs';
import { scan } from './usage.mjs';

const home = mkdtempSync(join(tmpdir(), 'reins-usage-'));
after(() => rmSync(home, { recursive: true, force: true }));
const r = roots({ HOME: home, CLAUDE_CONFIG_DIR: join(home, '.claude'), CODEX_HOME: join(home, '.codex'), REINS_HOME: join(home, '.reins') });

const ts = (day) => `"timestamp":"${day}T10:00:00Z"`;
const attach = (day, a) => JSON.stringify({ type: 'attachment', timestamp: `${day}T10:00:00Z`, attachment: a });

test('hook errors are counted for every error record shape, per event plus command', async () => {
  const dir = join(home, '.claude/projects/p');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 's1.jsonl'), [
    attach('2026-10-01', { type: 'hook_success', hookEvent: 'Stop', hookName: 'Stop', command: 'cmd-a', durationMs: 10, exitCode: 0, stdout: '', stderr: '' }),
    attach('2026-10-02', { type: 'hook_non_blocking_error', hookEvent: 'Stop', hookName: 'Stop', command: 'cmd-a', durationMs: 20, exitCode: 1, stdout: '', stderr: 'boom' }),
    attach('2026-10-03', { type: 'hook_success', hookEvent: 'Stop', hookName: 'Stop', command: 'cmd-a', durationMs: 30, exitCode: 2 }),
    // The blocking error carries the command inside blockingError, not at the top level.
    attach('2026-10-04', { type: 'hook_blocking_error', hookEvent: 'PostToolUse', hookName: 'PostToolUse:Edit', toolUseID: 't1', blockingError: { blockingError: 'denied', command: 'cmd-b' } }),
    attach('2026-10-05', { type: 'hook_blocking_error', hookEvent: 'PostToolUse', hookName: 'PostToolUse:Edit', toolUseID: 't2', blockingError: { blockingError: 'denied', command: 'cmd-b' } }),
    // Same command under another event is another hook.
    attach('2026-10-05', { type: 'hook_success', hookEvent: 'PreToolUse', command: 'cmd-b', durationMs: 5, exitCode: 0 }),
    // Quoted text and a record without a command are not runs.
    `{"type":"user",${ts('2026-10-05')},"message":{"content":"hook_blocking_error \\"command\\":\\"cmd-a\\""}}`,
    attach('2026-10-05', { type: 'hook_additional_context', hookEvent: 'Stop', content: {} }),
  ].join('\n'));
  const { totals } = await scan(r);
  const hook = (event, command) => totals.claude.hook[sha(`${event}|${command}`)];
  assert.deepEqual({ runs: hook('Stop', 'cmd-a').runs, errors: hook('Stop', 'cmd-a').errors, last: hook('Stop', 'cmd-a').last }, { runs: 3, errors: 2, last: '2026-10-03' });
  assert.deepEqual({ runs: hook('PostToolUse', 'cmd-b').runs, errors: hook('PostToolUse', 'cmd-b').errors }, { runs: 2, errors: 2 });
  assert.deepEqual({ runs: hook('PreToolUse', 'cmd-b').runs, errors: hook('PreToolUse', 'cmd-b').errors }, { runs: 1, errors: 0 });
});

test('scan reports the log window per CLI and rescans cache entries from an older parser', async () => {
  const { windows } = await scan(r);
  assert.equal(windows.claude.files, 1);
  assert.equal(windows.claude.oldest, '2026-10-01');
  assert.ok(windows.claude.newest > 0);
  assert.deepEqual(windows.codex, { files: 0, oldest: null, newest: null });
  // An entry written before the parser fix has no version and must not be trusted.
  const path = join(r.data, 'usage-cache.json');
  const cache = JSON.parse(readFileSync(path, 'utf8'));
  for (const e of Object.values(cache)) { delete e.v; e.rec.hook = {}; }
  writeFileSync(path, JSON.stringify(cache));
  const { totals } = await scan(r);
  assert.equal(totals.claude.hook[sha('PostToolUse|cmd-b')].errors, 2);
});
