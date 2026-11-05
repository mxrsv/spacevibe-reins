/**
 * Every word and number on the landing page. Product truth comes from
 * `../../PRODUCT.md` and `docs/specs/2026-11-02-reins.md`; nothing here claims a
 * feature the spec does not. The example rows mirror the synthetic fixture home the
 * app's own tests run against (`Tests/ReinsCoreTests/Fixtures`), so every value is
 * one the engine really produced, and every panel that shows them says "demo data".
 */

export const GITHUB_URL = "https://github.com/mxrsv/spacevibe-reins";
export const DOWNLOAD_URL = `${GITHUB_URL}/releases/latest`;

export const SITE = {
  brand: "Reins",
  url: "https://reins.spacevibe.dev",
  title: "Reins — take the reins of Claude Code and Codex",
  description:
    "A local Mac app that shows every skill, subagent and hook Claude Code and Codex carry, how often each ran, what each may do, and what it cost. Nothing leaves the machine.",
} as const;

export type CLI = "claude" | "codex";

export const CLI_LABEL: Record<CLI, string> = {
  claude: "Claude Code",
  codex: "Codex",
};

export interface NavLink {
  readonly href: string;
  readonly label: string;
}

export const NAV = [
  { href: "#loadout", label: "Loadout" },
  { href: "#rules", label: "Rules" },
  { href: "#activity", label: "Activity" },
  { href: "#tokens", label: "Tokens" },
] as const;

export const HEADER = {
  github: { href: GITHUB_URL, label: "GitHub" },
  cta: { href: DOWNLOAD_URL, label: "Download for macOS" },
} as const;

export const HERO = {
  headingLines: ["Take the reins", "of your agents."] as const,
  lede:
    "A local Mac app for Claude Code and Codex CLI. See every skill, subagent and hook each one carries, how often it actually ran and what it may do — then add or remove one in seconds.",
  cta: { note: "macOS\u00A015 or later · Apple\u00A0silicon", label: "Download for macOS", href: DOWNLOAD_URL },
} as const;

/* ---------------------------------------------------------------- usage states */

/** The five usage states the app must keep visibly different (spec, Loadout). */
export type UsageCellState =
  | { readonly state: "counted"; readonly runs: number; readonly errors?: number }
  | { readonly state: "never" }
  | { readonly state: "pending" }
  | { readonly state: "unmeasurable"; readonly reason: string }
  | { readonly state: "missing" };

export type ItemKind = "skill" | "agent" | "hook";

export interface LoadoutRow {
  readonly name: string;
  readonly kind: ItemKind;
  readonly plugin?: boolean;
  readonly claude: UsageCellState;
  readonly codex: UsageCellState;
}

const CODEX_HOOKS_UNLOGGED = "Codex does not log hook runs";

/** Four rows for the hero panel: one of each state that fits a glance. */
export const HERO_LOADOUT: readonly LoadoutRow[] = [
  { name: "ponytail", kind: "skill", claude: { state: "counted", runs: 142 }, codex: { state: "missing" } },
  { name: "impeccable", kind: "skill", claude: { state: "counted", runs: 87 }, codex: { state: "counted", runs: 31 } },
  { name: "architect", kind: "agent", claude: { state: "never" }, codex: { state: "missing" } },
  {
    name: "prettier",
    kind: "hook",
    claude: { state: "counted", runs: 1204, errors: 17 },
    codex: { state: "unmeasurable", reason: CODEX_HOOKS_UNLOGGED },
  },
];

export const USAGE_LEGEND = [
  { state: "counted", label: "Counted", detail: "bar and number" },
  { state: "never", label: "Never ran", detail: "installed, zero sessions" },
  { state: "pending", label: "Not counted yet", detail: "logs still being read" },
  { state: "unmeasurable", label: "Not measurable", detail: "the CLI logs nothing for it" },
  { state: "missing", label: "Not installed", detail: "add it in place" },
] as const;

/* ---------------------------------------------------------------- the four tabs */

export const LOADOUT = {
  id: "loadout",
  heading: "Every skill, agent and hook, with the number of times it actually ran.",
  body: "One inventory across both CLIs, joined to usage counted from your local session logs. Installed but never invoked, invoked often, present in one CLI and missing in the other, and exactly which hook commands fire on each event. Adding or removing is one step, with Undo.",
  filters: ["All", "In one CLI only", "Never ran", "Dead"] as const,
  rows: [
    { name: "ponytail", kind: "skill", claude: { state: "counted", runs: 142 }, codex: { state: "missing" } },
    { name: "impeccable", kind: "skill", claude: { state: "counted", runs: 87 }, codex: { state: "counted", runs: 31 } },
    { name: "diagnosing-bugs", kind: "skill", claude: { state: "counted", runs: 23 }, codex: { state: "missing" } },
    { name: "neon-postgres", kind: "skill", plugin: true, claude: { state: "counted", runs: 11 }, codex: { state: "missing" } },
    { name: "typescript-reviewer", kind: "agent", claude: { state: "counted", runs: 34 }, codex: { state: "missing" } },
    { name: "security-reviewer", kind: "agent", claude: { state: "counted", runs: 3 }, codex: { state: "counted", runs: 1 } },
    { name: "architect", kind: "agent", claude: { state: "never" }, codex: { state: "missing" } },
    {
      name: "PostToolUse · prettier --write",
      kind: "hook",
      claude: { state: "counted", runs: 1204, errors: 17 },
      codex: { state: "unmeasurable", reason: CODEX_HOOKS_UNLOGGED },
    },
    {
      name: "SessionStart · statusline",
      kind: "hook",
      claude: { state: "pending" },
      codex: { state: "unmeasurable", reason: CODEX_HOOKS_UNLOGGED },
    },
  ] satisfies readonly LoadoutRow[],
} as const;

export type Verdict = "allow" | "ask" | "deny" | "mixed";

export interface RuleRow {
  readonly capability: string;
  readonly claude: Verdict;
  readonly codex: Verdict;
  /** Concrete rules behind the Claude Code cell, shown for the expanded row. */
  readonly rules?: readonly { readonly verdict: Exclude<Verdict, "mixed">; readonly rule: string }[];
}

export const RULES = {
  id: "rules",
  heading: "Allow, Ask or Deny for each capability, in each CLI.",
  body: "Six capabilities, each cell Allow, Ask or Deny, expandable to the concrete rule behind it. Pick a scope: global or one project. Change a cell and the settings file changes with it, and every write keeps a restorable copy.",
  scopes: ["Global", "spacevibe-academy"] as const,
  expanded: "Run commands",
  rows: [
    { capability: "Read files", claude: "allow", codex: "allow" },
    { capability: "Edit files", claude: "mixed", codex: "allow" },
    {
      capability: "Run commands",
      claude: "mixed",
      codex: "ask",
      rules: [
        { verdict: "allow", rule: "Bash(git status:*)" },
        { verdict: "allow", rule: "Bash(pnpm run:*)" },
        { verdict: "allow", rule: "Bash(node:*)" },
        { verdict: "deny", rule: "Bash(rm -rf:*)" },
      ],
    },
    { capability: "Network", claude: "mixed", codex: "deny" },
    { capability: "Push and deploy", claude: "ask", codex: "ask" },
    { capability: "Secrets (.env)", claude: "deny", codex: "ask" },
  ] satisfies readonly RuleRow[],
} as const;

export type SessionState = "running" | "waiting" | "idle" | "unmeasurable";

export interface SessionRow {
  readonly cli: CLI;
  readonly title: string;
  readonly project: string | null;
  readonly state: SessionState;
  readonly tool: string | null;
  readonly usd: number | null;
  readonly note?: string;
}

export const ACTIVITY = {
  id: "activity",
  heading: "What is running, what failed, and which files were touched.",
  body: "One lane per CLI: running sessions with their current tool and estimated cost, failed commands grouped with a count, and a file history that names the CLI on every row. Stop a session from here. When a CLI cannot be read, Reins says so instead of guessing.",
  sessions: [
    { cli: "claude", title: "Fix leaderboard rank tie", project: "spacevibe-bench", state: "running", tool: "Bash · pnpm test", usd: 0.886 },
    { cli: "claude", title: "Add rate limit to /v1/votes", project: "spacevibe-api", state: "idle", tool: null, usd: 1.329 },
    { cli: "claude", title: "2026-11-02 · c0000002", project: "spacevibe-academy", state: "waiting", tool: "AskUserQuestion", usd: 0.443 },
    { cli: "codex", title: "Port the rank tie-break to a shared helper", project: "spacevibe-bench", state: "running", tool: null, usd: 4.8 },
    {
      cli: "codex",
      title: "Add /v1/leaderboard cache header",
      project: "spacevibe-api",
      state: "unmeasurable",
      tool: "shell · pnpm test --run",
      usd: 2.4,
      note: "Codex logs nothing while a tool runs, so a long command and a wait for approval look the same.",
    },
    {
      cli: "codex",
      title: "2026-11-02 · pid 5200",
      project: null,
      state: "unmeasurable",
      tool: null,
      usd: null,
      note: "Codex writes no log until the first prompt is sent.",
    },
  ] satisfies readonly SessionRow[],
  failures: [
    { cli: "claude", title: "pnpm tsc --noEmit", count: 8, exit: 2, reason: "rank.ts(41,9): TS2322 'number | undefined' is not 'number'", laterPass: true },
    { cli: "claude", title: "git push origin main", count: 3, exit: 1, reason: "Exit 1", laterPass: false },
  ] as const,
  files: [
    { label: "src/leaderboard/rank.ts", edits: 25, clis: ["claude", "codex"] as const },
    { label: "src/repositories/course.ts", edits: 24, clis: ["claude"] as const },
    { label: "src/votes/route.ts", edits: 1, clis: ["codex"] as const },
  ] as const,
} as const;

/** Tokens per day in thousands, last 14 days. Synthetic, like the rest. */
export const TOKENS = {
  id: "tokens",
  heading: "Tokens and cost for both CLIs, in one local history.",
  body: "Per day, per model and per project, counted from the same logs. Cache reuse shown as a share. Cost is an estimate and says so; a model with no price reads as not measured, never as 0. No separate tracker, and nothing leaves the machine.",
  periods: ["Day", "Week", "Month"] as const,
  measures: ["All tokens", "New only", "Est. cost"] as const,
  byDay: {
    claude: [320, 410, 380, 520, 610, 440, 390, 700, 650, 480, 560, 720, 690, 610],
    codex: [120, 90, 160, 210, 180, 140, 220, 260, 190, 230, 310, 280, 240, 300],
  },
  cost: [
    { cli: "claude", model: "opus", share: 0.38, usdPerM: 15 },
    { cli: "claude", model: "sonnet", share: 0.62, usdPerM: 3 },
    { cli: "codex", model: "gpt-5", share: 0.85, usdPerM: 1.25 },
    { cli: "codex", model: "gpt-5-mini", share: 0.15, usdPerM: null },
  ] as const,
} as const;

export const PRIVATE = {
  id: "private",
  heading: "Private by construction.",
  items: [
    {
      lead: "No network listener, no account, no telemetry.",
      body: "The only requests the app makes are its daily update check and the download you click. No user data passes through the site either.",
    },
    {
      lead: "Nothing is executed.",
      body: "A hook is shown and written, never run by the app. Session logs are read-only.",
    },
    {
      lead: "Every write has a way back.",
      body: "Writes go only to the skill, agent, hook and permission locations of each CLI, and each one keeps a restorable copy. Undo is one click.",
    },
    {
      lead: "Secrets stay unread.",
      body: "Values that may be secrets are never read into the interface or logged. Plugin-owned items are read-only.",
    },
  ],
} as const;

export const DOWNLOAD = {
  id: "download",
  heading: "Download Reins for macOS",
  body: "Free. macOS\u00A015 or later on Apple\u00A0silicon. Reins checks for updates once a day; installing one takes a click.",
  cta: { href: DOWNLOAD_URL, label: "Download for macOS" },
  secondary: { href: GITHUB_URL, label: "GitHub" },
} as const;

export const FOOTER = {
  brand: "Reins",
  by: "SpaceVibe",
  nav: NAV,
  github: { href: GITHUB_URL, label: "GitHub" },
} as const;
