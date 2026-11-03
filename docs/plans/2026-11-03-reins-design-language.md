# Reins: design language and component base

Spec: [2026-11-03-reins-design-language.md](../specs/2026-11-03-reins-design-language.md) (acceptance criteria DL1 to DL6).
Parent plan: [the SwiftUI plan](2026-11-02-reins-swiftui.md), whose packaging and cut-over phases still apply.
Mock: `~/scratch/spacevibe-reins/design-language/index.html` on the owner's Mac (outside git), with screenshots in `shots/v2-*` and `shots/inter-*` beside it and the Codex review in `codex-review.md`.
Status: approach proposed 2026-11-03, waiting for the owner's go and the T0 decision. No Swift written.

## Approach

Tokens first, then the components that read them, then one screen at a time. Each commit leaves every screen consistent, because a release script landed on 2026-11-03 (`04db6a1`) and `main` may be packaged at any point.

```
Sources/Reins/Tokens/      Metrics.swift (Space, Height, Radius, widths), ReinsType.swift (roles, tracking, line boxes, features), Palette.swift (+ well)
Sources/Reins/Components/  every visual decision; screens only compose these
Resources/Fonts/           InterVariable.ttf, OFL.txt (copied into the .app by build-app.sh)
Tests/ReinsTests/          StyleBoundaryTests (the policy test and its allowlist)
```

Facts this plan rests on, read 2026-11-03:

- Screens style themselves today: `.font(` appears 3 times in `Loadout/`, 16 in `Rules/`, 12 in `Activity/` and 15 in `Shell/`; `Palette.` 8, 29, 18 and 43 times. A restyle of any role currently means editing those files, which is what DL3 removes.
- `ReinsFont` has no literal outside [`Metrics.swift`](../../Sources/Reins/Tokens/Metrics.swift), so the type migration is one file plus the components that pick a role.
- The Swift app has no tags and S7/S8 of the parent plan are open: no one runs it yet, so no dev-only switch is needed (W17's purpose is to protect users of the old surface). Ordering the commits is enough.
- [`build-app.sh`](../../scripts/build-app.sh) copies only the binary, `Info.plist`, Sparkle and a rendered icon into the bundle; `Package.swift` declares no resources. The font needs its own copy step and a registration call (T1).
- The real screens have every action the mock draws: Loadout add and remove per CLI, Rules "Remove rule" ([RulesList.swift](../../Sources/Reins/Rules/RulesList.swift)), Activity Stop ([ActivitySessionRow.swift](../../Sources/Reins/Activity/ActivitySessionRow.swift)). No control is added.
- The [Tokens plan](2026-11-03-reins-tokens.md) runs on the cloud. Its T5 and T6 would add `ReinsFont` steps and a new screen; they now wait for T2 to T4 here, take their roles from the spec (`figure` for the leading number) and fall under the policy test. The dismissible `FilterChip` moves to T4 here.

## Decisions made in this plan (reversible)

- **The font registers at launch with `CTFontManagerRegisterFontsForURL(.process)`**, from `Bundle.main.resourceURL/Fonts` inside the `.app` and from the repo's `Resources/Fonts` for the bare binary that `dev-fixture.sh` runs. No SwiftPM resource bundle: inside an `.app` its default location is beside the bundle root, which code signing rejects (to confirm in T1).
- **A text role is one value** (`ReinsType`: size, weight, line box, tracking, features) applied by one modifier, `.reinsText(_:)`. Screens never call `.font(`.
- **The policy test reads source text**, not the view tree: it is cheap, runs in `scripts/test.sh`, and the forbidden patterns are lexical. Its allowlist holds a count per file and may only shrink.
- **Shell counts as a screen folder** for the policy test (it draws the sidebar, top bar and hint bar), so their styling moves into components too. `Gallery/` is exempt: it lays out specimens.

## Where each task runs

All tasks run on this Mac: SwiftUI compiles on macOS only, and the shot harness needs the window server. The cloud CI (`.github/workflows/swift.yml`) only sees this work after a push, which needs the owner's approval.

## Tasks

- [ ] T0 Clean base. About 20 files under `Sources/Reins` (and their tests) hold an uncommitted refactor from another session, last touched 2026-11-03 15:00 to 15:13: `CLIKind` replaced by `ReinsCore.InventoryCLI` with its colours moved to `CLIStyle.swift`, and one shared `ScopePicker` replacing the Loadout and Rules copies. `scripts/test.sh` passes on it (317 tests). Commit it as its own `refactor(app)` commit with the owner's OK, or wait for its owner, before any task below edits those files. The uncommitted Electron files stay as they are until S8.3 of the parent plan.
- [ ] T1 Font spike (DL1). In one throwaway render on this toolchain, settle: whether CoreText accepts the `.woff2` the owner already has or needs `InterVariable.ttf` from the official Inter release (downloaded into its own empty folder, `OFL.txt` kept beside it); registration in the `.app`, the bare binary and `ImageRenderer` shots; three distinct weights 400, 500, 600 through `Font.custom` with `.weight(_:)`; tabular digits through `.monospacedDigit()`; `ss02` and `zero` through a `CTFontDescriptor` feature setting wrapped in `Font(ctFont)`; Inter's ascender, descender and leading measured with `NSFont` at 12, 14, 16 and 24, which give each role's `lineSpacing` and single-line frame height. Record the numbers here. Then `build-app.sh` copies `Resources/Fonts` into `Contents/Resources/Fonts` before signing, and a test fails when the font does not register.
- [ ] T2 Tokens (DL2). `ReinsType` roles from the spec table and `.reinsText(_:)`; `Space`, `Height`, `Radius` and the fixed widths in `Metrics.swift`; `Palette.well`. Every existing `ReinsFont` use maps to a role (the old-to-new map is the mock's "Bảng đổi token"); the old sizes and the "13 pt base, system font" header go. One commit: every screen changes at once and stays consistent.
- [ ] T3 Policy test (DL3). `StyleBoundaryTests` scans `Sources/Reins/{Loadout,Rules,Activity,Shell}` (and `TokenUsage` when it exists) for `Font.system`, `.font(`, `Palette.`, `Color(`, `cornerRadius:` and numeric literals in `.padding(`, `spacing:` and `.frame(width:` / `height:`. Seed the allowlist with today's count per file; the test fails when a count rises or a new file has any.
- [ ] T4 Base components (DL4, DL5). Update or add, each with every state in the gallery: `Tag` (state tones, running = success with dot), `Count`, `Kbd`, `FilterChip` (plus the dismissible variant), `SegmentedControl` (reserved 600 width), button styles (ghost, icon with CLI badge), `ScopePicker`, `SearchField` (out of `TopBarView`), `Card` and `CardHeader` (replacing `GroupedList`'s header use, `HeadRow` and `GroupLabel`), `SectionRow`, `Row` (48, inset separators, tall variant), `RowText` (`rowTitle`, `codeTitle`, `code`), `UsageCell`, `UsageLegend` (with a note slot), `StateCell`, `NoteRegion`, `Banner`, `EmptyState`, `Toast`, `HintBar`, `PageLayout` (rhythm tiers and the `well`). One commit per small group; screens keep compiling and stay consistent.
- [ ] T5 Loadout on the components: three cards, actions column 60, ghost Add, the note in the legend. Its allowlist entries reach zero.
- [ ] T6 Rules on the components: tags after patterns, section spacing, no separators under section rows. Allowlist zero.
- [ ] T7 Activity on the components: state column 120, Stop icon, failure rows, the shared notes region. Allowlist zero.
- [ ] T8 Shell on the components: sidebar, top bar 48, hint bar 32 on `well`, palette and toast radii. Allowlist zero, so the allowlist is empty (DL3).
- [ ] T9 Living docs. `docs/DESIGN-LANGUAGE.md` (roles, scales, component list, the "screens compose components" rule and the policy test that enforces it); a line in `AGENTS.md` pointing to it and to Inter's licence; `Metrics.swift` and component doc comments match. Run `bash ~/.claude/scripts/docs-compliance.sh` and `bash ~/.claude/scripts/docs-anchors.sh`.
- [ ] T10 Verification (DL1, DL5, DL6). `scripts/test.sh`; `scripts/build-app.sh` with `minos 15.0` and the font inside the signed bundle; `REINS_SHOT_SCREEN=shell|loadout|rules|activity scripts/dev-fixture.sh --shots ~/scratch/spacevibe-reins/shots/ds-after/<screen>` in both appearances; each shot compared side by side with the mock's v2 screen and the gallery shot checked for every component. Record results here.
- [ ] T11 Owner eye approval (DL5). Open the after-shots, the gallery and the mock in one batch. This is the only eye gate in this plan.

## Acceptance criteria → tasks

| Criterion | Tasks |
| --- | --- |
| DL1 Inter everywhere, registered in `.app` and bare binary | T1, T2, T10 |
| DL2 roles only, sizes 12/14/16 plus `figure` | T2 |
| DL3 policy test, empty allowlist | T3, T5 to T8 |
| DL4 one token restyles every screen | T4 (shown in the gallery) |
| DL5 gallery complete, screens match mock v2 | T4, T10, T11 |
| DL6 tests pass, `minos 15.0`, font signed in bundle | T1, T10 |

## Handoff

- Checkout: `main` at `04db6a1` plus the uncommitted work described in T0. Nothing of this plan is written beyond this file and the spec.
- Next: the owner's decision on T0, then T1.

`/goal` Deliver the Reins design language per docs/specs/2026-11-03-reins-design-language.md: complete docs/plans/2026-11-03-reins-design-language.md T0 to T11 so that DL1 to DL6 hold, with Inter as the only bundled font, text roles at 12/14/16 plus `figure`, a policy test whose screen-folder allowlist is empty, a complete component gallery, fixture screenshots of every screen in both appearances compared with mock v2, and each task's evidence recorded under it; stop and ask at T0, at the owner's eye approval in T11, and before any push, merge or release.
