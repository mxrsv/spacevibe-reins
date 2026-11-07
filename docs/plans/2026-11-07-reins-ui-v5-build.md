# Reins: UI v5 build

Spec: [design language v5](../specs/2026-11-06-reins-design-language-v5.md): requirements V5-R1 to V5-R76, acceptance V5-A1 to V5-A24, the traceability table for ledger D1 to D68, the open questions and the data gaps (G1 to G13). This plan does not restate them.
Reference: the frozen mock at `~/scratch/spacevibe-reins/linear-directions/` (outside git, F4); see the spec's "Reference mock".
Checkout: `spacevibe-reins` on `main`, shared with other sessions. When this plan was written the go-core rename R1 (`REINS_*` to `SPACEVIBE_*`) was being applied, uncommitted, in the same checkout. Commit with `git commit -- <paths>` only (W11).
Started 2026-11-07. Status: U0 to U4 done 2026-11-07 (see Handoff); U5 next.

## Relation to other plans (D0)

| Plan | Relation |
| --- | --- |
| [Agents](2026-11-05-reins-agents.md) | This plan supersedes its UI placement: A8 (an Agents screen of CLI cards at `⌘2`), A10 (shots of that screen), the UI half of A12 (the Rules tab and Loadout's hooks go at this plan's X1), and the spec's AG1 placement and AG10's comparison with mock C′, by D43 to D49 and D68. It does not touch A1 to A6 (engine; the go-core plan's D-5 retargets them), A7, A9 and AG8 (the per-CLI settings panel and its push panel, a later phase by D47 and D48) or A11. Its reserved names `Sources/Reins/Agents/` and the CI loop keyed on that folder are reused here (U6). |
| [Design language v4](2026-11-05-reins-design-language-v4.md) | V2 to V8 are replaced by this plan (D15); only V1 (its spec text) was done. |
| [Go core and SpaceVibe identity](2026-11-07-go-core-and-spacevibe-identity.md) | Its open D-5 gates U1 (G-0). Its S.1 needs pixel-identical shots of the old screens, so S.1 and this plan never edit the same screen folder at once. Its R1 renames the env prefix (this plan already uses `SPACEVIBE_`), R2 the bundle id, R3 `Sources/Reins` to `Sources/SpaceVibe` (paths below then shift; risk H2). |
| [Tokens](2026-11-03-reins-tokens.md) | No Tokens page exists in the frozen mock; that plan must place its page later (risk H12). |
| [Settings](2026-11-04-reins-settings.md) | Settings takes the new token values only (V5-R7); its own eye task S10 is unaffected. |

Edits owed to other records, not made in this session: a pointer from the Agents plan's A8, A10 and A12 and the v4 plan's V2 to V8 to this plan; the "v4 changes" section of [the 2026-11-03 spec](../specs/2026-11-03-reins-design-language.md) marked superseded. They are listed again in Handoff.

## Approach

### W17 shape

- Every v5 surface is built on `main`, region by region, behind one dev switch, `SPACEVIBE_UI_V5=1`, read once in `Sources/Reins/App/LaunchMode.swift` from one name constant (so the go-core renames touch one line).
- The switch is honoured in a debug build, or in a local bundle that `scripts/build-app.sh` made without `--distribution` (the script passes `-Xswiftc -DSPACEVIBE_DEV_BUILD`); never in a distribution build. It is off by default, so the old app stays the default and `main` stays releasable.
- With the switch on, the window uses the v5 shell (sidebar Agents, Activity, Limits; Settings in the footer) and every v5 region built so far; a region not built yet shows an `EmptyState` "Not built yet" in its slot. With it off, today's app runs, changed only by the token values of U2.
- Regions: shell, Limits, Skills, Subagents, Hooks, Rules, Activity. The blocks several regions share are built first, once, in `Sources/Reins/Components` (U4, U5). A block a later region needs lands as its own small change before that region uses it; no region writes its own copy.
- Cut-over is one change, X1, after the owner's batch approval (U14). The regions are coupled through navigation: the v5 sidebar has no Loadout or Rules page and the old sidebar has no Agents tabs, so no single page can switch alone without a mixed window. X1 deletes the old surfaces, the components only they use, and the switch. A region the owner does not approve blocks X1 until it is fixed and approved, unless the owner says to cut over without it.
- Push and merge follow `CLAUDE.md` `<branching>`: each task is one commit on `main`; once the owner approves this track (G-2), each small verified change may be pushed and merged without asking (the W17 exception); X1 deletes code and asks first.

### Tokens (spec C3)

- Colour values in `Palette` change app-wide once, in U2 (D53). Settings and the old screens take them; V5-A11's shots check that nothing breaks. The toast duration (5 s) and the focus fill (D57) are app-wide too.
- The D66 spacing and sizes, the new type roles and the new blocks are new tokens and components that only v5 code uses, behind the switch. The old `Metrics` and `Rhythm` values stay for the old screens until X1 removes the unused ones ("changed N of M").

### Files (F2)

- The repo's convention ([AGENTS.md](../../AGENTS.md) "Layout", [DESIGN-LANGUAGE.md](../DESIGN-LANGUAGE.md) "The rule") wins over the generic template: one folder per screen under `Sources/Reins`, blocks in `Components`, values in `Tokens`. New screen folders, all inside the existing `Reins` target: `Sources/Reins/Agents/` (the page and its tab head), `Sources/Reins/Skills/`, `Sources/Reins/Subagents/`, `Sources/Reins/Hooks/`. New Limits, Activity, Rules and Shell views go in their existing folders beside the old files, which X1 deletes.
- Names: no generation suffix (F3: no `V5`, `New`, `-v2`); named by function (F5); UpperCamel Swift file names as in the repo. New types avoid the `Reins` prefix so R3's rename touches fewer names. Every file named "new" below is a proposal; F1 still applies (search before creating).
- Models are reused, not rewritten: [`LoadoutModel`](../../Sources/Reins/Loadout/LoadoutModel.swift) and [`LoadoutRows`](../../Sources/Reins/Loadout/LoadoutRows.swift) (skills, subagents, hooks, their writes and Undo), [`RulesModel`](../../Sources/Reins/Rules/RulesModel.swift), [`ActivityModel`](../../Sources/Reins/Activity/ActivityModel.swift), [`LimitsModel`](../../Sources/Reins/Limits/LimitsModel.swift). v5 views read these models and never call `ReinsCore` themselves, so the go-core S.1 change (screen models to DTOs) touches the models, not the new views. A page's derived facts (its Answer, bands, filters) live in a small model file in its own folder, testable without a window.
- Shots: with the switch on, the existing `SPACEVIBE_SHOT_SCREEN` keys (`shell`, `limits`, `rules`, `activity`) shoot the v5 surfaces, and new keys `skills`, `subagents`, `hooks` are added in [`ShotRenderer`](../../Sources/Reins/Gallery/ShotRenderer.swift). A state that needs files gets a variant in [`scripts/fixture-home.mjs`](../../scripts/fixture-home.mjs) (synthetic names only, S-R2) named in the header of [`scripts/dev-fixture.sh`](../../scripts/dev-fixture.sh); a pure model state (loading, empty, many) is drawn by the shot harness from an in-memory model, as `writeShellStates` does today.

### Evidence outside the repo (UP7, F4)

Shots, mock captures, crops, contrast output and review sheets go to `/tmp/reins-v5/<task>/`. Nothing of it enters the repo; the untracked `.playwright-mcp/` in the checkout stays out of every commit.

### Standard checks

```
TEST   scripts/test.sh
       → "Test run with N tests in M suites passed", N > 0; N recorded before and after the task; any change in N explained
       → if it fails only in `go vet`/`go test` of a package another session has uncommitted under `core/` (W11; check
         `git status --porcelain core/`), run the fallback /tmp/reins-v5/swift-test.sh (test.sh minus the Go vet and test
         line; it still builds the core, checks the golden hashes and runs swift test) and write "test.sh red from go-core
         WIP in <package>; Swift half: N passed", never "test.sh passes". U13 needs the real test.sh green.
BUILD  scripts/build-app.sh
       → prints "minos 15.0"
SHOTS  SPACEVIBE_UI_V5=1 SPACEVIBE_SHOT_SCREEN=<key> scripts/dev-fixture.sh --shots /tmp/reins-v5/<task>/<key>
       → PNGs in dark and light; the agent opens and reads them itself (its own check, not shown to the owner, W18)
MOCK   headless Chrome, never the Playwright MCP (it writes `.playwright-mcp/` into the repo; owner, 2026-11-07):
       /tmp/reins-v5/mock/capture.sh <out.png> '<page folder>/index.html?theme=<dark|light>&accent=1&hdr=1' [w h]
       (serves the mock folder on a free 127.0.0.1 port, shoots at 1440 x 900 by default, device scale 2, stops the server)
       → /tmp/reins-v5/mock/<page>-<theme>.png, the page frame only; pages: skills c3, subagents b-subagents, hooks b-hooks,
         rules b-rules, activity b-activity, limits b-limits; components system/components.html (1440 x 6000)
       → the bottom-left dev panel (header 1/2, accent dots, theme) is mock-only, an expected difference
SIDE   one HTML sheet per task in /tmp/reins-v5/<task>/side.html: mock PNG beside app PNG per surface and theme
       → the agent reads it; differences are listed against the spec's "Mock substitutions" (anything else is a defect or a named departure)
RUN    (W22, the runtime the owner looks at; agent memory "reins-dev-app-launch")
       pkill -x Reins; while pgrep -x Reins >/dev/null; do sleep 0.2; done
       scripts/build-app.sh
       scripts/dev-fixture.sh --prepare | grep '^export' > /tmp/reins-v5/env.sh
       ( . /tmp/reins-v5/env.sh; open -n build/Reins.app --env HOME="$HOME" --env CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" \
           --env CODEX_HOME="$CODEX_HOME" --env SPACEVIBE_HOME="$SPACEVIBE_HOME" --env SPACEVIBE_TEST=1 \
           --env SPACEVIBE_PROC_FIXTURE="$SPACEVIBE_PROC_FIXTURE" --env SPACEVIBE_UI_V5=1 )
       → lsappinfo list shows the app with the bundle id of Resources/Info.plist and type="Foreground";
         ps eww -p "$(pgrep -x Reins)" shows the synthetic HOME; the task's page opens from the sidebar and its actions work
       → afterwards pkill -x Reins and delete the synthetic home named in env.sh (never the real home)
DOCS   bash ~/.claude/scripts/docs-compliance.sh && bash ~/.claude/scripts/docs-anchors.sh
       → exit 0 and no finding (both passed when this plan was written)
```

`scripts/dev-fixture.sh` run mode is not used for RUN: it starts the raw debug binary, which macOS registers as a background process that hides under other windows. `scripts/dev.sh` is not used by agents: it reads the real `~/.claude` and `~/.codex` (S-R1); the owner uses it in U14.

## Owner decisions and gates

| ID | Decision | Recommendation | Blocks |
| --- | --- | --- | --- |
| G-0 | The go-core plan's D-5: does new UI work pause until the core review and the first Go CLI exist? | Run this plan either before go-core S.1 starts or after S.8, never alongside S.1 on the same screen folder | U1 |
| G-1 | W20: the owner has seen the spec's traceability table | show it in U0 | U1 |
| G-2 | Approve this track for the W17 push-and-merge exception | approve | pushes after U1 |
| OQ1 to OQ9 | The spec's open questions | build with the recommended defaults; the owner answers at U14 | OQ4 blocks the Rules part of X1; OQ7 needs a yes before U14 accepts departures |

## Tasks

Every task: `git status --porcelain` before the first edit, leave other sessions' changes alone, one conventional commit with a scope (W5) through `git commit -- <paths>`, temporary files deleted at the end (W8). A task that changes a documented responsibility updates its owning doc in the same commit ([AGENTS.md](../../AGENTS.md), "Read before work").

- [x] **U0. Gates (no code)**
  - Build: ask the owner G-0 and G-2 and show the spec's traceability table (G-1). The answer to D-5 is recorded in the go-core ledger by that plan's P0.2, not here.
  - Verify: Handoff holds the date and the owner's words for G-0, G-1 and G-2.
  - Acceptance: spec "Traceability (W20)".

- [x] **U1. Dev switch and the style boundary**
  - Files: [`LaunchMode.swift`](../../Sources/Reins/App/LaunchMode.swift) (the switch and its name constant); [`scripts/build-app.sh`](../../scripts/build-app.sh) (`-Xswiftc -DSPACEVIBE_DEV_BUILD` on both `swift build -c release` lines, only when not `--distribution`); [`scripts/dev.sh`](../../scripts/dev.sh) (pass `SPACEVIBE_UI_V5` to `open --env` when set); [`StyleBoundaryTests.swift`](../../Tests/ReinsTests/StyleBoundaryTests.swift); new `Tests/ReinsTests/LaunchModeTests.swift`.
  - Depends on: U0.
  - Build:
    - The switch reads the environment once; a test injects the environment and the "dev build" condition and checks on, off, and ignored in a distribution build.
    - `StyleBoundaryTests`: screen folders gain `Agents`, `Skills`, `Subagents`, `Hooks`; new patterns `.background(` with a colour or shape, `.border(`, `.shadow(`, `.overlay(` holding a stroked or filled shape, `LinearGradient|RadialGradient|AngularGradient`, `repeatForever`; a test that every folder under `Sources/Reins` is a listed screen folder or exempt (`Tokens`, `Components`, `Gallery`, `App`).
    - Measure the new patterns on today's screens first (noise): an old screen file that hits only a new pattern gets an allowlist entry with a comment, removed at X1; a v5 folder never gets one (V5-A3).
  - Verify: TEST (N up by the new tests); `grep -n 'DSPACEVIBE_DEV_BUILD' scripts/build-app.sh` shows it only outside the distribution branch; BUILD; RUN without the switch shows today's app unchanged.
  - Acceptance: V5-A3, V5-A21 (switch part); V5-R8.

- [x] **U2. Token values and the new tokens**
  - Files: [`Palette.swift`](../../Sources/Reins/Tokens/Palette.swift) (the spec's colour values, app-wide); [`Metrics.swift`](../../Sources/Reins/Tokens/Metrics.swift) (the rhythm table's sizes as new names beside the old; `toastDuration` 5 s); [`PageLayout.swift`](../../Sources/Reins/Components/PageLayout.swift) (`Rhythm`: edge 32, card 24, group 32, side 16 as new names); [`ReinsType.swift`](../../Sources/Reins/Tokens/ReinsType.swift) (roles 10, 11, 13, 16, 20, 28 per the spec's type table; `TypeScale` keeps scaling them); [`FocusRing.swift`](../../Sources/Reins/Components/FocusRing.swift) (focus as a fill, D57); new `Tests/ReinsTests/ContrastTests.swift`; new `Tests/ReinsTests/HuePolicyTests.swift`.
  - Depends on: U1.
  - Build:
    - W21 first: search the repo for every old colour literal (`#476EAE`, `#A4BFEB`, `#1596D6` and each value `Palette` holds today) and every use of each changed token; end with "changed N of M", the skipped sites named (`site/` per D14, `mocks/`, frozen specs and plans).
    - Contrast: composite each translucent token over its real ground; check the V5-A2 pairs at 4.5:1 for text and 3:1 for meaning-carrying marks, both appearances; a miss is fixed in the token. Risk H5 expects `fg3` text on `bgRaise` to miss.
    - Hue: state families are ±20° of hue around `ok`, `warn` and `bad` in OKLCH (the working threshold; the owner's eye at U14 may move it); categories, CLI identity and the accent must sit outside and apart (V5-A16).
  - Verify: TEST; shots of every old screen and Settings with the switch off (`SPACEVIBE_SHOT_SCREEN=shell|loadout|rules|activity|limits|settings`, dark and light) read for contrast, truncation and overlap; RUN with the switch off (Settings opens and reads).
  - Acceptance: V5-A2, V5-A11 (token part), V5-A16; V5-R2 to V5-R7, V5-R11, V5-R41, V5-R46.

- [x] **U3. Icons**
  - Files: [`scripts/generate-icons.mjs`](../../scripts/generate-icons.mjs) (new sources: MingCute Line for the category glyphs; the content and sidebar glyph family of open question 6, including the stop, copy and bug glyphs Activity drew page-locally); [`ReinsIconData.swift`](../../Sources/Reins/Components/ReinsIconData.swift) (regenerated, never edited by hand); [`ReinsIcon.swift`](../../Sources/Reins/Components/ReinsIcon.swift) (more than one source; size 12 for chevrons, checks and the chip close); new `Sources/Reins/Components/VerdictGlyph.swift` (the five hexagon glyphs drawn as shapes, one neutral colour); [`IconPolicyTests.swift`](../../Tests/ReinsTests/IconPolicyTests.swift); [`Credits.swift`](../../Sources/Reins/App/Credits.swift).
  - Depends on: U2.
  - Build: first compare the mock sprite (`system/shared.js` lines 83 to 116) with `@iconify-json/mingcute` and `@iconify-json/ph` (`npm pack` into a scratch folder, never committed, as AGENTS.md says for Solar) to settle which family each glyph is (spec V5-R10, C13); read each set's licence in its repository and record it in `Credits` (V5-R15). If a licence asks for more than a credit, stop and ask the owner (risk H6).
  - Verify: `node scripts/generate-icons.mjs <icons.json>` run twice, the second gives no diff; TEST; gallery shots (`SPACEVIBE_SHOT_SCREEN=shell`) beside `system/components.html` in MOCK; RUN with `SPACEVIBE_GALLERY=1` added (the gallery's icon section in the live window) and once without the switch (the old sidebar still draws its glyphs).
  - Acceptance: V5-A4, V5-A9; V5-R9, V5-R10, V5-R12, V5-R14 to V5-R16.

- [x] **U4. Shared blocks: containers**
  - Files (new in `Sources/Reins/Components/`): `Tile.swift` (card and header), `AnswerCard.swift`, `Band.swift` (header, body, the collapsed two-column grid, the open-state store), `ListRow.swift` (the 44 row with lead slot, checkbox, divider and current bar), `StatFigures.swift`, `ColumnChart.swift`. Edits: [`Cells.swift`](../../Sources/Reins/Components/Cells.swift) (bar, share and count cells beside the old ones), [`EmptyState.swift`](../../Sources/Reins/Components/EmptyState.swift) (loading skeleton, "Nothing matches" with `Clear filters`), [`ComponentGallery.swift`](../../Sources/Reins/Gallery/ComponentGallery.swift) (a specimen per state).
  - Depends on: U3.
  - Build: each block reads tokens only and draws the states in the spec's Components table; the band store keeps open and closed choices per page and band until the app quits (V5-R55).
  - Verify: TEST; gallery shots dark and light; crops of the card header, band header and row beside the same crops of `system/components.html` at the same scale (MOCK, SIDE); RUN with `SPACEVIBE_GALLERY=1` added (hover, current-row and collapse states in the live window).
  - Acceptance: V5-A10 and V5-A23 (these blocks); V5-R53 to V5-R56, V5-R58.

- [ ] **U5. Shared blocks: controls and overlays**
  - Files: new `Sources/Reins/Components/TabChips.swift` (tab chip, count circle, tab head row); new `ToolbarMenu.swift` (toolbar button, menu surface, two-level and one-level Filter menus, radio menus); [`FilterChip.swift`](../../Sources/Reins/Components/FilterChip.swift) (the `field | value | x` chip and chip row beside the capsule, which X1 removes); new `LogoToggle.swift` (toggle and strip); new `PopoverSurface.swift` (the 272 surface, placement, warning and row-detail content); new `WarningSlot.swift`; new `BulkBar.swift`; edits: [`Toast.swift`](../../Sources/Reins/Components/Toast.swift) (Undo with its `Z` cap), [`ConfirmationDialog.swift`](../../Sources/Reins/Components/ConfirmationDialog.swift) (400 wide, padding, small line), [`ReinsButtonStyle.swift`](../../Sources/Reins/Components/ReinsButtonStyle.swift) (solid danger kind, key-cap slot, focus fill), [`Kbd.swift`](../../Sources/Reins/Components/Kbd.swift), [`HintBar.swift`](../../Sources/Reins/Components/HintBar.swift) (the right-hand source note), [`PaletteParts.swift`](../../Sources/Reins/Components/PaletteParts.swift) (560, 48, 32, 32); gallery specimens.
  - Depends on: U4.
  - Verify: TEST; gallery shots; RUN with `SPACEVIBE_GALLERY=1` added: menus (arrows, `Right`, `Left`, `Return`), `Esc` from a popover returns focus, the dialog's `Tab` cycle, VoiceOver names on the logo toggle and warning slot; crops beside `system/components.html`.
  - Acceptance: V5-A10 and V5-A23 (these blocks), V5-A8 (part); V5-R20, V5-R24 to V5-R28, V5-R36 to V5-R39, V5-R57, V5-R59.

- [ ] **U6. Shell and navigation behind the switch**
  - Files: [`ShellView.swift`](../../Sources/Reins/Shell/ShellView.swift) (pick the shell by the switch); new `Sources/Reins/Shell/AppSidebar.swift` (V5-R50, with the CLI status rows and the footer); new `Sources/Reins/Shell/ContentPanel.swift` (panel frame, tab head host, chip row, status bar); [`TabRegistry.swift`](../../Sources/Reins/Shell/TabRegistry.swift) (switch on: Agents, Activity, Limits); [`ShellModel.swift`](../../Sources/Reins/Shell/ShellModel.swift) (`⌘1` to `⌘3`, Settings from the footer); [`CommandPalette.swift`](../../Sources/Reins/Shell/CommandPalette.swift); [`ThemeToggle.swift`](../../Sources/Reins/Shell/ThemeToggle.swift) (the footer button); new `Sources/Reins/Agents/AgentsPage.swift` (a `ReinsTab`: tab head with the four tabs, placeholders); [`ShotRenderer.swift`](../../Sources/Reins/Gallery/ShotRenderer.swift) (v5 keys); [`ShellModelTests.swift`](../../Tests/ReinsTests/ShellModelTests.swift); [`.github/workflows/swift.yml`](../../.github/workflows/swift.yml) (a v5 shot step; the Agents loop no longer keyed on the folder's existence).
  - Depends on: U5.
  - Build: the product name and mark come from one constant (the go-core identity work renames it, SV9). The CLI status rows show only what the shell can derive (G9); an underivable state is left out and named.
  - Verify: TEST; SHOTS `shell` beside the mock's sidebar and panel frame (any page, dark and light); RUN: the sidebar navigates, `⌘1` to `⌘3`, Settings opens from the footer, the search row and `⌘K` open the palette; without the switch the old shell.
  - Acceptance: V5-A1 (shell), V5-A13; V5-R37, V5-R49 to V5-R51, V5-R61 (head).

- [ ] **U7. Limits, the test page**
  - Files: new `Sources/Reins/Limits/LimitsCanvas.swift`; new `Sources/Reins/Limits/LimitsAnswer.swift` (the Answer, Next resets and Source facts as a model); [`LimitsModel.swift`](../../Sources/Reins/Limits/LimitsModel.swift) (refresh, the unused-windows toggle if missing); [`LimitsWording.swift`](../../Sources/Reins/Limits/LimitsWording.swift); [`LimitsShots.swift`](../../Sources/Reins/Limits/LimitsShots.swift); [`scripts/fixture-home.mjs`](../../scripts/fixture-home.mjs) only for a V5-R62 state the `typical` and `edge` variants cannot show; new `Tests/ReinsTests/LimitsAnswerTests.swift`.
  - Depends on: U6.
  - Build: thresholds come from the existing `LimitTone` (20% and 5%, already matching the mock); check the existing stale rule against the mock's 6 hours before adding one (W23). `Copy /usage` puts `/usage` on the pasteboard.
  - UP4 and UP5: Limits is the conformance pilot. After it, crop every shared block on this real page against the mock and fix the blocks before U8. No owner stop here (`CLAUDE.md` `<frontend>`); if the owner asks to see it, show it then.
  - Verify: TEST (Answer cases: one CLI has room, both low, no reading, a stale read named, Gemini not measurable); SHOTS `limits` with `SPACEVIBE_FIXTURE_LIMITS=typical` and `=edge`, dark and light; MOCK `limits`; SIDE; the V5-A20 trace for every Limits figure (source field, fixture value, shown value); fit at 1440 x 900; RUN.
  - Acceptance: V5-A1 (Limits), V5-A18 to V5-A20, V5-A22 to V5-A24 (Limits); V5-R60, V5-R62, V5-R73, V5-R74.

- [ ] **U8. Agents > Skills**
  - Files: new `Sources/Reins/Skills/SkillsTab.swift` (list and pane, the head's scope, Filter and View); new `Sources/Reins/Skills/SkillsList.swift`; new `Sources/Reins/Skills/SkillsPane.swift`; [`LoadoutRows.swift`](../../Sources/Reins/Loadout/LoadoutRows.swift) (filters, rank tiers, grouping, order, extended in place, F1); [`LoadoutModel.swift`](../../Sources/Reins/Loadout/LoadoutModel.swift) (bulk add and remove if missing); new `Sources/Reins/Skills/SkillsShots.swift`; `Sources/Reins/Agents/AgentsPage.swift` (new in U6); [`LoadoutRowsTests.swift`](../../Tests/ReinsTests/LoadoutRowsTests.swift).
  - Depends on: U7.
  - Build: usage per D63 (L81) without an engine change: the engine's `pending` cell reads as `Never ran` with the neutral clock and "added <when>"; counts say "sessions" (S2, S3).
  - Verify: TEST (V5-A5; the write paths keep their `ReinsCoreTests`); SHOTS `skills` (normal, filtered, grouped, multi-select with the bottom bar, warning popover, pane states, empty); MOCK `skills`; SIDE; the V5-A20 trace (session counts against the fixture's usage golden); RUN: a logo toggle shows the toast, `z` restores the file bytes on the synthetic home, `x` and the bottom bar.
  - Acceptance: V5-A1 (Skills), V5-A5, V5-A6, V5-A7 (Skills), V5-A19, V5-A20; V5-R18 to V5-R35.

- [ ] **U9. Agents > Subagents**
  - Files: new `Sources/Reins/Subagents/SubagentsTab.swift`; new `Sources/Reins/Subagents/SubagentsModel.swift` (Answer, bands by presence and by model, warning states, filters, the addable rule); new `Sources/Reins/Subagents/SubagentsShots.swift`; `Sources/Reins/Agents/AgentsPage.swift`; new `Tests/ReinsTests/SubagentsModelTests.swift`.
  - Depends on: U8.
  - Build: settle G1 and G10 first. Without model and tools in the data, the model column, the Model grouping, the Can-touch filter and the "can run Bash" half of the Answer are left out as named departures (open question 7), and the Answer uses only the facts the data has. The add-to-other-CLI toast says what the write really does.
  - Verify: TEST; SHOTS `subagents` (V5-R62 states); MOCK `agents`; SIDE; the V5-A20 trace; fit (the spine scrolls inside, accepted by D68); RUN.
  - Acceptance: V5-A1 (Subagents), V5-A6, V5-A18 to V5-A20, V5-A22, V5-A24; V5-R52 to V5-R57, V5-R63, V5-R64.

- [ ] **U10. Agents > Hooks**
  - Files: new `Sources/Reins/Hooks/HooksTab.swift`; new `Sources/Reins/Hooks/HooksModel.swift` (groups by event and name, the one copy rule, Answer, the two small-card lists, filters); new `Sources/Reins/Hooks/HooksShots.swift`; `Sources/Reins/Agents/AgentsPage.swift`; new `Tests/ReinsTests/HooksModelTests.swift`.
  - Depends on: U9.
  - Build: settle G2 and G3 first against the CLIs' hook docs (UP6). Event order and per-CLI events come from the inventory's `events` (`InventoryTypes.swift`), not from a list typed in the view. Codex hook runs read `Unmeasurable` (S5). Without a handler kind in the data, the Handler filter and its reason are left out as named departures.
  - Verify: TEST; SHOTS `hooks` (sample, healthy, many, none, Codex not installed, loading); MOCK `hooks`; SIDE; the V5-A20 trace; fit (the stack scrolls inside, accepted); RUN: copy to Codex, toast, `z` restores the bytes; remove a hook whose script is gone.
  - Acceptance: V5-A1 (Hooks), V5-A6, V5-A17, V5-A18 to V5-A20, V5-A22, V5-A24; V5-R65, V5-R66.

- [ ] **U11. Agents > Rules**
  - Files: new `Sources/Reins/Rules/RulesCanvas.swift` (small cards and the Permissions spine); new `Sources/Reins/Rules/RuleFamilies.swift` (a rule's family from `RuleItem.tool`, stance, the mismatch against Codex's facts, redundant rules); [`RulesModel.swift`](../../Sources/Reins/Rules/RulesModel.swift) (verdict change and remove reused; a family change as one Journal entry if the engine allows, else one per rule); [`RulesShots.swift`](../../Sources/Reins/Rules/RulesShots.swift) and [`scripts/rules-shots.sh`](../../scripts/rules-shots.sh) (v5 states, the invalid-file state); `Sources/Reins/Agents/AgentsPage.swift`; new `Tests/ReinsTests/RuleFamiliesTests.swift`.
  - Depends on: U10.
  - Build: settle C18 and G12 first: map each family to the Codex fact `RulesCodexPermissions` really holds; where none maps, the Codex cell stays empty rather than guessed. Global scope only, as the mock shows; the old Rules page keeps project scopes and adding a rule until OQ4 is answered.
  - Verify: TEST; SHOTS `rules` (with the `SPACEVIBE_FIXTURE_CODEX` variants), states including the invalid file; MOCK `rules`; SIDE; the V5-A20 trace; fit (Rules scrolls inside, accepted); RUN: change a family's verdict from the Answer, toast, `z` restores `settings.json` byte for byte.
  - Acceptance: V5-A1 (Rules), V5-A6, V5-A17, V5-A18 to V5-A20, V5-A22, V5-A24; V5-R67, V5-R68.

- [ ] **U12. Activity**
  - Files: new `Sources/Reins/Activity/ActivityCanvas.swift` (tabs and the three canvases); new `Sources/Reins/Activity/ActivityAnswers.swift` (the three Answers, Today, Busiest projects, bands); [`ActivityModel.swift`](../../Sources/Reins/Activity/ActivityModel.swift) (dismissal kept in memory, G13); [`ActivityStopConfirmation.swift`](../../Sources/Reins/Activity/ActivityStopConfirmation.swift) (V5-R59 through `ConfirmationDialog`); [`ActivityTab.swift`](../../Sources/Reins/Activity/ActivityTab.swift); [`ActivityShots.swift`](../../Sources/Reins/Activity/ActivityShots.swift); new `Tests/ReinsTests/ActivityAnswersTests.swift`.
  - Depends on: U11.
  - Build: settle G4, G5, G6, G11 and G13 first. Today shows only figures the engine reports, each labelled for what it is ("estimated cost of running sessions", not "today", if that is all the data says), or the card is left out as a named departure. `Open` per open question 5 (a folder or a log file in the default app; no process, S-R4). Stop goes through the existing pid-checked path; in the fixture it edits the list only.
  - Verify: TEST; SHOTS `activity` (Running, Failed, Files, the Stop dialog, and the V5-R62 states with `SPACEVIBE_FIXTURE_ACTIVITY=empty|loading`); MOCK `activity` (tabs switched with `1` to `3`); SIDE; the V5-A20 trace (cost labelled as an estimate, ranges real); RUN: Stop on a fixture session names its pid, then a toast with no Undo.
  - Acceptance: V5-A1 (Activity), V5-A17 to V5-A20, V5-A22, V5-A24; V5-R59, V5-R69 to V5-R72.

- [ ] **U13. Audits, sweeps and polish**
  - Files: fixes land in `Tokens`, `Components` or the page's own model file; results go to "Verification evidence" below.
  - Depends on: U12.
  - Build:
    - W21 vocabulary sweep over `Sources/Reins`, shot text and accessible names for every word V5-R45 bans, plus "Loadout" in visible strings: "changed N of M", skipped sites named (V5-A15).
    - Flow audit per page (V5-A17); numbers once (V5-A24); keyboard walkthrough (V5-A7) and VoiceOver and reduced motion (V5-A8) in RUN.
    - Fit at 1440 x 900 and below 700 pt of canvas width (V5-A22); conformance crops of every shared block on every page (V5-A23); every V5-R62 state shot (V5-A19); the V5-A20 trace complete for every page.
    - `impeccable distill` and `clarify` on every surface (`CLAUDE.md` `<frontend>`), without breaking UP1 (fixes go to blocks, never to a page).
    - The review sheet `/tmp/reins-v5/review/index.html`: every surface, mock beside app, dark and light, with the expected substitutions and the named departures listed per surface.
  - Verify: each audit's output pasted under "Verification evidence"; TEST; BUILD.
  - Acceptance: V5-A7, V5-A8, V5-A11, V5-A12 (tests and build), V5-A15, V5-A17, V5-A19, V5-A20, V5-A22 to V5-A24.

- [ ] **U14. Owner eye approval, one batch**
  - Build: in the owner's runtime: RUN, left open; the owner may also run `SPACEVIBE_UI_V5=1 scripts/dev.sh` themselves to see their real data (it reads the real `~/.claude` and `~/.codex`; every write has Undo and a restorable copy). Open the review sheet as the last step (W18, main sheet only).
  - The owner judges each surface on structure, content, look and theme, in dark and light (light for the first time since D66), and answers the spec's open questions 1 to 9.
  - Verify: the owner's words per surface and per open question, with the date, in Handoff. A surface not approved gets a fix task appended here and only that surface is shown again (the same batch, not a new stop between tasks).
  - Acceptance: V5-A14, V5-A1, V5-A20 (the owner's real-data look).

- [ ] **X1. Cut-over (W17)**
  - Depends on: U14 approval for every region (or the owner's word to cut over without one), OQ4 answered.
  - Files: deleted, each only once `git grep` shows no remaining user: the old screens (`Loadout/` views: `LoadoutScreen`, `LoadoutTable`, `LoadoutRowView`, `LoadoutToolbar`, `LoadoutTab`, `LoadoutShots`; the old Rules page: `RulesScreen`, `RulesGrid`, `RulesList`, `RulesToolbar`, `RulesCodexPage`, `RulesConfirmation`, `RulesTab`, and `RulesAddRow` and `RulesScopes` per OQ4; Activity: `ActivityScreen`, `ActivityLane`, `ActivityRows`, `ActivitySessionRow`, `ActivityFailureRow`, `ActivityFileHistory`, `ActivityLines`; Limits: `LimitsScreen`, `LimitsSidebarBlock`; Shell: `SidebarView`, `TopBarView`); components only they used (for example `SidebarItem`, `LimitSidebarTile`, `LimitWindowTile`, `LimitFigure`, `FactTile`, `Ruler`, `UsageCell`, `UsageCellModel`, `UsageLegend`, `CLISummaryBar`, `StatusLead`, `GroupedList`, `CardHeader`, `GroupLabel`, `RowHeaders`, `CLIDot`, `ScopePicker`, the capsule `FilterChip`) and their tests (for example `RulerTests.swift`); unused `Metrics` and `Rhythm` names; the switch in `LaunchMode.swift` and its flag in `build-app.sh` and `dev.sh`. Moved with `git mv` (old and new paths listed): the still-used Loadout model files into the folder that owns them. Edited: `StyleBoundaryTests` (drop `Loadout` and the X1-only allowlist entries), `ShotRenderer`, `.github/workflows/swift.yml`, the header of `scripts/dev-fixture.sh`; [`docs/DESIGN-LANGUAGE.md`](../DESIGN-LANGUAGE.md) rewritten for the shipped language (D1); [`AGENTS.md`](../../AGENTS.md) (screen list, the design-language paragraph); the spec's status line; this plan's status.
  - Build: before deleting, list every type and file to remove with its `git grep` count; end with "changed N of M", each kept site named. Deletions are recoverable from git, but X1 still shows the list to the owner before it is pushed (W9, `CLAUDE.md` `<branching>`).
  - Verify: TEST (N falls by exactly the deleted tests, listed); BUILD; every SHOTS key with no switch (v5 is the default) pixel-compared with the U14-approved set, each difference explained; `git grep -n 'SPACEVIBE_UI_V5\|SPACEVIBE_DEV_BUILD'` empty; `git grep -n` for each deleted type empty; DOCS with no new finding; RUN without the switch shows v5.
  - Acceptance: V5-A11, V5-A12, V5-A21.

## Acceptance map

| Acceptance | Tasks |
| --- | --- |
| V5-A1 | U6 to U12 (per surface), U13, U14 |
| V5-A2 | U2 |
| V5-A3 | U1, X1 |
| V5-A4 | U3 |
| V5-A5 | U8 |
| V5-A6 | U8 to U11 |
| V5-A7 | U5, U8, U13 |
| V5-A8 | U5, U13 |
| V5-A9 | U3 |
| V5-A10 | U4, U5 |
| V5-A11 | U2, U13, X1 |
| V5-A12 | U13, X1 |
| V5-A13 | every UI task (RUN), U14 |
| V5-A14 | U14 |
| V5-A15 | U13 |
| V5-A16 | U2 |
| V5-A17 | U10 to U13 |
| V5-A18 | U7, U9 to U12 |
| V5-A19 | U7 to U13 |
| V5-A20 | U7 to U14 |
| V5-A21 | U1, X1 |
| V5-A22 | U7, U9 to U13 |
| V5-A23 | U4, U5, U7, U13 |
| V5-A24 | U7, U9 to U13 |

## Order and parallelism

- Sequential by default: U0, U1, U2, U3, U4, U5, U6, U7, then U8 to U12, U13, U14, X1.
- U8 to U12 touch different screen folders but share `AgentsPage.swift`, `ShotRenderer.swift`, `StyleBoundaryTests.swift` and the CI workflow. They run in parallel only if the owner has asked to see Limits and approved it first (UP4), and each track lands its edits to those shared files as a separate small change before its page.
- Never in parallel with the go-core S.1 on the same screen folder (G-0).

## Risks and unknowns (Hypothesis, unverified, with the deciding check)

| ID | Hypothesis | Deciding check |
| --- | --- | --- |
| H1 | Go-core S.1 and this track edit the same screen models; its pixel-identical gate breaks | G-0; `git log -5 -- Sources/Reins/<folder>` before each task |
| H2 | R1, R2 or R3 lands mid-track, so env names, the bundle id or the paths here go stale | before each task: `ls Sources`, `grep -c SPACEVIBE_ scripts/test.sh`, `/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist` |
| H3 | SwiftUI reproduces the kit's hairlines, top highlight, tinted chips, popover clamping and the collapsed two-column grid closely enough | U4 and U5 crops against the mock |
| H4 | The 28 pt Answer sentence wraps differently in the app than in Chrome, so card heights and inner scrolling differ | U7 crops and fit |
| H5 | `fg3` text on `bgRaise` misses 4.5:1 (about 3.5:1 computed from the kit values `#6B7078` on `#191A1D`), so raising it is a visible departure from the mock | U2 contrast test; the departure goes on the U14 sheet |
| H6 | A MingCute or Phosphor licence asks for more than a credit line | U3 licence read |
| H7 | The data gaps G1 to G13 leave cards or columns out | the first step of U9 to U12 |
| H8 | Light mode, never eye-checked since D66, is rejected at U14 | the agent reads the light SIDE sheets in U13 first |
| H9 | The dev-build flag leaks into a distribution build | checked when this plan was written: `scripts/release.sh` (line 81) always calls `build-app.sh --distribution`, for `--prepare` and `--notarize` alike, so the flag stays out as long as U1 adds it only outside that branch; U1 greps the branch again |
| H10 | Headless shots differ from the live window (scale, font rendering) | the owner's RUN window at U14 |
| H11 | Other sessions change the shared checkout during a task | `git status --porcelain` before each task (W11); commit only the task's paths |
| H12 | The Tokens page has no place in the frozen mock's sidebar | the Tokens plan owner, or the owner at U14 |

## Verification evidence

### Baseline (2026-11-07, before U1, HEAD 01b8712)

- `scripts/test.sh` → exit 1 before any Swift test ran: `vet: internal/activity/fold-common.go:184:3: undefined: foldCodex`, later `internal/activity/sessions.go:324:15: undefined: codexProcessID`. `core/internal/activity/`, `inventory/` and `usage/` are untracked, written by the go-core session (G2.1, G2.2) in the shared checkout; not this track's. `go build ./cmd/spacevibe` passes (the binary does not import those packages).
- Fallback `/tmp/reins-v5/swift-test.sh` → `Test run with 416 tests in 46 suites passed`. Baseline N = 416.
- G-0 check: no `Sources/Reins/Core/` (go-core S.1 not started); last `Sources/Reins` commit is 416f512 (G1.4). H2: `ls Sources` → CZstd, Reins, ReinsCore, ReinsStatusline; `grep -c SPACEVIBE_ scripts/test.sh` → 5; bundle id `dev.spacevibe.reins`.
- Mock reference set: `/tmp/reins-v5/mock/<skills|subagents|hooks|rules|activity|limits|components>-<dark|light>.png` from `capture.sh`.

### U1 (2026-11-07)

- `scripts/test.sh` (full, green) → `Test run with 426 tests in 47 suites passed`. N 416 → 426: +7 `LaunchModeTests` (name, on, off with 6 values, ignored in a distribution build, mode unchanged, debug counts as dev, build-flag check of `build-app.sh` and `release.sh`) and +3 `StyleBoundaryTests` (every folder known, lists consistent with no v5 allowlist entry, V5-R8 patterns).
- Noise of the new patterns on today's screens (`grep -nE` over Loadout, Rules, Activity, Shell, Limits, Settings for `.background(`, `.border(`, `.shadow(`, `.overlay(`, gradients, `repeatForever`) → 0 hits, so no allowlist entry; `allowed` stays empty.
- `grep -n 'DSPACEVIBE_DEV_BUILD' scripts/build-app.sh` → one line, `"") BUILD_FLAGS=(-Xswiftc -DSPACEVIBE_DEV_BUILD) ;;`, the no-argument (development) branch; `--distribution)` sets no flag. `scripts/release.sh:81` still calls `build-app.sh --distribution` (H9); `LaunchModeTests` asserts both.
- `scripts/build-app.sh` → exit 0, `minos 15.0` (app), `minos 12.0` (helper), log `/tmp/reins-v5/U1/build.log`.
- RUN without the switch (the RUN block minus `--env SPACEVIBE_UI_V5=1`) → `lsappinfo` shows `type="Foreground"`, bundle id `dev.spacevibe.reins`; `ps eww` shows the synthetic HOME and no `SPACEVIBE_UI_V5`. Nothing reads the switch yet, so the window is today's app by construction. Quit, synthetic home removed.
- Follow-up, V5-A3 gap: `[^)]*?` stopped at the first `)`, so `.overlay(alignment: .top) { Rectangle().stroke(tone) }` passed. Added two patterns, shape construction (`Rectangle|RoundedRectangle|UnevenRoundedRectangle|Capsule|Circle|Ellipse(`) and shape paint (`.stroke|strokeBorder|fill|clipShape(`), valid in a multi-line closure because each line is judged alone. Measured on today's screens before adding: 1 hit in 1 file, `Limits/LimitsSidebarBlock.swift:37` `.contentShape(Rectangle())` (a hit area, draws nothing); every other file 0. The shape pattern excludes `contentShape(` instead of putting that file in `allowed`, so a v5 row can set a hit area; `allowed` stays empty. `paintPatterns` gained the two one-liners from the review, a multi-line closure case, `clipShape` and the `contentShape` exception. `scripts/test.sh` after the follow-up → `Test run with 426 tests in 47 suites passed`; N unchanged because the new cases extend `paintPatterns` and no test was added.
- Not run: a build carrying the flag was not launched with `SPACEVIBE_UI_V5=1`, because no surface consumes `LaunchMode.uiV5Enabled` until U6.

### U2 (2026-11-07)

Shots, mock-free evidence and the derivation scripts: `/tmp/reins-v5/U2/` (`before/` and `after/` per SHOTS key, `pairs/` before beside after, `gen.py` and `report.py` for the departures).

- TEST: `scripts/test.sh` (full; the go half green) → `Test run with 433 tests in 49 suites passed`. After the last edit (the 12 and 14 pt v5 roles, which extend an existing test): test.sh red from go-core WIP in `core/internal/statusline` (untracked; `vet: statusline.go:35:11: undefined: runCapture`); Swift half (`/tmp/reins-v5/swift-test.sh`): `Test run with 433 tests in 49 suites passed`. N 426 → 433: +2 `ContrastTests` (every pair, the V5-A2 names covered), +3 `HuePolicyTests` (outside the state families, apart from each other, chroma), +2 `InterFontTests` (the v5 roles, the 450 weight axis).
- Structure: `PaletteValue` holds every colour as data (`ColorValue`: light and dark hex plus alpha) under the spec's token names; `Palette` builds the colours from it, and `ContrastTests` and `HuePolicyTests` read the same values. The old names stay as aliases of the v5 token that replaces each (`well` = `bgSide`, `surface` = `bgPanel`, `surfaceRaised` = `bgRaise`, `divider` = `hair`, `border` = `hair2`, `selection` = `sel`, `text`/`textSecondary`/`textTertiary` = `fg`/`fg2`/`fg3`, `success` = `ok`, `danger` = `bad`, `overlay` = `scrim`, `background` = `bgApp`) until X1. `border` takes `hair2`, not `hair`: the token table says both "hair replaces border" and "hair2 extends border"; every use of `border` is a `hair2` role (overlay edge, field outline) and its old light value `#DADADA` was black at 14.5%. New v5 names: `bgSunk`, `bgPop`, `bgBand`, `hair2`, `rowDivider`, `hi`, `trackHi`, `kbdBg`, `kbdBorder`, `fg4`, `accentText`, `accentBg`, `mute`, `onVerdict`, `badSolid`, the four category colours, the tab inks, `shadowPop`, `shadowDialog`; `TabChipAlpha` holds the tab chip shares. `Metrics` gains one group per v5 block (the "Rhythm and sizes" table) and `Rhythm` gains `edge` 32, `card` 24, `group` 32, `side` 16, all unused until U4. `ReinsType` gains `micro` 10, `small`/`smallLabel` 11, `meta`/`metaLabel` 12, `prose`/`rowName`/`control`/`controlStrong` 13, `field` 14, `cardTitle` 16, `heading` 20, `answer` 28, each with the mock body's `cv11`, `ss03` and tabular figures and scaled by `TypeScale`; `rowName`'s 450 is Inter's weight axis (`InterFont.Weight.book`). The spec's table maps 12 and 14 to `caption`, `label` and `body`; those keep the old features for the old screens, so `meta`, `metaLabel` and `field` carry the v5 features at the same sizes, and a v5 page never mixes the two shapes of the a.
- W21 sweep (old literals `#476EAE`, `#A4BFEB`, `#1596D6` and the 42 hex values the old `Palette` held, then every use of each changed token):
  - Tokens: changed 31 of 36 old names; kept 5 by design: `onAccent` (white), `overlayShadow` (the old overlays' shadow; v5 has `shadowPop`/`shadowDialog`), `markGround`, `markInk`, `brandMonochrome` (the app mark and brand artwork, D14).
  - Use sites: 182 reads of those 36 names outside the palette (`rg -o 'Palette\.[a-zA-Z]+' Sources Tests`); 173 of 182 now read a changed value, 9 read a kept one (`onAccent` 3, `overlayShadow` 3, `markGround`, `markInk`, `brandMonochrome` 1 each). No colour is built outside `Palette.swift` (`rg 'Color\(|NSColor' Sources/Reins`: only `NSColor.labelColor` in `Credits.swift`, the system label colour of the About panel, kept).
  - Files holding one of those literals (`git ls-files` grep, CZstd excluded): changed 2 of 15, `Sources/Reins/Tokens/Palette.swift` and `docs/DESIGN-LANGUAGE.md` (the Codex `#1596D6` pin, the blue selection and focus, the colour bullets, the ruler's empty cells). Skipped 13: `docs/specs/2026-11-03-reins-design-language.md` (historical spec, values of record), `docs/specs/2026-11-06-reins-linear-identity-decisions.md` (ledger), `docs/specs/2026-11-06-reins-design-language-v5.md` (the source), `docs/plans/2026-11-05-reins-design-language-v4.md` (superseded), this plan (the U2 text), `mocks/agents/agents-panel.css` and `mocks/agents/controls-directions.css` (`mocks/`, reference only), `site/app/globals.css` and `site/public/icon.svg` (`site/`, D14; the mark colours `#050608` and `#F4F5F7`, unchanged anyway), `site/public/landing/star-tile-far.svg`, `-mid.svg`, `-near.svg` (an unrelated `#FFFFFF`, `site/`, D14), `Resources/AppIcon.svg` (the icon, D14; the mark colours).
  - Focus ring to fill (D57): changed 5 of 5 definitions and users (`FocusRing.swift` renamed `FocusFill.swift` with `focusFill`; `reinsFocusable` and its 12 call sites; `Row`, `LimitWindowTile`, `SegmentedControl`, `TextInputField`). `Row` and `LimitWindowTile` skip the fill when selected: two stacked `sel` fills put `fg3` at 3.81:1 (dark, card).
  - `toastDuration` 7 s to 5 s: 1 of 1 use (`ToastCenter.swift:90`).
- Contrast (`ContrastTests`, 183 pairs, each in both appearances): every pair passes. Grounds are composited: each surface, `sel` (also the focus fill), `hover` and `accentBg` over the surfaces rows sit on, tab chips and count circles over `bgPanel`, tints over `bgPanel`/`bgSide`/`bgRaise`, the solid fills with the primary button's hover brightening. Departures from the spec, for the U14 sheet (spec value → built value, worst pair before → after):

  | Token | Mode | Spec → built | Worst pair, before → after |
  | --- | --- | --- | --- |
  | `fg3` | dark | `#6B7078` → `#8D929A` | text on `sel` over `bgPop` 2.85 → 4.54 (H5: on `bgRaise` 3.49 → 5.56) |
  | `fg3` | light | `#8B8F97` → `#646870` | text on `sel` over `bgSide` 2.61 → 4.51 |
  | `fg2` | light | `#5E626A` → `#595D65` | inactive tab count on its circle 4.20 → 4.54 |
  | `accentText` (new) | dark | `accent` `#4F86F7` → `#568EFF`; `accent` itself keeps shade 1 for fills and marks | toast `Undo` on `sel` over `bgPop` 4.12 → 4.54 (hovered 4.44 → 4.89) |
  | `accentSolid` | both | `accent` → `#2A5DCB` / `#1E5CD2` | white on it 3.45 → 5.95 (dark); with hover brightening 2.75 → 4.51 dark, 4.15 → 4.55 light |
  | `badSolid` (new) | both | `bad` → `#B8334C` / `#BE2C49` | white on the spec `bad` 3.43 (dark) → 5.81; with hover brightening 2.71 → 4.51 dark, 3.58 → 4.51 light |
  | `ok` | light | `#2F9E6B` → `#2A9B68` | mark on `sel` over `bgRaise` 2.89 → 3.00 |
  | `warn` | light | `#C4811A` → `#BD7A0B` | mark on `sel` over `bgRaise` 2.76 → 3.02 (on `bgBand` 2.81 → 3.07) |
  | active tab text | dark | category colour → mixed with white (category share 0.79 to 0.91; accent 0.75) | on the focused chip (34%) 3.6 → 4.5 |
  | active tab count | both | category (dark), 68% with black (light) → dark share 0.08 to 0.33 (close to `fg`), light 51% to 54% with black | on the 40% circle 2.1 → 4.5 (dark), 3.3 → 4.5 (light) |
  | `bad` | both | `#E5604F` / `#D2442F` → `#E45C6F` / `#D13F58` | OKLCH hue 29.7/31.3 → 14.7/15.1 (see Hue) |
  | `catRule` | both | `#E8709F` / `#D2487F` → `#E471AC` / `#CC4A91` | OKLCH hue 357.2/359.4 → 349.9/350.0 (see Hue) |

  Side effect: `fg3` now sits close to `fg2` (1.30:1 dark, 1.18:1 light; spec 2.06:1 and 1.89:1), so the three-step text hierarchy is nearly two steps. The `Ink` twins (old screens only) were re-derived at the new hues with the old ramp (L 0.80/C 0.07 dark, L 0.38/C 0.08 light) and pass 4.5:1 on their tints; tints are the new fill at 15%; `codexInk` and `codexTint` follow Codex's text colour.
- Hue (`HuePolicyTests`, OKLCH, state family ±20°): with the spec's values Claude's clay sat 9.1° (dark) and 7.0° (light) from `bad`, inside the danger family; `catRule` was 32.5°/31.9° from `bad` (the pair H-notes expected to be tight passed). The test cannot pass with clay, `bad` and `catRule` all at their spec hues: the warm side holds `bad`, clay and `warn` within 46° (dark) and 40° (light), so at ±20° no hue fits between `bad` and `warn` in light. Built, option A, the lead's decision of 2026-11-07 (identity stays, state moves; V5-R17, V5-R46): `bad` moved redder to hue 15 and `catRule` to hue 350, OKLCH lightness and chroma kept, named departures for U14; Claude's clay is untouched; the test stays strict (no exception list). Margins after, dark / light: `bad`–`warn` 61.1° / 55.5°, `bad`–clay 24.1° / 23.2°, `catRule`–`bad` 24.8° / 25.1°, `catRule`–`catSubagent` 25.0° / 27.1° (hues: `bad` 14.7 / 15.1, clay 38.8 / 38.3, `warn` 75.8 / 70.6, `catRule` 349.9 / 350.0). ±20° is the plan's working threshold, which the owner may move at U14; the alternative kept for that sheet is clay to hue 52.5 with light `warn` to 74 (clay turns orange). Closest non-state pair: light `catSkill` and the accent, 28.5°. Codex, `mute` and the greys are achromatic (OKLCH chroma under 0.02).
- Focus fill (V5-R40, V5-A2): the spec names no pair for "the focus fill 3:1". Read as content on the fill, it holds: the focus fill is `sel` (D57, V5-R41), so every text and mark pair on a `sel` ground above is the focused case. Read as the focused fill against the unfocused one (WCAG 2.4.13, AAA), `sel` over `bgRaise` is 1.19:1 dark and 1.13:1 light; 3:1 needs white at 33% (dark) and black at 42% (light), and then `fg2` text on a focused row falls to 2.4:1 and 2.0:1. The second reading contradicts D57's fill and the text rule, so it is not built (the lead's decision of 2026-11-07); it goes to the owner at U14 as an open accessibility trade-off. `ContrastTests` also checks that the fill changes the look from rest and stands a step above hover, both appearances: from rest 1.15 to 1.20:1 dark and 1.13:1 light, from hover 1.06 to 1.08:1 dark and 1.05:1 light (on `bgSide`, `bgPanel`, `bgRaise`, `bgPop`).
- Neutrality (V5-R2), measured, no test: every surface is within 4 (dark) and 8 (light) except dark `bgBand` `#1B1C20` (spread 5), the kit's own value.
- SHOTS, switch off, every old key in dark and light (`before/` at 0f8c9f3, `after/` with this change; `limits` needs `SPACEVIBE_FIXTURE_LIMITS=typical|edge`, the bare key fails its own check at both revisions); every shot run's own checks passed. Read on a first after-set, then the final set (after the `bad`/`catRule` move and the ruler fix) re-read for every screen that draws danger or warn: Rules invalid file, add-rule error, the Codex page, the confirmation with its warning, Loadout's dead hooks, Limits edge. Per screen:
  - Loadout, Rules, Activity, Shell (palette, toast, gallery): no truncation, no overlap, every text readable. Selection and chosen segments turn from blue to neutral `sel`; Codex bars and dots turn from blue to the text colour; the primary button and switch are a deeper blue. Dark cards on the well separate less (1.06:1, was 1.26:1). Light: controls, tags, fact tiles and segment frames inside a card are `bgRaise` `#FBFBFB` on white, 1.04:1 (was 1.12:1), so they read as plain labels; their text passes. The old screens have no borders, so the v5 hairlines that separate these in the mock are not there until each region is rebuilt.
  - Limits (typical, edge): the ruler's empty cells used `surfaceRaised` and vanished on a light card; they now use `track` (`Ruler`, `LimitWindowTile`, `docs/DESIGN-LANGUAGE.md`), as visible as before. Figures, tiles and the sidebar block read; no truncation.
  - Banners and state tiles (final set): the error banner, the warning note and the success tile read in both modes; the danger tint is a little pinker after the hue move.
  - Danger tone on the old screens after the `bad` move (D53, app-wide), final set: `after/rules/rules-invalid-{dark,light}.png` (error banner), `after/rules/rules-default-{dark,light}.png` (Deny dots), `after/rules/rules-add-error-{dark,light}.png`, `after/loadout/loadout-dead-{dark,light}.png` (script-not-found tags, the `0` in danger ink), `after/limits-edge/limits-page-{dark,light}.png` and `limits-sidebar-{dark,light}.png` (the 4% figure, ruler and tile), `after/activity/activity-default-{dark,light}.png` (failed-command dots), under `/tmp/reins-v5/U2/`; each beside its `before/` twin in `pairs/`. Taken before the accent split below, which changes only the dark system tint (`.tint`, back to shade 1) on these screens and no drawn text.
  - Settings (Appearance, System, Large, every Update state, palette, the Large font on three screens): reads in both modes; the chosen theme tile turns neutral; the font-size sample block is faint in light (same 1.04:1); no truncation at Large.
- BUILD: `scripts/build-app.sh` → exit 0, `minos 15.0` (app), `minos 12.0` (helper).
- RUN, switch off: `lsappinfo` → `type="Foreground"`, `bundleID="dev.spacevibe.reins"`; `ps eww` → the synthetic `HOME`, no `SPACEVIBE_UI_V5`. Quit; synthetic home removed. Not done: opening Settings in the live window. `osascript` has no assistive access here (`-1719`) and Computer Use is not authorized, so Settings was read in the SHOTS above (the real Settings views, every state, both modes), not in the running app.
- DOCS: `docs-compliance.sh` and `docs-anchors.sh` → exit 0, no finding.
- Follow-up, the lead's decisions (2026-11-07): hue option A kept, the test strict; focus read as content on the fill, plus a test that the fill differs from rest and from hover; white on the accent fixed in a solid token, not the shade, so `accent` dark went back to shade 1 `#4F86F7` and the text pair moved to a new `accentText` (`TextTone.accent` reads it; Activity's tab inks re-derived from shade 1: text `#7BA4F9` 4.52:1 on the focused chip, count `#C0D3FC` 4.53:1); `DESIGN-LANGUAGE.md` points to the v5 spec for the full rewrite at X1. `scripts/test.sh` (full, green) → `Test run with 434 tests in 49 suites passed`; N 433 → 434, +1 `ContrastTests` (the focus fill step). DOCS → exit 0, no finding.

### U3 (2026-11-07)

Evidence: `/tmp/reins-v5/U3/` (`pkg/` the packed sets, `lic/` the upstream licences, `scratch/compare*.mjs`, `shell/` and `shell-off/` SHOTS, `mock-glyphs-<dark|light>.png`, `SIDE-glyphs-<dark|light>.png`, `build.log`, `test1.log`).

- Glyph table (path data of the mock's sprite against `@iconify-json/mingcute` 1.2.10, `ph` 1.2.2 and `solar` 1.2.13, exact `d` equality, `compare.mjs`): `i-skill`, `i-agent`, `i-hook` are `mingcute:flash-line`, `robot-line`, `fish-symbol-line` (the sprite comment "Phosphor" is wrong for these and for `i-all` = `layers-line`); every other sprite glyph except three is the Phosphor Duotone icon of the same name, 2 of 2 paths: `stack`, `pulse`, `gauge`, `magnifying-glass`, `sliders-horizontal`, `lock`, `plus`, `x`, `check`, `trash`, `arrow-square-out`, `caret-down`, `funnel`, `file`, `sun`, `moon`, `clock`, `copy` (Activity's page-local one), `list-checks` (Rules), `terminal-window` (CLI), `arrow-elbow-down-left` (return, also the refresh button), `warning` (same outline, the light layer's path starts at another point). Three do not match: `i-stop` (Activity, page-local: a ring plus a filled rounded square; nearest `ph:stop-circle-duotone`, an outlined square), `i-bug` (page-local, drawn with an ellipse and 16-unit strokes; nearest `ph:bug-duotone`), `i-rank` (c3 and the components sheet, three stroked rectangles; nearest `ph:chart-bar-duotone`). The owner approved the nearest Phosphor icon for the three (the lead's message), each a named departure for U14.
- Sources and files: `generate-icons.mjs` now takes the three `icons.json` and writes `ReinsIconData.swift` (Solar, the old screens; every `p.` path line identical to HEAD, only the header, the protocol members and `iconName` for `solarName` changed), new `CategoryIconData.swift` (`CategoryGlyph`: `skill`, `subagent`, `hook`) and `ContentIconData.swift` (`ContentGlyph`, 25 glyphs). Phosphor is scaled from its 256 grid to the 24 box at generation; its light layer is `.2` in the set and drawn at the mock's `.25`; the mock adds an 8-unit round-joined stroke to every glyph (`system/shared.css` `.ico`), reproduced as `outlineWidth` 0.75 in the 24 box so weights match. Each type conforms to `GlyphSource`; `ReinsIcon` takes `ReinsIcon(.lock)` (Solar), `ReinsIcon(category:)` and `ReinsIcon(content:)`, because an unlabelled `.lock` would be ambiguous across sets. `IconSize.small` (12) and `Metrics.iconSmall` added; the old 22 and 20 stay for the old screens; `Chevron` is untouched.
- `VerdictGlyph` (five hexagon shapes in `fg2`, the cut-out in `onVerdict`, geometry from the kit's `v2-*` symbols in `shared.js`, constants in `Metrics.Verdict`).
- Run twice: first run `shasum` of the three files, second run `shasum -c` → three `OK`.
- TEST: `scripts/test.sh` (full, go half green, before the last two edits: the specimen's column count and `GlyphSource: Sendable`) → `Test run with 438 tests in 49 suites passed`; after them test.sh red from go-core WIP in `core/cmd/spacevibe` (`TestContract` transcripts differ; `core/cmd/spacevibe` and `core/internal/rpc` are uncommitted by the go-core session); Swift half (`/tmp/reins-v5/swift-test.sh`): `Test run with 438 tests in 49 suites passed`. Final run right before the commit: `scripts/test.sh` (full, go half green) → `Test run with 528 tests in 61 suites passed`; the go-core session's S.1/S.2 commits and untracked tests entered the shared checkout during the task (G-0 breach, reported to the lead), so 528 counts their tests too, and `IconPolicyTests` passed in every run. An earlier run on the same tree (Swift half, `/tmp/reins-v5/swift-test.sh`) had 528 tests with 1 issue in `CoreClientTests.swift:253` (a helper file `seen` not found) from the go-core session's uncommitted WIP; it did not recur, and the Icon policy suite passed in both runs. 438 passed on the tree before their edits. N for this task alone 434 (U2 follow-up 89181d4 had added one `ContrastTests` test after U2's 433) → 438: `IconPolicyTests` 5 → 9 (no SF symbol or image outside `Gallery/`, the pattern, every glyph inside its box with its layers per set, the three MingCute names of V5-R10 and the Phosphor names, verdict glyphs own and `fg2`/`onVerdict` only, v5 screen folders draw no Solar glyph, sizes, attribution per set, the licences).
- SHOTS (`SPACEVIBE_UI_V5=1`, `shell`): the gallery shot rendered blank at 16430 px (the 16384 px texture limit; the U2 gallery was 15472). `ShotRenderer` now writes `gallery` and `gallery-more` (the gallery in two halves, `ComponentGalleryContent(part:)`) and refuses an image taller than 16384 px instead of writing it blank; later tasks that add specimens must keep each half under it. The v5 icon section is in `gallery-<dark|light>.png`, below the Solar one, shown only with the switch.
- SIDE (`SIDE-glyphs-<dark|light>.png`, mock on top, app below, same 2x scale; the mock side is `mock-glyphs-*.png`, rendered by headless Chrome from the mock's own `shared.js`, since `system/components.html` has no glyph grid): shapes, weights and sizes 12, 14, 16 and 24 agree for every matched glyph in dark and light. Differences: `stop`, `bug` and `rank` (above); the warn column uses the old screens' `warnInk` in the app and `--warn` in the mock (a specimen choice, not a glyph property); the specimen names differ.
- BUILD: `scripts/build-app.sh` → exit 0, `minos 15.0` (app), `minos 12.0` (helper); `Contents/Resources/Licenses/MingCute-Apache-2.0.txt` is in the bundle and equals `Resources/Licenses/MingCute-Apache-2.0.txt` (`cmp`).
- RUN (the plan's RUN block, synthetic home): with `SPACEVIBE_UI_V5=1` and `SPACEVIBE_GALLERY=1` → `lsappinfo` shows `dev.spacevibe.reins`, `type="Foreground"`, `ps eww` shows both variables and the synthetic `HOME`; the process was still running after 7 s. Without the switch: `type="Foreground"`, no `SPACEVIBE_UI_V5` in the environment. Quit, synthetic home removed. Not run: reading the gallery's icon section in the live window; `osascript` has no assistive access and Computer Use is not authorized, so the icon section was read in the SHOTS (the same views). Without the switch the old sidebar still draws Solar (`shell-off/shell-loadout-dark.png`, pixel-identical to the with-switch shot, `compare -metric AE` = 0, since no v5 surface consumes the switch before U6) and the gallery has no v5 section (6638 px against 7980).
- Licences (V5-R15, H6), read from each set's repository: Solar CC BY 4.0 (unchanged). Phosphor MIT, `Copyright (c) 2023 Phosphor Icons`: the notice and the permission text, about 1 KB, are in `Credits.contentIcons`, as the BSD notice is. MingCute Apache-2.0 (`mingcute-design/mingcute-icons`, blob d645695, last changed in bcee804 on 2026-07-30; the upstream file is the unfilled template, with no copyright line, and the repository has no `NOTICE`): section 4(a) asks for a copy of the licence, which the About-panel form cannot hold at 11 KB beside the 2 KB BSD notice, so it went to the owner (H6); the build ships the text as `Resources/Licenses/MingCute-Apache-2.0.txt` beside Inter's `OFL.txt` and `Credits.categoryIcons` names it; section 4(b)'s "changed" note is in the generated header and the credit. The owner chose option D on 2026-11-07 (see Handoff).

### U4 (2026-11-07)

Evidence: `/tmp/reins-v5/U4/` (`shell/` SHOTS with the switch, `before-off/` and `after-off/` without it, `offdiff/`, `side/` and `side.html` for SIDE, `mock/` the components-sheet captures, `test-before.log`, `test-after.log`, `build-app.log`, `scratch/` the contrast and crop scripts).

- Blocks (`Sources/Reins/Components/`), each reading tokens only and taking values and closures, never a model or a `CoreService` type: `Tile` (header 52 with title, count, `StateMark`, 28-high actions and the collapse chevron; body `rows`, `content` or `bare`; `maxHeight` scrolls the body inside), `AnswerCard` and `VerdictBox`, `Band` and `BandStack` (closed runs stacked 10 apart, or `.grid` for Hooks; 32 above every band but the first) with `OpenStateStore`, `ListRow` and `ListRows` (dividers as container values, after `GroupedList`), `StatFigures`, `ColumnChart`; in `Cells.swift` `BarCell` (neutral, warn, danger, unknown as a dashed line), `ShareCell`, `CountCell`, `MetaCell`; in `EmptyState.swift` `QuietEmptyState` (card or list) and `LoadingSkeleton`. Shared helpers: `blockSurface(_:edge:radius:)` (fill, 1 pt edge, the `hi` top-edge highlight), `StateMark` (warn, danger, clock, lock, with its spoken label), `specimen(_:)` (hover and focus drawn for the gallery only), `lineBox(_:)` in `ReinsType.swift` (CSS line boxes for free text), `CLIMark(size: .control)` (the bare 16 pt logo). Sizes in new `Metrics` groups (`ListRow`, `Bar`, `Tile`, `Band`, `Skeleton`, `EmptyState`, `VerdictBox`, `Stats`, `ColumnChart`, `Radius.cornerStyle` circular as CSS, `Radius.edge`); `IconSize.row` (20) stays for the verdict box.
- States: fills one at a time (picked `accentBg`; current or focused `sel`; hovered `hover`), so current and focused never stack two `sel` fills (U2). Band rest `bgBand`, hovered `bgBandHover`, focused `bgBandFocus`, hovered and focused one fill. Reduced motion removes the chevron turn, the hover fades, the bar width change and the skeleton pulse (the only `repeatForever`, in `LoadingSkeleton`).
- Open-state store (V5-R55): a user's choice wins; a band shown open stays open when its default turns closed, so a write or a refresh never folds it; a band closed by default opens when its default turns open; pages are apart; `defaultOpen(holdsProblem:isFirst:pageNeedsUser:)` holds the spec's rule. In memory for the app's lifetime (`OpenStateStore.shared`, read through `@Environment(\.openStateStore)`).
- Tokens, option A, the lead's decision of 2026-11-07 (see Handoff): the mock's band hover (8% `fg` into `bgBand`) puts `fg3` at 4.38:1 dark and 4.16:1 light, so new `bgBandHover` mixes 4% dark (`#242528`) and 3% light (`#E8E9EC`), and `bgBandFocus` 6% (`#28292D`) and 4% (`#E6E7EA`). Light `warn` read 2.85:1 on a focused band and 2.62:1 as a bar on the track of a current row, so it moves `#BD7A0B` → `#B26F00` (OKLCH lightness lowered, chroma and hue kept inside the sRGB gamut; hue 70.6 → 68.7). `ContrastTests` cases 191 → 214: `fg`, `fg2`, `fg3` on both band fills; `warn`, `bad`, `claude`, `codex` on both band fills; `fg2`, `warn`, `bad` as bars on `track` over `bgRaise`, `hover` and `sel` over `bgRaise`; `HuePolicyTests` pass unchanged. Departures for the U14 sheet, in the format of U2's table (worst pair; ratios from the token values, WCAG over the composited ground; the borderline ones are the `ContrastTests` cases above):

  | Token | Mode | Mock or before → built | Worst pair, before → after |
  | --- | --- | --- | --- |
  | `bgBandHover` (new) | dark | mock `bgBand` + 8% `fg` `#2C2D31` → 4% `#242528` | `fg3` text on it 4.38 → 4.92 |
  | `bgBandHover` (new) | light | mock 8% `#DDDEE1` → 3% `#E8E9EC` | `fg3` text on it 4.16 → 4.59 |
  | `bgBandFocus` (new) | dark | mock: `sel` in place of `bgBand` → 6% `#28292D` | `fg3` text on it 4.65 (8%: 4.38) |
  | `bgBandFocus` (new) | light | mock: `sel` in place of `bgBand` (`#EEEEEE`, 1.0:1 from the band at rest, no visible focus) → 4% `#E6E7EA` | `fg3` text on it 4.50 (8%: 4.16) |
  | `warn` | light | spec `#C4811A`, U2 `#BD7A0B` → `#B26F00` | bar on `track` over a current row 2.40 (spec), 2.62 (U2) → 3.01; mark on `bgBandFocus` 2.61, 2.85 → 3.29 |
- TEST: `scripts/test.sh` (full, go half green) → `Test run with 546 tests in 64 suites passed` (`test-after.log`), against 550 before the task (`test-before.log`). This track: +6 (`OpenStateStoreTests`: problem resolved stays open, user choice wins, a new problem opens, pages apart, binding, defaults). The go-core session's Loadout and Rules cut-over in the same checkout (S.6 committed as 7f15071 during this task, the rest uncommitted: `InProcessCoreTests`, `CoreRoutingTests` renamed `CoreEnvironmentTests`, `RulesModelEngineTests`, `RulesModelTests`) changed its own tests by −10; the per-name diff of the two logs lists only those suites besides the six above. Re-run at bdbbdc7 (this task's commit, after 7f15071): `scripts/test.sh` (full, green) → `Test run with 546 tests in 64 suites passed` (`test-final.log`).
- SHOTS (`SPACEVIBE_UI_V5=1 SPACEVIBE_SHOT_SCREEN=shell`): the blocks need 4170 pt, more than either half has left (the first half reached 16086 px of 16384 with them), so the gallery gains a third part, `gallery-v5-<dark|light>.png` (8339 px; written only with the switch), after the U3 icon section; `gallery` and `gallery-more` keep 7980 and 8986 px. Each specimen is 557 wide, a card of a split page at 1440 x 900, so crops line up with the mock's. Read in dark and light: every state of the Components table for these blocks shows.
- Switch off (`before-off/` at ffc6e24 against `after-off/`, `compare -metric AE`): the 9 dark shots are pixel-identical (AE 0); the light ones differ only where `warn` or `warnTint` draws (the Activity note banner, banners and tags in `gallery-more`, warn glyphs; `offdiff/*-diff.png`), all under 2% per channel (`-fuzz 2%` gives AE 0 on Activity).
- W21 and V5-A11 for the light `warn` move: `rg 'Palette\.warn(Tint)?\b' Sources` outside `Palette.swift` → 12 reads in 10 files, all through the token, so changed 12 of 12 (old screens: `Banner` 2, `LimitFigure` 2 (`LimitTone` low fill and tint), `SegmentedControl` 1 (`SegmentReadout`), `Tag` 1, `StatusLead` 1, `InsetBox` 1 (`WarningNote`), gallery 2; v5: `StateMark`, `BarTone`); `TextTone.warn` reads `warnInk`, unchanged. No literal of the old value in `Sources` or `Tests`. SHOTS with the switch off (`off-screens/`: `limits` edge and typical, `rules`, `loadout`, `settings`, `activity`) against U2's `after/`: light differs only at warn marks and tints (the confirmation's warning note, Ask dots, the Limits low tone, the Activity note banner); the dark differences (limits, `rules-codex-project`, activity) are one line of clock-dependent text each (a reset time, a date), not colour. Read in light: no contrast, truncation or overlap problem.
  - The light shots that show the warn tone, each beside its U2 twin (still `#BD7A0B`) in `off-screens/pairs/`, AE against U2's `after/`: `rules/rules-confirm-warning-light.png` and `rules-confirm-scope-light.png` (the confirmation's warning note on `warnTint`, 92312 px each), `rules/rules-expanded-light.png`, `rules-project-light.png`, `rules-noop-light.png`, `rules-added-light.png`, `rules-add-error-light.png`, `rules-confirm-light.png` (Ask dots, 140 to 416 px), `loadout/loadout-hooks-light.png` (the "17 errors" and "3 errors" tag dots, 272 px), `limits-typical/limits-sidebar-light.png` and `limits-edge/limits-sidebar-light.png` (136 px each), `settings/large-activity-light.png` (the Activity note banner, 267142 px, under 2% per channel), `activity/activity-default-light.png` (136 px beyond the clock-dependent line its dark twin also has), and `shell/after-off/shell-activity-light.png` above. Every one reads; the amber is a step browner.
- SIDE (`side.html`, mock crop over app crop at 2x, dark and light): card header and rows (Limits Next resets), card header with a state glyph and an action (Hooks), Answer card (Activity and Limits), band open and collapsed with logo, count, state glyph and stale extras (Limits), problem band with lead-glyph rows (Hooks), the Hooks grid, band and row states on the components sheet, list rows (Skills `c3`), card rows (Activity), Stats and column chart (Activity). Heights, insets, the 34/8 divider, the current bar, fills, checkbox, band pitch (44, 10, the grid's 52), the verdict box (64 high) and the Stats columns match. Differences:
  - Mock substitutions: none in these blocks beyond sample text.
  - Named departures: band hover and focus fainter than the mock (tokens above); light `warn` darker (tokens above); `fg3` lighter in the chart bars and counts (U2's `fg3`); the Hooks grid sits 32 below an open band (spec "32 above a band"), where the mock page's own CSS puts 16 (`b-hooks` `.bands{margin-top:16px}`, like S6); the band's state glyph sits 12 after the count, the 4 extra that `b-limits` and `b-hooks` add in page CSS moved into the block.
  - Not this task: header actions and fix buttons in the specimens are today's `ReinsButtonStyle` (28, no edge); the v5 buttons with their edge and key caps are U5, as are the logo strip and the warning slot (specimens hold a 24 slot).
  - Rendering (H10): light text on dark renders heavier in the headless shot than in Chrome (row names at 450 look near 600); advances match the mock to the pixel, so the weight axis applies; dark text on light matches. The live window decides at U14.
- BUILD: `scripts/build-app.sh` → exit 0, `minos 15.0` (app), `minos 12.0` (helper).
- RUN (RUN block plus `--env SPACEVIBE_GALLERY=1`): `lsappinfo` → `bundleID="dev.spacevibe.reins"`, `type="Foreground"`; `ps eww` → the synthetic `HOME`, `SPACEVIBE_UI_V5=1`, `SPACEVIBE_GALLERY=1`; still running after 24 s. A first launch was gone after 7 s with no crash report while the go-core session was running its own `Reins` processes in the same checkout; the second launch stayed up. Quit; synthetic home removed. Not run: hover, current row, focus and collapse in the live window (no assistive access, Computer Use not authorized); they are drawn as static specimens in the SHOTS through `specimen(_:)` and `OpenStateStore` bindings.

## Handoff

- Date: 2026-11-07
- Progress (task, commit): U0 closed (6fd9f45); U1 done (af3f28b, 0f8c9f3); U2 done (89181d4 and earlier); U3 done (407cb5f); U4 done (this commit, `feat(components): v5 container blocks (U4)`).
- Checkout, branch, PR: `spacevibe-reins` on `main`, shared with the go-core session (uncommitted `core/` work); no PR.
- Observed verification (N tests before and after, shot folders, trace tables): baseline N = 416 (Swift half; see "Baseline"); after U1 N = 426 (`scripts/test.sh`, full); after U2 N = 434 (full, with the follow-up); after U3 N = 438 for the Swift tests of this track, 528 in the shared checkout at commit time (full); after U4 N = 444 for this track (+6), 546 in the shared checkout (full, green; 550 before, the go-core WIP −10). U2 shots: `/tmp/reins-v5/U2/`; U3: `/tmp/reins-v5/U3/`; U4: `/tmp/reins-v5/U4/`.
- Remaining work: U5 to U13, then U14.
- For U14 (from U2): the token departures table under "U2" (contrast and hue), the focus-fill reading, `fg3` close to `fg2`, and light controls inside cards on the old screens reading as plain labels until their region is rebuilt.
- For U4 and U5 (from U2): band hover is not a token yet; a band-hover fill must keep `fg3` at 4.5:1 (`ContrastTests` has no band-hover ground). A v5 row that is both current and focused must not stack two `sel` fills (`fg3` 3.81:1). v5 text at 12 and 14 uses `meta`, `metaLabel` and `field`, not `caption`, `label` and `body`.
- For U4 onward (from U3): a gallery image over 16384 px renders blank (the shot harness now refuses it); keep each half of the gallery under it. Glyphs: `ReinsIcon(category:)`, `ReinsIcon(content:)`, `VerdictGlyph`; a block that takes an icon takes `any GlyphSource` (or `ContentGlyph`), never `ReinsGlyph`; `IconPolicyTests` fails if a v5 screen folder names a Solar glyph.
- For U14 (from U3): departures `stop`, `bug`, `rank` (nearest Phosphor icon where the mock hand-drew its own); Phosphor's light layer at the mock's 25%, with the mock's thin outline reproduced.
- For U5 onward (from U4): pages build cards with `Tile` (or `AnswerCard`), rows with `ListRows { ListRow(...) }`, bands with `BandStack { Band(...) }` and their open state from `@Environment(\.openStateStore)` keyed by page and band id, the default from `OpenStateStore.defaultOpen`. Header actions and Answer fixes are slots: U5's 28 and 32 v5 buttons go there. U5's warning slot reuses `StateMark`; its popover, menu, toast and dialog surfaces use `blockSurface(Palette.bgPop, edge: Palette.hair2)` plus their shadow. Gallery specimens draw hover and focus with `.specimen(_:)`. The gallery's third part (`gallery-v5`) is at 8339 px of 16384: U5's specimens fit below the containers or go in a fourth part. Free text in v5 blocks takes `.lineBox(role)` so its height matches the kit's line boxes. The card's collapse chevron is 16 (a control in a 28 button, as the mock); a band's is 12 (V5-R16).
- For U14 (from U4): the token departures table under "U4" (band hover and focus fainter than the mock's 8%, light `warn` `#B26F00`, with before and after ratios); the Hooks grid 32 under an open band (spec) against the mock page's 16; the verdict box's glyph at 20 as the mock draws it, outside V5-R16's list of sizes.
- Blockers: 2026-11-07: go-core S.1a, S.2, S.1b, S.1c committed (c6079c2, 14a3064, 9542400, a34c8bc) while this track ran, against G-0; track paused after U3 for the owner. Resumed at U4 after the owner's answer (below): S.1 finished at 88e6e59 (S.1e; `git grep -l 'import ReinsCore' -- Sources/Reins` → only `Sources/Reins/Core/InProcessCore.swift`; the go-core plan's S.1 box is not ticked), and go-core S.3 landed at 9c97706. Before each task the orchestrator checks that the go-core session's uncommitted files do not overlap the task's files. `scripts/test.sh` was green at U1 (the go-core WIP vetted); if it goes red again from `core/internal/`, use the TEST fallback.
- Owner decisions recorded (G-0, G-1, G-2, OQ1 to OQ9, per-surface approval):
  - G-0 (2026-11-07): "G-0 làm UI trước go-core S.1 hoặc sau S.8, không chạy song song". S.1 had not started, so this track runs now and go-core S.1 waits until it ends.
  - G-0 follow-up (2026-11-07), after go-core S.1 started while U3 ran: the owner chose "Chờ S.1 xong" (resume U4 once go-core has committed S.1 for every screen; S.2 to S.7 touch models and `AppEnvironment`, v5 views only read models; overlap checked before each task).
  - G-1 (2026-11-07): "G-1 đã xem bảng truy vết".
  - G-2 (2026-11-07): "G-2 duyệt track (mỗi thay đổi nhỏ đã kiểm chứng được push và merge không cần hỏi)". The owner also said: "Hỏi trước khi làm X1, release, deploy".
  - U3 licence (2026-11-07): MingCute's Apache-2.0 section 4(a) asks for a copy of the licence; the owner chose option D, "File trong bundle": the verbatim text as `Resources/Licenses/MingCute-Apache-2.0.txt`, copied into `Contents/Resources/Licenses/` by `build-app.sh`, a one-line credit in `Credits.swift` naming it, and the Phosphor MIT notice in `Credits.swift`.
  - Execution (2026-11-07): one subagent per task, in order; shots by headless Chrome or SHOTS, never the Playwright MCP.
  - U4 tokens (2026-11-07), the lead: option A, final: `bgBandHover` and `bgBandFocus` (one fill, never stacked), light `warn` lowered in lightness only to the first value that reads 3:1 on the band focus fill and as a bar on `track` over a current row, the `ContrastTests` pairs, and both rows on the U14 departures table. Rejected: B (bars out of the pairs, `warn` to about `#B87600`) and C (band count in `fg2`, the mock's 8% hover kept).
- Follow-ups outside this plan: pointers from the Agents plan (A8, A10, A12) and the v4 plan (V2 to V8) to this plan; the 2026-11-03 spec's "v4 changes" marked superseded; PRODUCT.md's primary-datum line if open question 1 keeps 28; the go-core plan's D-5 answer recorded in its ledger.

/goal Build Reins UI v5 per docs/specs/2026-11-06-reins-design-language-v5.md and docs/plans/2026-11-07-reins-ui-v5-build.md: after the U0 gates (go-core D-5 answered, the W20 table shown, track approved), do U1 to U13 in order on main, one commit each, every v5 surface behind SPACEVIBE_UI_V5 (debug or non-distribution builds only) with the old app as the default. Done means scripts/test.sh passes with N above the starting count, including the contrast, hue, style-boundary, icon-policy, launch-mode, Answer and write tests against TempHome; scripts/build-app.sh prints minos 15.0; shots of every page and every V5-R62 state exist in dark and light beside the frozen mock, and the V5-A20 real-data trace, the V5-A22 fit and the V5-A23 conformance results are pasted in the plan. Stop at U14 for the owner's one batch eye approval, comparing each surface with the mock in dark and light; X1 cut-over, push, merge and release need the owner. Never touch the real ~/.claude or ~/.codex.
