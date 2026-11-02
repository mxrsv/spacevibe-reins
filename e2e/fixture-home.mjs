// Builds a throwaway HOME with synthetic skills, hooks and logs (no real data) for headless runs.
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export function createFixtureHome() {
  const home = mkdtempSync(join(tmpdir(), 'reins-e2e-'));
  const put = (path, text) => { mkdirSync(join(path, '..'), { recursive: true }); writeFileSync(path, text); };
  put(join(home, '.claude/skills/keep/SKILL.md'), '---\nname: keep\ndescription: fixture\n---\n');
  put(join(home, '.claude/agents/rev.md'), '---\nname: rev\ndescription: fixture\n---\n');
  put(join(home, '.claude/settings.json'), JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo live' }] }] } }));
  put(join(home, '.codex/skills/keep/SKILL.md'), '---\nname: keep\ndescription: fixture\n---\n');
  const stamp = '"timestamp":"2026-10-30T10:00:00Z"';
  put(join(home, '.claude/projects/p/sess1.jsonl'), [
    `{"type":"assistant",${stamp},"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"keep"}}]}}`,
    `{"type":"attachment",${stamp},"attachment":{"type":"hook_success","hookEvent":"Stop","command":"echo live","durationMs":100,"exitCode":0}}`,
  ].join('\n'));
  return {
    home,
    env: { PATH: process.env.PATH, HOME: home, CLAUDE_CONFIG_DIR: join(home, '.claude'), CODEX_HOME: join(home, '.codex'), REINS_HOME: join(home, '.reins') },
  };
}
