import { DOWNLOAD_URL, GITHUB_URL } from "../content";
import type { ShotKey } from "../shots";

/**
 * Copy for the three landing directions (mock stage, 2026-11-05). Every claim below is one the shipped
 * app shows on its own screen or PRODUCT.md states; nothing here is a number about real users.
 * The bands follow decision L13 of `docs/specs/2026-11-05-reins-landing.md`. When the owner picks a
 * direction, this moves into `../content.ts` and the unpicked directions are deleted.
 */

export const HERO_NEXT = {
  headingLines: ["Which of your skills", "actually run?"] as const,
  lede: "Reins is a local Mac app for Claude Code and Codex CLI. It counts, from your own session logs, how often every skill, subagent and hook ran, and says plainly when a CLI logs nothing to count.",
  cta: { note: "macOS 15 or later · Apple silicon", label: "Download for macOS", href: DOWNLOAD_URL },
} as const;

export type BandId = "loadout" | "limits" | "activity" | "rules";

export interface Band {
  readonly id: BandId;
  readonly label: string;
  readonly question: string;
  readonly answer: string;
  /** The region of the screen that is only this category, not the whole window. */
  readonly shot: ShotKey;
  /** The sidebar tab this category lives behind in the app. */
  readonly tab: ShotKey;
  readonly caption: string;
}

const DEMO = "demo data from a synthetic home";

export const BANDS: readonly Band[] = [
  {
    id: "loadout",
    label: "Loadout",
    question: "What is installed, and how often did it run?",
    answer:
      "One inventory across both CLIs, joined to usage counted from your local session logs: never ran, ran often, present in one CLI and missing in the other, and which hook commands fire on each event. Adding or removing one is a single step, with Undo.",
    shot: "loadoutRows",
    tab: "tabLoadout",
    caption: `Loadout · ${DEMO}`,
  },
  {
    id: "limits",
    label: "Limits",
    question: "How much of my Claude and Codex limit is left?",
    answer:
      "Read from Claude Code's status-line snapshots and Codex's session logs, with no login and no API call. A CLI that keeps no usage file reads as not measurable; Reins never guesses.",
    shot: "limitsDetail",
    tab: "tabLimits",
    caption: `Limits · ${DEMO}`,
  },
  {
    id: "activity",
    label: "Activity",
    question: "What is running, what failed, and what did it cost?",
    answer:
      "One lane per CLI: running sessions with their current tool and estimated cost, and failed commands grouped with a count. Stop a session from here. Where a CLI cannot be read, Reins says so instead of guessing.",
    shot: "activityLanes",
    tab: "tabActivity",
    caption: `Activity · ${DEMO}`,
  },
  {
    id: "rules",
    label: "Rules",
    question: "What is each CLI allowed to do?",
    answer:
      "One page per CLI, in its own terms. Claude Code's rules are Allow, Ask or Deny per capability, expandable to the rule behind them; Codex's sandbox and approvals are shown read only. Every write keeps a restorable copy.",
    shot: "rulesVerdicts",
    tab: "tabRules",
    caption: `Rules · ${DEMO}`,
  },
];

/** Direction "Two CLIs": what differs between the two CLIs on each screen, in the app's own words. */
export const DIFFS: Record<BandId, { readonly claude: string; readonly codex: string }> = {
  loadout: {
    claude: "Counts how often each skill, subagent and hook ran, and which hook commands fire on each event.",
    codex: "Counts skills and subagents. Codex does not log hook runs, so a hook reads not measurable, never 0.",
  },
  limits: {
    claude: "Reads the share left in each window from Claude Code's status-line snapshot.",
    codex: "Reads it from the last Codex turn, and shows how old that reading is.",
  },
  activity: {
    claude: "Claude Code does not record permission prompts, so a long tool run and a wait for approval look the same.",
    codex: "Codex logs nothing while a tool runs and writes no log until the first prompt is sent.",
  },
  rules: {
    claude: "Allow, Ask or Deny for each capability, editable, with the concrete rules behind each one.",
    codex: "Sandbox and approval settings in Codex's own words, shown read only.",
  },
};

/** Direction "Manual": what each screen does and the one thing it cannot see. */
export const MANUAL: Record<BandId, { readonly does: readonly string[]; readonly cannot: string }> = {
  loadout: {
    does: [
      "Lists every skill, subagent and hook with its run count in each CLI.",
      "Adds an item to the other CLI, or removes it, in one step with Undo.",
      "Shows which hook commands fire on each event.",
    ],
    cannot: "Count Codex hook runs. Codex does not log them, so they read not measurable.",
  },
  limits: {
    does: ["Shows the share left in each usage window and when it resets.", "Shows how old each reading is."],
    cannot: "Read Gemini CLI. It keeps no usage file, so it reads as not measurable.",
  },
  activity: {
    does: [
      "Shows running, waiting and idle sessions with their current tool and estimated cost.",
      "Groups failed commands with a count and notes a later pass.",
      "Stops a session you pick.",
    ],
    cannot: "Tell a long tool run from a wait for approval. Neither CLI logs the difference.",
  },
  rules: {
    does: [
      "Shows what Claude Code may do as Allow, Ask or Deny for each capability.",
      "Opens the concrete rules behind a capability, for every project or for one.",
      "Writes a change to the settings file and keeps a restorable copy.",
    ],
    cannot: "Edit Codex. Its page is read only, in Codex's own words.",
  },
};

export const UPCOMING = {
  id: "next",
  heading: "Agents and Tokens are in development.",
  label: "In development",
  previewCaption: "Design preview · not in the current download",
  items: [
    {
      name: "Agents",
      body: "One card per agent. Rules, permissions, hooks, MCP servers and model open in a side panel and save in one step.",
      shot: "previewAgents",
    },
    {
      name: "Tokens",
      body: "Tokens and estimated cost per day, model and project for both CLIs, kept as a local history.",
      shot: "previewTokens",
    },
  ] satisfies readonly { readonly name: string; readonly body: string; readonly shot: ShotKey }[],
  watch: { href: `${GITHUB_URL}/releases`, label: "Watch releases on GitHub" },
} as const;

export const DIRECTION_NAV = [
  { href: "#loadout", label: "Loadout" },
  { href: "#limits", label: "Limits" },
  { href: "#activity", label: "Activity" },
  { href: "#rules", label: "Rules" },
  { href: `#${UPCOMING.id}`, label: UPCOMING.label },
] as const;

export const DIRECTIONS = [
  { key: "deck", label: "Deck", href: "/directions/deck", line: "Each screen is a full-width window that the next one slides over." },
  { key: "two-clis", label: "Two CLIs", href: "/directions/two-clis", line: "Each screen carries what differs between Claude Code and Codex." },
  { key: "manual", label: "Manual", href: "/directions/manual", line: "A reference page: question, figure, what it does, what it cannot see." },
] as const;

export type DirectionKey = (typeof DIRECTIONS)[number]["key"];
