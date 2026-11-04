# Reins: Settings

Date: 2026-11-04
Status: intent confirmed by the owner on 2026-11-04 (interview in chat); mock combination **Rail A + Content 2** chosen the
same day. Parent spec: [Reins](2026-11-02-reins.md). Execution: [plan](../plans/2026-11-04-reins-settings.md).
Mock, outside git: `~/scratch/spacevibe-reins/settings/index.html` (synthetic data; rail A "Thanh công cụ", content 2
"Xem trước").

## Intent

- Outcome: a Settings screen that starts with two sections, Appearance and Update; more sections come later.
- User: the owner, the only user today, who judges the interface by eye.
- Success: the build matches the chosen mock; Theme and Font size survive a relaunch; the Update section shows Sparkle's
  real state.
- Constraint: screens compose components and tokens only; no network request beyond Sparkle's (AGENTS.md S-R5); the
  interface stays English only.
- Out of scope: Account (owner, 2026-11-04: "bỏ qua Account, làm sau"; a Reins login would reverse "No account" and
  S-R5), translation and a Vietnamese interface, accent colour, density, installing an update without a click, a beta
  channel, a separate macOS Settings window.

## Interface

- **Placement.** Settings takes the whole Reins window: the sidebar, top bar and tab are hidden while it shows, and stay
  mounted so a tab keeps its filters. It opens from `Reins > Settings…` (`⌘,`), a gear button in the sidebar footer next
  to the theme toggle, and the `⌘K` palette. It closes with `Esc` (while the palette is closed), the back button at the
  top left, or anything that selects a tab or Limits (`⌘1`…`⌘3`, `⌘L`, a palette entry).
- **Rail (mock A).** A horizontal rail at the top, centred: one tab per section, its icon above its name, the chosen one
  filled with `surface`. The back button sits at the top left, after the window buttons. The hint bar shows only
  `Esc Back to <page>`.
- **Content (mock 2).** One centred column of cards on the well, 720 pt wide.
- **Appearance.**
  - Theme: three tiles, System, Light and Dark, each a small Reins window painted in that theme (System is half
    dark, half light). The chosen tile takes the `selection` fill.
  - Font size: Small, Default, Large in a segmented control in the card header, over two Loadout rows that show the
    size.
  - Language: the value "English" in the card header, no control, until a second language exists.
- **Update.**
  - A lead card: the Reins mark, "Reins <version>" and "Build <build>", a status tag with the time of the last check,
    and one button.
  - A row with the switch "Check for updates automatically" and "Once a day. Installing always takes a click."
  - States: no check finished since launch (time of the last check only, `Check Now`); checking (`Checking…`, button
    off); up to date (`Up to date` tag, `Check Now`); an update found (`Reins <version> is available`, `View Update` in
    place of `Check Now`); the check failed (`Check failed` warn tag, `Check Now`; not in the mock, added for a feed that
    cannot be reached); unavailable (the reason from `UpdateController`, such as "This build has no update source.
    Install a release build to receive updates.", button and switch off).

## Decisions

- **Theme.** `System` follows macOS and is new. The default stays Dark. The sidebar toggle sets Light or Dark explicitly,
  the opposite of what shows, so it leaves System.
- **Font size.** Each step adds or removes 1 pt on every 12, 14 and 16 pt role (Small 11/13/15, Large 13/15/17). Line
  boxes, spacing, icons and the two large roles `figure` (24) and `display` (72) do not change. The fixed widths that
  hold text (usage number, cost, state tag, the Rules value columns, the file history line) grow with the size and never
  shrink below their measured value. The setting applies to the whole app at once, without a relaunch.
- **Update checks.** The switch is Sparkle's automatic check. This amends the parent spec's "checks once a day without
  asking": checks are on by default and the owner can turn them off. `Check Now` is Sparkle's background probe, so the
  result shows in place and no Sparkle window opens; `View Update` and the menu's `Check for Updates…` open Sparkle's
  standard window. Opening Settings never starts a check. The time shown is Sparkle's last check date, which a probe
  also updates (Sparkle 2, `SPUUpdater.m`, `checkForUpdatesWithDriver:` sets it for every check).

## Acceptance criteria

- **ST1.** `⌘,`, the sidebar gear and the palette open Settings over the whole window; `Esc`, the back button and any tab
  or Limits shortcut close it; the tab under it keeps its state.
- **ST2.** Theme: System follows macOS live, Light and Dark fix the appearance, the choice survives a relaunch, and the
  sidebar toggle still flips between light and dark.
- **ST3.** Font size: Small, Default and Large change every 12/14/16 role across Loadout, Rules, Activity, Limits and
  Settings at once and survive a relaunch; at Large no fixed text column truncates in the fixture shots.
- **ST4.** Update: each state above renders; `Check Now` runs a probe and shows its result in place; the switch writes
  Sparkle's automatic check setting; a build without a feed shows the reason and makes no request.
- **ST5.** The build follows mock A2 (rail, tiles, preview rows, lead card); departures are named in the plan's handoff.
- **ST6.** `StyleBoundaryTests` covers `Settings/`; the new controls are components with gallery specimens; the design
  language page lists them and the size scale.
- **ST7.** The owner approves the Settings, Large-size Loadout and Activity shots by eye.
