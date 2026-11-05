// The Agents page's fixture data for scripts/fixture-home.mjs (a SECTIONS entry): synthetic only, like the rest of it.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// Agents (plan A10), only when REINS_FIXTURE_AGENTS=legacy|profiles|both, so the goldens never see it. MCP servers with
// env and headers values, token-like keys in Claude's env and Codex's config, a plain DISABLE_TELEMETRY that must show,
// instruction files with an @import, a project .mcp.json, and Codex in one of its three permission states. The two dead
// hooks come from configSection. Every value here is made up.
const FAKE_SECRET = 'fixture-secret-do-not-show';
export function agentsSection(ctx) {
  const variant = process.env.REINS_FIXTURE_AGENTS;
  if (!['legacy', 'profiles', 'both'].includes(variant)) return;
  const { claude, codex, work, put, projects } = ctx;
  const bench = join(work, 'spacevibe-bench');
  const settings = JSON.parse(readFileSync(join(claude, 'settings.json'), 'utf8'));
  settings.env = { DISABLE_TELEMETRY: '1', EXAMPLE_TOKEN: FAKE_SECRET, ANTHROPIC_API_KEY: `${FAKE_SECRET}-key` };
  settings.model = 'sonnet';
  settings.permissions.defaultMode = 'default';
  settings.permissions.additionalDirectories = [join(work, 'shared-docs')];
  put(join(claude, 'settings.json'), JSON.stringify(settings, null, 2));
  put(join(claude, '.claude.json'), JSON.stringify({
    numStartups: 41,
    theme: 'dark',
    mcpServers: {
      github: { command: 'npx', args: ['-y', '@modelcontextprotocol/server-github'], env: { GITHUB_TOKEN: FAKE_SECRET, GITHUB_ORG: 'spacevibe' } },
      linear: { type: 'http', url: 'https://mcp.linear.example/mcp', headers: { Authorization: `Bearer ${FAKE_SECRET}` } },
    },
    projects: { [bench]: { allowedTools: [], mcpServers: { 'bench-db': { command: 'bench-db-mcp', args: ['--read-only'], env: { PGPASSWORD: FAKE_SECRET } } } } },
  }, null, 2));
  put(join(bench, '.mcp.json'), JSON.stringify({ mcpServers: { docs: { type: 'http', url: 'https://docs.spacevibe.example/mcp' } } }, null, 2));
  put(join(claude, 'CLAUDE.md'), '# Working rules\n\n- Answer in **Vietnamese**, keep `code` in English.\n- Run `pnpm test` before a commit.\n\n@rules/style.md\n');
  put(join(claude, 'rules/style.md'), '# Style\n\nShort sentences. One idea per line.\n');
  put(join(bench, 'CLAUDE.md'), '# spacevibe-bench\n\nThe benchmark runner. Never commit `results/`.\n');
  put(join(codex, 'AGENTS.md'), '# Codex rules\n\n- Prefer small diffs.\n- Ask before touching `infra/`.\n');
  const common = [
    'model = "gpt-5-codex"', 'model_reasoning_effort = "medium"', 'approval_policy = "on-request"',
  ];
  const legacy = ['sandbox_mode = "workspace-write"', '', '[sandbox_workspace_write]', 'network_access = false', `writable_roots = ["${join(work, 'cache')}"]`];
  const profiles = [
    'default_permissions = "project-edit"', '',
    '[permissions.project-edit]', 'extends = ":workspace"', '',
    '[permissions.project-edit.filesystem]', '":workspace_roots" = "write"', '":workspace_roots/**/*.env" = "deny"', '"~/.ssh" = "deny"', '":tmpdir" = "write"', '',
    '[permissions.project-edit.network]', 'enabled = true', '',
    '[permissions.project-edit.network.domains]', '"api.openai.com" = "allow"', '"**.npmjs.org" = "allow"', '"*.internal.example" = "deny"', '',
    '[permissions.review-only]', 'extends = ":read-only"', '',
    '[features]', 'network_proxy = true',
  ];
  const model = variant === 'legacy' ? legacy : variant === 'profiles' ? profiles : [...legacy.slice(0, 1), ...profiles, '', ...legacy.slice(1)];
  put(join(codex, 'config.toml'), [
    '# Synthetic Codex settings for the Agents page', ...common, ...model, '',
    '[shell_environment_policy]', `set = { LANG = "en_US.UTF-8", OPENAI_API_KEY = "${FAKE_SECRET}" }`, '',
    '[mcp_servers.docs]', 'command = "docs-mcp"', 'args = ["--port", "4000"]', `env = { DOCS_TOKEN = "${FAKE_SECRET}", DOCS_HOST = "docs.internal" }`, '',
    ...projects.flatMap((p) => [`[projects."${join(work, p)}"]`, 'trust_level = "trusted"', '']),
  ].join('\n'));
}
