'use strict';
/* C′ mock: Agents page with agent cards whose buttons open a right-hand panel. Demo data only. */

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const PARAMS = new URLSearchParams(location.search);
/* The sidebar keeps Solar Bold Duotone; page content draws from one candidate set (?icons=solar-linear|lucide|ph|tabler). */
const PAGE_SET = PAGE_ICONS[PARAMS.get('icons')] ? PARAMS.get('icons') : 'tabler';
const svg = (g, cls) => `<svg class="i ${cls}" viewBox="${g.vb}" aria-hidden="true">${g.body}</svg>`;
const navIcon = (name, cls = '') => svg(SOLAR[name], cls);
const iconFrom = (set, name, cls = '') => svg(PAGE_ICONS[set].icons[name], cls);
const icon = (name, cls = '') => iconFrom(PAGE_SET, name, cls);
/* Raycast-style shortcut cap inside a button; shown only by button direction C. */
const keycap = (k) => `<span class="k kbd">${k}</span>`;
const clone = (v) => structuredClone(v);
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const plural = (n, one, many = one + 's') => `${n} ${n === 1 ? one : many}`;
const fmt = (n) => n.toLocaleString('en-US');

const CLI = { claude: { name: 'Claude Code', root: '~/.claude', other: 'codex' }, codex: { name: 'Codex', root: '~/.codex', other: 'claude' } };
const PROJECTS = ['spacevibe-reins', 'spacevibe-api', 'tinysift'];
const SECTIONS = {
  rules: { title: 'Rules', icon: 'rules' }, permissions: { title: 'Permissions', icon: 'permissions' }, hooks: { title: 'Hooks', icon: 'hooks' },
  mcp: { title: 'MCP', icon: 'mcp' }, model: { title: 'Model', icon: 'model' }, advanced: { title: 'Advanced', icon: 'advanced' },
};
const FACETS = ['rules', 'permissions', 'hooks', 'mcp', 'model'];
const SCOPES = {
  claude: { rules: ['global', 'project', 'local'], permissions: ['global', 'project', 'local'], hooks: ['global', 'project', 'local'], mcp: ['global', 'project', 'local'], model: ['global', 'project', 'local'], advanced: ['global', 'project', 'local'] },
  codex: { rules: ['global', 'project'], permissions: ['global', 'project'], hooks: ['global'], mcp: ['global'], model: ['global'], advanced: ['global'] },
};
const WIDTH = { min: 420, max: 720 };
/* The agent cards never get narrower than this while a panel is open; past it the window must grow, as with a native inspector. */
const CARDS_MIN = 440;

const VERDICT = { allow: { l: 'Allow', tone: 'ok' }, ask: { l: 'Ask', tone: 'warn' }, deny: { l: 'Deny', tone: 'bad' } };
const DECISION = { allow: { l: 'Allow', tone: 'ok' }, prompt: { l: 'Prompt', tone: 'warn' }, forbidden: { l: 'Forbidden', tone: 'bad' } };
const MODES = [
  { v: 'default', l: 'Ask first', d: 'Asks the first time it uses each tool.' },
  { v: 'acceptEdits', l: 'Accept edits', d: 'Edits files without asking, asks before commands.' },
  { v: 'plan', l: 'Plan', d: 'Reads and plans, changes nothing.' },
  { v: 'bypassPermissions', l: 'Bypass', d: 'Runs every tool without asking.', warn: true },
];
const APPROVAL = [{ v: 'untrusted', l: 'Unless allowed' }, { v: 'on-request', l: 'When needed' }, { v: 'never', l: 'Never', warn: true }];
const SANDBOX = [{ v: 'read-only', l: 'Read only' }, { v: 'workspace-write', l: 'Workspace' }, { v: 'danger-full-access', l: 'Full access', warn: true }];
const TRUST = [{ v: null, l: 'Not set' }, { v: 'trusted', l: 'Trusted' }, { v: 'untrusted', l: 'Untrusted' }];
const EFFORT = [{ v: 'minimal', l: 'Minimal' }, { v: 'low', l: 'Low' }, { v: 'medium', l: 'Medium' }, { v: 'high', l: 'High' }];
const WARN = {
  bypass: 'Claude Code will run every tool, including edits and shell commands, without asking.',
  full: 'Codex will be able to read and write anywhere on this Mac and use the network.',
  never: 'Codex will never stop to ask before running a command.',
};
const EVENTS = {
  claude: ['PreToolUse', 'PostToolUse', 'UserPromptSubmit', 'Notification', 'Stop', 'SubagentStop', 'PreCompact', 'SessionStart', 'SessionEnd'],
  codex: ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'SubagentStart', 'SubagentStop', 'Interrupt', 'Stop', 'SessionEnd'],
};
const MODEL_LOG = { claude: [['opus', 104], ['sonnet', 38], ['haiku', 4]], codex: [['gpt-5-codex', 30], ['gpt-5', 4]] };
const SESSIONS = { claude: 146, codex: 34 };

const MD = {
  claudeGlobal: `# How I work

- Answer in Vietnamese; keep code identifiers in English.
- Read the code before changing it. Reuse before adding a dependency.
- Never push, merge or deploy without asking.

## Verification

Run the tests and paste the output before saying a task is done.

@~/.claude/rules/core/workflow.md
`,
  workflow: `# Workflow

- **W1.** Default to doing the work directly.
- **W3.** Edit only within the task's scope.
- **W4.** Never report "done" without running the verification command.
`,
  reinsAgents: `# AGENTS.md — spacevibe-reins

## Rules

- **S-R1.** Tests and agents never touch the real config.
- **S-R3.** Secrets are never read into the UI or logged.

## Verify

Run \`scripts/test.sh\` before every commit.
`,
  codexGlobal: `# A careful collaborator

Keep changes focused, preserve existing work, and leave every task easier to review.

## Working agreements

- Read the relevant code before making a change.
- Use native tools before adding a dependency.
- Verify the behaviour you changed.
`,
};
const IMPORTS = { '~/.claude/rules/core/workflow.md': MD.workflow, 'AGENTS.md': MD.reinsAgents };

/* Saved state, keyed agent/section/scope. A missing key reads as that section's empty value. */
const saved = {
  'claude/rules/global': MD.claudeGlobal,
  'claude/rules/project:spacevibe-reins': '@AGENTS.md\n',
  'codex/rules/global': MD.codexGlobal,
  'codex/rules/project:spacevibe-reins': MD.reinsAgents,
  'claude/permissions/global': {
    mode: 'default',
    rules: [['Read', 'allow'], ['Bash(npm run test:*)', 'allow'], ['Bash(git status)', 'allow'], ['Bash(git diff:*)', 'allow'], ['WebFetch(domain:docs.swift.org)', 'allow'],
      ['Bash(git push:*)', 'ask'], ['Bash(vercel:*)', 'ask'], ['Edit(~/.claude/**)', 'ask'], ['Bash(rm -rf:*)', 'deny'], ['Read(.env*)', 'deny'], ['Edit(~/.ssh/**)', 'deny']].map(([p, v]) => ({ p, v })),
    dirs: ['~/Developer/workspace'],
  },
  'claude/permissions/project:spacevibe-reins': { mode: null, rules: [{ p: 'Bash(scripts/test.sh)', v: 'allow' }, { p: 'Bash(swift build:*)', v: 'allow' }, { p: 'Read(Tests/Fixtures/secrets/**)', v: 'deny' }], dirs: [] },
  'claude/permissions/local:spacevibe-reins': { mode: null, rules: [{ p: 'Bash(open -a Preview:*)', v: 'allow' }], dirs: [] },
  'codex/permissions/global': {
    approval: 'on-request', sandbox: 'workspace-write', network: false, roots: [],
    rules: [['git push', 'prompt'], ['gh pr merge', 'prompt'], ['rm -rf', 'forbidden'], ['npm test', 'allow']].map(([p, d]) => ({ p, d })),
  },
  'codex/permissions/project:spacevibe-reins': { trust: 'trusted' },
  'codex/permissions/project:spacevibe-api': { trust: 'trusted' },
  'claude/hooks/global': [
    { id: 'h1', event: 'PreToolUse', matcher: 'Bash', cmd: '~/.claude/hooks/block-push.sh', runs: 1204 },
    { id: 'h2', event: 'PostToolUse', matcher: 'Edit|Write', cmd: 'prettier --write "$FILE"', runs: 12345, errors: 17 },
    { id: 'h3', event: 'Stop', matcher: '', cmd: 'afplay /System/Library/Sounds/Glass.aiff', runs: 203 },
    { id: 'h4', event: 'SessionStart', matcher: '', cmd: '~/.claude/hooks/load-context.sh', runs: 0, dead: true },
  ],
  'codex/hooks/global': [
    { id: 'x1', event: 'PreToolUse', matcher: 'shell', cmd: '~/.codex/hooks/guard.sh', runs: null },
    { id: 'x2', event: 'Stop', matcher: '', cmd: 'terminal-notifier -message "Codex finished"', runs: null },
  ],
  'claude/mcp/global': [
    { name: 'github', type: 'stdio', target: 'npx -y @modelcontextprotocol/server-github', secrets: [{ k: 'GITHUB_PERSONAL_ACCESS_TOKEN' }] },
    { name: 'context7', type: 'http', target: 'https://mcp.context7.com/mcp', secrets: [{ k: 'CONTEXT7_API_KEY' }] },
    { name: 'playwright', type: 'stdio', target: 'npx @playwright/mcp@latest', secrets: [] },
    { name: 'neon', type: 'http', target: 'https://mcp.neon.tech/mcp', secrets: [], plugin: 'neon' },
  ],
  'codex/mcp/global': [
    { name: 'github', type: 'stdio', target: 'npx -y @modelcontextprotocol/server-github', secrets: [{ k: 'GITHUB_PERSONAL_ACCESS_TOKEN' }] },
    { name: 'figma', type: 'http', target: 'http://127.0.0.1:3845/mcp', secrets: [] },
  ],
  'claude/model/global': { model: 'opus' },
  'codex/model/global': { model: 'gpt-5-codex', effort: 'medium' },
};
const EMPTY = { rules: '', permissions: { claude: { mode: null, rules: [], dirs: [] }, codex: { trust: null } }, hooks: [], mcp: [], model: { claude: { model: null }, codex: { model: null, effort: null } } };

function emptyFor(agent, section) {
  const e = EMPTY[section];
  return e && typeof e === 'object' && !Array.isArray(e) && agent in e ? clone(e[agent]) : clone(e ?? '');
}
const keyOf = (agent, section, scope) => `${agent}/${section}/${scope}`;
function readSaved(agent, section, scope) {
  const k = keyOf(agent, section, scope);
  if (section === 'advanced' && !(k in saved)) return advancedText(agent, scope);
  return k in saved ? clone(saved[k]) : emptyFor(agent, section);
}

