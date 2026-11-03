# Reins design language

How the SwiftUI app looks, and the one rule that keeps it consistent. Decisions and their reasons:
[the design-language spec](specs/2026-11-03-reins-design-language.md).

## The rule: screens compose components

Every visual decision lives in [`Sources/Reins/Tokens`](../Sources/Reins/Tokens) and
[`Sources/Reins/Components`](../Sources/Reins/Components). Screen folders (`Loadout`, `Rules`, `Activity`, `Shell`, and
`TokenUsage` when it exists) only arrange those pieces. They contain no `.font(`, no `Palette.`, no `Color(`, no
`cornerRadius:` and no non-zero number in `.padding`, `spacing:` or `.frame(width:/height:)`.
[`StyleBoundaryTests`](../Tests/ReinsTests/StyleBoundaryTests.swift) reads the source and fails on any such literal, so a
restyle is an edit to a token or a component, never to a screen. A screen that needs something new gets a component
first, shown in the gallery.

`Gallery/` is exempt: it lays out specimens. See everything with `REINS_GALLERY=1 scripts/dev-fixture.sh`, or as PNGs
with `REINS_SHOT_SCREEN=shell scripts/dev-fixture.sh --shots <dir>` (`gallery-dark.png`, `gallery-light.png`).

## Type

- **Inter 4 variable is the only face**, for prose, numbers and machine strings alike
  ([`InterFont`](../Sources/Reins/Tokens/InterFont.swift), `Resources/Fonts/InterVariable.woff2` with its `OFL.txt`).
  It registers per process on first use: from `Contents/Resources/Fonts` in the app
  ([`build-app.sh`](../scripts/build-app.sh) copies it before signing) and, in debug builds only, from the checkout.
- **Sizes 12, 14 and 16**, plus `figure` (24) for one leading number per Tokens card. Each role in
  [`ReinsType`](../Sources/Reins/Tokens/ReinsType.swift) fixes size, weight (400, 500, 600), line box (16, 20, 24) and
  tracking. Views take a role with `.reinsText(_:tone:)` and a colour by meaning with `TextTone`.
- **Hierarchy within a size comes from weight and tone.** Card title `title` 16/600, row name `rowTitle` 14/500, second
  line `caption` 12 in the tertiary tone.
- **Machine strings stay Inter** with `ss02` and `zero` on (`code`, `codeTitle`, `codeBody`): slashed zero, distinct l,
  I and 1. Prose never uses them.
- **Tabular digits only where numbers line up** (`number`, `count`, `figure`). Inter's `tnum` also widens the hyphen, so
  it is off for prose.

## Space, size, colour

- **Spacing** is [`Space`](../Sources/Reins/Tokens/Metrics.swift): 2, 4, 6, 8, 12, 16, 24, 32, with 2 and 6 only inside a
  component. Between blocks use `Rhythm`: cards 24, regions 32, two cards in one Activity lane 16.
- **Heights**: 20 tag and key cap, 24 segment, 28 every control, 32 sidebar item, section row and hint bar, 36 palette row,
  48 every row, card header and the top bar. **Radii**: 4 tag, 6 segment, 8 control, 12 card; filter chips are capsules.
- **Colour** values live in [`Palette`](../Sources/Reins/Tokens/Palette.swift). Cards (`surface`) sit on the `well`, one
  step darker in light, so each card reads as a block. CLI colours mark identity only; state uses the success, warn and
  danger tones. Elevation is a border, except overlays (palette, confirmations, toast).

## Components

| Need | Component |
| --- | --- |
| A group of rows | [`GroupedList`](../Sources/Reins/Components/GroupedList.swift) (a card) with a [`CardHeader`](../Sources/Reins/Components/CardHeader.swift) as its first line; `SectionRow` for a sub-group; `.pinnedCardTop()` with `GroupedList(edges: .belowPinnedHeader)` for a header that stays put while rows scroll |
| One line | [`Row`](../Sources/Reins/Components/Row.swift) (48, `tall` for three lines or more) with [`RowText`](../Sources/Reins/Components/RowText.swift), `EmptyRow`, `ShowMoreRow` |
| Cells | `UsageCell`, `NumberCell`, `StateCell`, `FixedCell`, `EmptyActionSlot`, `ReadOnlyMark`, `ColumnSpacer` ([Cells](../Sources/Reins/Components/Cells.swift)) |
| Labels | `Tag` (state tones; success carries a dot), `CLITag`, `CLIDot`, `Count`, `Kbd` |
| Controls | `ReinsButtonStyle` kinds (normal, primary, danger, ghost, icon, plainIcon, inverse), `RowActionButton` (with a CLI badge), `SegmentedControl`, `FilterChip` (and its dismissible form), `ScopePicker`, `SearchField`, `TextInputField` |
| Messages | `Banner`, `EmptyState`, `NoteRegion`, `InsetBox`, `WarningNote`, `UsageLegend`, `ToastView`, `ConfirmationDialog` |
| Page and shell | `PageLayout` (or `.pageTools()`, `.pageContent()`, `.pageBackground()`), `HintBar`, `SidebarItem` with `.sidebarSurface()`, `PaletteCard` and its parts, `Scrim` |

## Traps

- `Font.custom("Inter", …)` silently falls back to the system font: the family is `Inter Variable`. Build fonts only
  through `ReinsType`, which creates them by PostScript name.
- `@Entry` needs SwiftUI's macro plugin, which the Command Line Tools lack; container and environment keys are written out.
- Fixed widths that hold text were measured in Inter at these sizes (usage number 52, cost 72, state 120, Rules' Claude
  Code column 280). Recheck them when a role's size or weight changes.
