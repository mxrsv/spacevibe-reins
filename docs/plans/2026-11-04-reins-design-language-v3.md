# Reins: design language v3

Spec: [2026-11-03-reins-design-language.md](../specs/2026-11-03-reins-design-language.md) (section "v3 changes"; acceptance criteria DL1 to DL9) and, for the Limits page, [2026-11-02-reins.md](../specs/2026-11-02-reins.md) (Interface: Limits).
Related plans: [design language v2](2026-11-03-reins-design-language.md) (shipped), [Limits](2026-11-03-reins-limits.md) (L4 is redone here, task V6), [Tokens](2026-11-03-reins-tokens.md) (takes the v3 tokens when it ships).
Mock: `~/scratch/spacevibe-reins/design-language/index.html?ver=v3` on the owner's Mac (outside git, synthetic data). Its "Bảng đổi token" v3 section is the old-to-new contract. The icon comparison is `~/scratch/spacevibe-reins/icons/index.html`; the Solar glyphs the mock uses are in `design-language/solar-icons.js`.
Status: v3 approved by the owner on 2026-11-04 ("ok chốt") on the mock; no Swift written yet. Started 2026-11-04.

## Approach

Tokens first, then components, then icons, then one screen at a time; every commit leaves every screen consistent because `main` can be packaged at any point (the shipped v2 plan used the same order). No dev-only switch: nobody runs the Swift app yet.

```
Sources/Reins/Tokens/      Palette (dark surface and raised), Metrics (48 item, 56 header, ruler, tile sizes), ReinsType (+ display)
Sources/Reins/Components/  GroupedList, CardHeader, Row, SidebarItem, Tag, UsageBar/UsageCell, controls, Limit* tiles; ReinsIcon (generated)
scripts/                   generate-icons.mjs (Solar JSON to Swift shapes); a policy test for icons
Resources/Brand/           stays for the CLI marks; no icon SVG is shipped
Tests/ReinsTests/          StyleBoundaryTests (screen folders), RulerTests, IconPolicyTests
```

Facts this plan rests on, read 2026-11-04:

- The app uses 29 distinct SF Symbols in 131 places (`grep -rn 'systemName\|systemImage' Sources/Reins`); top ones: trash 10, sparkles 6, info.circle 6, exclamationmark.triangle 6, clock 6.
- `UsageBar` is constructed once; every column bar goes through `UsageCell` (`Components/UsageCell.swift`), so the ten-cell ruler is one component. `LimitBar` (Limits) is a second one and merges into the same ruler.
- CoreSVG rejected a Gemini glyph with packed arc flags and gradients on 2026-11-03 (the shipped mark in `Resources/Brand/gemini.svg` was rewritten), so SVG at run time is not a safe path for 27+ icons.
- The Solar set is on npm as `@iconify-json/solar` (CC BY 4.0). 27 glyphs of the mock map to Solar `*-bold-duotone` icons (`icon-build/solar-map.mjs` in the mock folder shows the mapping); two concepts have no Solar bold-duotone twin worth using (chevron is drawn as a stroke).
- The mock fixed the ruler's cell at 13.6 pt because the usage track is 136 pt; the Swift ruler must derive the cell from the real track width (spec: track width divided by ten).
- Shell files (`SidebarView`, `ShellCommands`) and `Components/` were owned by the design-language session `6c`, which no longer exists; the owner directs this plan, so there is nobody to coordinate with.

## Decisions made in this plan (reversible)

- **Icons are generated Swift, not resources.** `scripts/generate-icons.mjs` reads the Solar JSON (downloaded into a scratch folder, never committed) and writes `Sources/Reins/Components/ReinsIconData.swift`: per icon, a viewBox and two paths (the solid layer and the lighter layer). A small SVG path parser turns `M L H V C S Q T A Z` into SwiftUI `Path`; arcs become cubics. Why: no CoreSVG, the two layers take separate colours, and the data is reviewable text.
- **One neutral colour per icon.** The lighter layer is drawn at 50% opacity of the same colour; a tone is passed only by state tags and banners.
- **Chevron stays a stroked path** drawn by hand (the Solar chevron renders as a fragment at 20 pt).
- **The old Limits popover is deleted, not kept.** Task V6 replaces it with the page from the spec; commits `5799e3f` and `bd08339` stay as history.

## Tasks

### V1. Spec and living docs
- Spec "v3 changes" and DL7 to DL9 written; parent spec Limits Interface updated (done 2026-11-04, with this plan).
- Update `docs/DESIGN-LANGUAGE.md` (tokens table, components table, icons, attribution) in the commit that ships each token, not before (D1).

### V2. Tokens
- `Palette`: neutral greys for every surface, border, hover, divider and text (see the spec's colour line; navy first tried on 2026-11-04, replaced the same day); remove `sidebar` when nothing reads it (V4 stops using it).
- `Metrics`: sidebar item 48, card header 56, tag 24, tag radius 6, ruler (cell gap 3, height 8), tile sizes already added for Limits kept; remove constants that become unused.
- `ReinsType`: add `display` 72/88 600 (88 is the face's own height at 72, so the line box never clips), tracking −0.03 em, tabular. DL2 test: no size outside 12, 14, 16, 24, 72 exists.
- Verification: `scripts/test.sh` passes; gallery shots still render.

### V3. Components
- `GroupedList` and `CardHeader`: no border, 8 bottom padding, header 56; divider between two rows (8% text, inset 40, 8 trailing) hidden at a hovered or selected row and the one after it; the row fill is an 8-radius block inset 8.
- `SidebarItem` and `sidebarSurface()`: 48 high, `title` role in every state, icon 22 neutral, 8 between items, 16 side padding, active = fill `surface` only, ground `well` with a 1px vertical line (8% text) on the trailing edge; count `body` tertiary.
- `Tag` and `CLITag`: 24 high, radius 6, `surfaceRaised`, neutral text, 6 pt dot in the tone colour (none with an icon or without a tone), ink text for warn and danger.
- `Ruler` (Limits only): ten square-ended cells from the real track width, last cell clipped, empty cells `surfaceRaised`, dashed outline for unknown; Limits tones at 20% and 5%. `UsageCell` keeps the continuous `UsageBar` (owner, 2026-11-04: the ruler is not for other categories, and its cells are slices, not capsules).
- Controls (`ReinsButtonStyle`, `SegmentedControl`, `FilterChip`, `ScopePicker`, `SearchField`, `Kbd`): no outline, fills per spec.
- Gallery: every component in every state, both appearances.
- Verification: `RulerTests` (DL8), gallery shots read against mock v3's component sheet.
- Done 2026-11-04 on `claude/reins-design-v3`. The V2 `Metrics` items (48, 56, 24, radius 6, ruler) landed here, with their first reader; `Palette.sidebar` and `Palette.track` are gone, `Palette.divider` (text at 8%) and `ControlGround` are new. Readings where the spec is silent, all reversible: no line under a card header; 8 pt above the first row of a card that has no header (the add-rule card), to match the 8 below; a row block keeps 8 pt of padding inside its 8 pt inset, so text stays 16 pt from the card's edge and the divider starts where the text starts (40 from the block); a ruler cell is a tenth of the track with the 3 pt gap at its trailing end, capsule-shaped like the old bar; the sidebar item's 16 pt is its own inner padding (the column keeps 8). Not checked by eye: dark `hover` (0x262E3D at 55%) is now almost the colour of the brighter dark `surface`, so a hovered row in dark barely shows.

### V4. Icons
- `scripts/generate-icons.mjs` and `ReinsIcon` (a `View` taking the icon, size and tone) with the generated data; the licence text (Solar by 480 Design, CC BY 4.0) in the About or licences surface, and in `docs/DESIGN-LANGUAGE.md`.
- Replace the 29 symbols in 131 places; `IconPolicyTests` fails on `systemName:` or `systemImage:` outside `Gallery/` (DL7).
- Verification: the generator is deterministic (a rerun gives no diff); icons render at 14, 16, 20, 22 in the gallery; `scripts/test.sh` passes.
- Done 2026-11-04 from `@iconify-json/solar` 1.2.13: 31 glyphs, 464 lines of generated Swift. Picks beyond the mock's list: `arrow.right` arrow-right, `arrow.up.arrow.down` sort-vertical, `arrow.left.arrow.right` transfer-horizontal, `arrow.down.circle` round-arrow-down, `return` undo-left-round, `questionmark.folder` folder-error, `sun.max` sun; `chevron.up.chevron.down` is the drawn chevron pair and the scope menu's checkmark is the menu's own (a `Toggle` per option). Checked outside the repo: each glyph rasterised in Chromium from the Solar source and from the generated layers matches within anti-aliasing, except `layers` (Loadout), whose two overlapping 50% shapes Solar composites to 75% and one light layer draws at 50%. Credits are in the About panel (`CommandGroup(replacing: .appInfo)`, which also keeps Check for Updates).

### V5. Screens
- Loadout, Rules, Activity and the shell compose the new components; fix whatever the new rhythm breaks (row heights, column widths, the Rules grid columns, Activity's 120 pt state column). Screen folders keep zero style literals (DL3).
- Verification: shots of the four screens in both appearances from the synthetic home (`scripts/dev-fixture.sh --shots`).
- Done 2026-11-04. What the v3 components broke, found by measuring Inter (`InterVariable.woff2` in a browser) rather than by eye: a 24 pt tag beside a row name grew the row to 52, so the name's line keeps its 20 pt box (`RowText`); "not measurable" with its 16 pt icon is 125 wide, so Activity's state column is 128, not 120 (owner to confirm, see the spec's fixed widths); the add-rule card's row takes the row padding (6 around the 28 pt controls, 48 high) now that the card adds 8 above and below; the sidebar footer and the Limits block title start 16 in, like the items. The Rules columns (segmented control and "mixed" tag 228 of 280) and the "Add to Claude Code" button (168 of 200) still fit. The shots ran in CI; this session could not download them (the artifact host is outside its network policy), so no screen was looked at.

### V6. Limits page
- Rework the Limits surface from the spec: sidebar block as is (restyled by V3), `⌘L` and a click open the page; list on the left (ruler per row, Gemini CLI row), detail on the right (`display` figure, ruler, three facts, source and `Copy /usage`); delete `LimitsDetail` popover, `LimitCard`, `LimitTile`, `LimitNoteTile` and `LimitBar` where the new components replace them. `LimitsModel` and `LimitsWording` stay.
- Verification: `scripts/test.sh --filter "Limits"`; `REINS_FIXTURE_LIMITS=typical|edge REINS_SHOT_SCREEN=limits` shots in both appearances.
- Done 2026-11-04. `ShellModel.isLimitsOpen` puts `LimitsScreen` in the content area (title "Limits", hint `⌘R Refresh`); choosing a tab closes it; the active tab stays chosen underneath. The list is one "Windows" card with a section per CLI; the detail is a card with the window's name and "CLI · plan", `LimitFigure`, a `Ruler` and three `FactTile`s (resets in, resets at, reading age with its source and, for Claude Code, `Copy /usage`); a CLI without a window shows its state note there. New components `LimitShareCell`, `LimitFigure`, `FactTile`; `LimitCard`, `LimitTile`, `LimitNoteTile`, `LimitsDetail` and their metrics are gone; `LimitTone` moved to `LimitFigure.swift`. Readings where the spec is silent: the two cards share the width equally (no new column constant); "Show windows not in use" stays as a chip in the page's tools row, off by default, so "every window" reads as every window in use unless the chip is on; a passed window reads "unknown" in `title` with the dashed ruler instead of a `display` number. The CI workflow now shoots `limits` for both fixture variants, and `LimitsShots` checks the first selection (the Codex weekly window in both) and that a tab closes the page.

- Reworked 2026-11-04 after the owner compared the app with mock H ("trang limit của app đang chưa giống trong Mock"), so the readings above where the spec was silent are replaced by the mock's: the list is a 340 pt column of separate `LimitWindowTile`s on the well (no "Windows" card, no CLI sections; the CLI's 28 pt mark on each tile, "Codex · resets in 6 d 16 h" under the name, the small ruler under the text, the share at the right in one 52 pt width so the rulers end on one line; Gemini CLI has no ruler), and the detail takes the rest in a `ContentCard` (mark and "Codex · Weekly", no plan; `LimitFigure` with "left of this window"; a 32 pt ruler; three compact `FactTile`s, the reading as "4 min ago" and a passed reset as "Reset was · 26 min ago"). The source and `Copy /usage` left the Reading tile, which made all three tiles tall and cut the button to "Copy…", for one caption line under the facts. A CLI without a window shows a one-line note instead of the centred empty state. Refresh comes before the chip, as in the mock. Not taken from the mock: the in-page "Limits · Pick a window to read it" heading (it repeats the top bar's title), the "↑↓ Window" hint (no arrow-key navigation exists), and its blue-tinted greys and 3 pt cell radius (the neutral palette and square cells came later). `LimitShareCell` is gone; `LimitsShots` also shoots the Claude Code entry selected.

### V7. Shots and eye approval (one batch)
- Shots of Loadout, Rules, Activity, Limits and the shell, both appearances, typical and edge data, next to mock v3 for comparison.
- `impeccable distill` and `clarify` on the changed surfaces.
- Owner eye approval of the batch (DL9). Update `DESIGN-LANGUAGE.md`, mark this plan historical.

## Verification map

| Criterion | Check |
| --- | --- |
| DL1, DL2 | existing tests plus the size test with `display` |
| DL3 | `StyleBoundaryTests`, allowlist stays empty |
| DL4, DL5 | gallery shots (V3) |
| DL6 | `scripts/test.sh`; `scripts/build-app.sh` prints `minos 15.0` |
| DL7 | `IconPolicyTests`; licence text visible in the app |
| DL8 | `RulerTests` |
| DL9 | V7 eye approval |

## Handoff

- Checkout: `main`, shared with anyone else working in this repo; commit with `git commit -- <paths>`, stage new files with `git add -- <paths>` first. Uncommitted Electron and `src/` changes in the checkout belong to other work; leave them.
- Done: spec, parent-spec Limits Interface, this plan (docs only, 2026-11-04); V2 (`4dc72c4`, on `main`); V3 to V6 on branch `claude/reins-design-v3` (cloud session, 2026-11-04), one commit each, each green in the `swift` workflow on macos-15. That session could not compile SwiftUI itself nor download the workflow's screenshot artifact, so no shot of V3 to V6 has been looked at by anyone yet.
- Remaining: V7 (shots next to mock v3, `distill` and `clarify`, owner eye approval), then merge. Open for the owner: Activity's state column is 128, not the spec's 120 (V5); dark `hover` barely shows on the brighter dark `surface` (V3); the Loadout glyph loses Solar's 75% middle band (V4).

`/goal` Build design language v3 per docs/specs/2026-11-03-reins-design-language.md ("v3 changes", DL1 to DL9) and docs/plans/2026-11-04-reins-design-language-v3.md: complete tasks V2 to V6 in order, one commit per task, so that scripts/test.sh passes (including RulerTests and IconPolicyTests) and shots from scripts/dev-fixture.sh match ~/scratch/spacevibe-reins/design-language/index.html?ver=v3 in light and dark; leave V7 (owner eye approval) for the owner; never push, release or touch the real ~/.claude or ~/.codex.
