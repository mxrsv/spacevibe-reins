/**
 * The app screens the page shows. The five real ones are captures of the SwiftUI app on
 * the synthetic fixture home (`scripts/dev-fixture.sh --shots`, dark, 2x, resized to 2200 px);
 * the two `preview*` ones are renders of the tracked mocks in `mocks/` for pages that are
 * still in development, and the page labels them as design previews.
 */
export interface Shot {
  readonly src: string;
  readonly width: number;
  readonly height: number;
  readonly alt: string;
  /** The screen is short and the window's lower half is empty: show the top of it, cut flat. */
  readonly crop?: "wide";
}

export const SHOTS = {
  loadout: {
    src: "/landing/app/loadout.webp",
    width: 2200,
    height: 1375,
    alt: "Reins Loadout: skills listed with a bar and run count for Claude Code and for Codex, items that never ran at zero, and Add to Codex where a skill is missing.",
  },
  limits: {
    src: "/landing/app/limits.webp",
    width: 2200,
    height: 1375,
    alt: "Reins Limits: the share left in each Claude Code and Codex usage window, one window opened with its reset time and the age of the reading, and Gemini CLI marked not measurable.",
    crop: "wide",
  },
  activity: {
    src: "/landing/app/activity.webp",
    width: 2200,
    height: 1375,
    alt: "Reins Activity: one lane per CLI with running sessions and their estimated cost, failed commands grouped with a count, and a list of what cannot be measured.",
  },
  rules: {
    src: "/landing/app/rules.webp",
    width: 2200,
    height: 1375,
    alt: "Reins Rules for Claude Code: Allow, Ask or Deny for each capability, with the concrete rules listed underneath and a bar describing how Codex runs.",
  },
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
