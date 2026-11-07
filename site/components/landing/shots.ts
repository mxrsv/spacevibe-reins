/**
 * The app screens the page shows. The real ones are crops of dark captures of the SwiftUI app on
 * the synthetic fixture home (`scripts/dev-fixture.sh --shots`, 2x): the Loadout window for the hero,
 * one signature region per category (the part of the screen that is only that category), and the
 * sidebar tab each category lives behind (decorative: the caption beside it already names the category). The two `preview*` ones are renders of the tracked mocks
 * in `mocks/` for pages that are still in development; the page labels them as design previews.
 */
export interface Shot {
  readonly src: string;
  readonly width: number;
  readonly height: number;
  readonly alt: string;
}

export const SHOTS = {
  loadout: {
    src: "/landing/app/loadout.webp",
    width: 2200,
    height: 1375,
    alt: "SpaceVibe Loadout: skills listed with a bar and run count for Claude Code and for Codex, items that never ran at zero, and Add to Codex where a skill is missing.",
  },
  loadoutRows: {
    src: "/landing/app/loadout-rows.webp",
    width: 2000,
    height: 957,
    alt: "Loadout skills: an orange bar and count for Claude Code and a teal bar for Codex on each row, red zeros for skills that never ran, a dashed bar for one still being counted, and Add to Codex where a skill is missing.",
  },
  limitsDetail: {
    src: "/landing/app/limits-detail.webp",
    width: 2000,
    height: 584,
    alt: "Limits: a list of usage windows with the share left, Gemini CLI marked not measurable, and the selected Codex weekly window as 39% left of this window on a ten-segment ruler with its reset time and the age of the reading.",
  },
  activityLanes: {
    src: "/landing/app/activity-lanes.webp",
    width: 2000,
    height: 1025,
    alt: "Activity: one lane per CLI with running, waiting and idle sessions and their estimated cost, Codex sessions tagged not measurable, and failed commands grouped with a count under each lane.",
  },
  rulesVerdicts: {
    src: "/landing/app/rules-verdicts.webp",
    width: 2000,
    height: 615,
    alt: "Rules for Claude Code: Read files, Edit files, Run commands, Network, Push and deploy and Secrets each set to Allow, Ask or Deny, or tagged mixed, with the number of rules behind each.",
  },
  tabLoadout: { src: "/landing/app/tab-loadout.webp", width: 432, height: 97, alt: "" },
  tabLimits: { src: "/landing/app/tab-limits.webp", width: 432, height: 97, alt: "" },
  tabActivity: { src: "/landing/app/tab-activity.webp", width: 432, height: 97, alt: "" },
  tabRules: { src: "/landing/app/tab-rules.webp", width: 432, height: 97, alt: "" },
  previewAgents: {
    src: "/landing/app/preview-agents.webp",
    width: 1563,
    height: 919,
    alt: "Design preview of the Agents page: one card per agent with Rules, Permissions, Hooks, MCP and Model buttons, and a side panel editing Claude Code permissions.",
  },
  previewTokens: {
    src: "/landing/app/preview-tokens.webp",
    width: 1440,
    height: 900,
    alt: "Design preview of the Tokens page: estimated cost for Claude Code and Codex over 30 days, a bar chart by day, cache reuse and an estimated cost table.",
  },
} as const satisfies Record<string, Shot>;

export type ShotKey = keyof typeof SHOTS;
