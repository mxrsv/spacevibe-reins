// Headless smoke test of the built app (run `npm run build` first). Starts Electron with
// REINS_TEST=1: no window is shown, HOME and the config roots point at a temporary folder, and the
// app prints counts only. Pass the path of a packaged binary to test that instead of out/.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import { createRequire } from 'node:module';
import { createFixtureHome } from './fixture-home.mjs';

const binary = process.argv[2] ?? createRequire(import.meta.url)('electron');
const args = process.argv[2] ? [] : ['.'];
const { home, env } = createFixtureHome();
try {
  const out = execFileSync(binary, args, { env: { ...env, REINS_TEST: '1' }, encoding: 'utf8', timeout: 120_000 });
  const line = out.split('\n').find((l) => l.startsWith('REINS_TEST '));
  assert.ok(line, 'no REINS_TEST line in the output');
  const result = JSON.parse(line.slice('REINS_TEST '.length));
  console.log(line);
  assert.equal(result.ok, true);
  assert.deepEqual([result.items, result.hooks, result.usageState, result.usageFiles], [3, 1, 'ready', 1]);
  assert.equal(result.badChannelRefused && result.navigationBlocked && result.windowOpenBlocked && !result.nodeLeaked, true);
  assert.equal(result.cspProbeSeen, true, 'the CSP violation counter did not see the deliberate probe');
  assert.equal(result.consoleErrors.csp, 0);
} finally {
  rmSync(home, { recursive: true, force: true });
}
