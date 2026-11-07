# Reins: UI v5 build

Spec: [design language v5](../specs/2026-11-06-reins-design-language-v5.md): requirements V5-R1 to V5-R76, acceptance V5-A1 to V5-A24, the traceability table for ledger D1 to D68, the open questions and the data gaps (G1 to G13). This plan does not restate them.
Reference: the frozen mock at `~/scratch/spacevibe-reins/linear-directions/` (outside git, F4); see the spec's "Reference mock".
Checkout: `spacevibe-reins` on `main`, shared with other sessions. When this plan was written the go-core rename R1 (`REINS_*` to `SPACEVIBE_*`) was being applied, uncommitted, in the same checkout. Commit with `git commit -- <paths>` only (W11).
Started 2026-11-07. Status: U0 closed 2026-11-07 (see Handoff); U1 next.

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

- [ ] **U2. Token values and the new tokens**
  - Files: [`Palette.swift`](../../Sources/Reins/Tokens/Palette.swift) (the spec's colour values, app-wide); [`Metrics.swift`](../../Sources/Reins/Tokens/Metrics.swift) (the rhythm table's sizes as new names beside the old; `toastDuration` 5 s); [`PageLayout.swift`](../../Sources/Reins/Components/PageLayout.swift) (`Rhythm`: edge 32, card 24, group 32, side 16 as new names); [`ReinsType.swift`](../../Sources/Reins/Tokens/ReinsType.swift) (roles 10, 11, 13, 16, 20, 28 per the spec's type table; `TypeScale` keeps scaling them); [`FocusRing.swift`](../../Sources/Reins/Components/FocusRing.swift) (focus as a fill, D57); new `Tests/ReinsTests/ContrastTests.swift`; new `Tests/ReinsTests/HuePolicyTests.swift`.
  - Depends on: U1.
  - Build:
    - W21 first: search the repo for every old colour literal (`#476EAE`, `#A4BFEB`, `#1596D6` and each value `Palette` holds today) and every use of each changed token; end with "changed N of M", the skipped sites named (`site/` per D14, `mocks/`, frozen specs and plans).
    - Contrast: composite each translucent token over its real ground; check the V5-A2 pairs at 4.5:1 for text and 3:1 for meaning-carrying marks, both appearances; a miss is fixed in the token. Risk H5 expects `fg3` text on `bgRaise` to miss.
    - Hue: state families are ±20° of hue around `ok`, `warn` and `bad` in OKLCH (the working threshold; the owner's eye at U14 may move it); categories, CLI identity and the accent must sit outside and apart (V5-A16).
  - Verify: TEST; shots of every old screen and Settings with the switch off (`SPACEVIBE_SHOT_SCREEN=shell|loadout|rules|activity|limits|settings`, dark and light) read for contrast, truncation and overlap; RUN with the switch off (Settings opens and reads).
  - Acceptance: V5-A2, V5-A11 (token part), V5-A16; V5-R2 to V5-R7, V5-R11, V5-R41, V5-R46.

- [ ] **U3. Icons**
  - Files: [`scripts/generate-icons.mjs`](../../scripts/generate-icons.mjs) (new sources: MingCute Line for the category glyphs; the content and sidebar glyph family of open question 6, including the stop, copy and bug glyphs Activity drew page-locally); [`ReinsIconData.swift`](../../Sources/Reins/Components/ReinsIconData.swift) (regenerated, never edited by hand); [`ReinsIcon.swift`](../../Sources/Reins/Components/ReinsIcon.swift) (more than one source; size 12 for chevrons, checks and the chip close); new `Sources/Reins/Components/VerdictGlyph.swift` (the five hexagon glyphs drawn as shapes, one neutral colour); [`IconPolicyTests.swift`](../../Tests/ReinsTests/IconPolicyTests.swift); [`Credits.swift`](../../Sources/Reins/App/Credits.swift).
  - Depends on: U2.
  - Build: first compare the mock sprite (`system/shared.js` lines 83 to 116) with `@iconify-json/mingcute` and `@iconify-json/ph` (`npm pack` into a scratch folder, never committed, as AGENTS.md says for Solar) to settle which family each glyph is (spec V5-R10, C13); read each set's licence in its repository and record it in `Credits` (V5-R15). If a licence asks for more than a credit, stop and ask the owner (risk H6).
  - Verify: `node scripts/generate-icons.mjs <icons.json>` run twice, the second gives no diff; TEST; gallery shots (`SPACEVIBE_SHOT_SCREEN=shell`) beside `system/components.html` in MOCK; RUN with `SPACEVIBE_GALLERY=1` added (the gallery's icon section in the live window) and once without the switch (the old sidebar still draws its glyphs).
  - Acceptance: V5-A4, V5-A9; V5-R9, V5-R10, V5-R12, V5-R14 to V5-R16.

- [ ] **U4. Shared blocks: containers**
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

## Handoff

- Date: 2026-11-07
- Progress (task, commit): U0 closed (6fd9f45); U1 done (this commit).
- Checkout, branch, PR: `spacevibe-reins` on `main`, shared with the go-core session (uncommitted `core/` work); no PR.
- Observed verification (N tests before and after, shot folders, trace tables): baseline N = 416 (Swift half; see "Baseline"); after U1 N = 426 (`scripts/test.sh`, full).
- Remaining work: U2 to U13, then U14.
- Blockers: none. `scripts/test.sh` was green at U1 (the go-core WIP vetted); if it goes red again from `core/internal/`, use the TEST fallback.
- Owner decisions recorded (G-0, G-1, G-2, OQ1 to OQ9, per-surface approval):
  - G-0 (2026-11-07): "G-0 làm UI trước go-core S.1 hoặc sau S.8, không chạy song song". S.1 had not started, so this track runs now and go-core S.1 waits until it ends.
  - G-1 (2026-11-07): "G-1 đã xem bảng truy vết".
  - G-2 (2026-11-07): "G-2 duyệt track (mỗi thay đổi nhỏ đã kiểm chứng được push và merge không cần hỏi)". The owner also said: "Hỏi trước khi làm X1, release, deploy".
  - Execution (2026-11-07): one subagent per task, in order; shots by headless Chrome or SHOTS, never the Playwright MCP.
- Follow-ups outside this plan: pointers from the Agents plan (A8, A10, A12) and the v4 plan (V2 to V8) to this plan; the 2026-11-03 spec's "v4 changes" marked superseded; PRODUCT.md's primary-datum line if open question 1 keeps 28; the go-core plan's D-5 answer recorded in its ledger.

/goal Build Reins UI v5 per docs/specs/2026-11-06-reins-design-language-v5.md and docs/plans/2026-11-07-reins-ui-v5-build.md: after the U0 gates (go-core D-5 answered, the W20 table shown, track approved), do U1 to U13 in order on main, one commit each, every v5 surface behind SPACEVIBE_UI_V5 (debug or non-distribution builds only) with the old app as the default. Done means scripts/test.sh passes with N above the starting count, including the contrast, hue, style-boundary, icon-policy, launch-mode, Answer and write tests against TempHome; scripts/build-app.sh prints minos 15.0; shots of every page and every V5-R62 state exist in dark and light beside the frozen mock, and the V5-A20 real-data trace, the V5-A22 fit and the V5-A23 conformance results are pasted in the plan. Stop at U14 for the owner's one batch eye approval, comparing each surface with the mock in dark and light; X1 cut-over, push, merge and release need the owner. Never touch the real ~/.claude or ~/.codex.
