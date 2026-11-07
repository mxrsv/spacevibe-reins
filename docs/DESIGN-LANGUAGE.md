# Reins design language

How the SwiftUI app looks, and the one rule that keeps it consistent. Decisions and their reasons:
[the design-language spec](specs/2026-11-03-reins-design-language.md).

## The rule: screens compose components

Every visual decision lives in [`Sources/SpaceVibe/Tokens`](../Sources/SpaceVibe/Tokens) and
[`Sources/SpaceVibe/Components`](../Sources/SpaceVibe/Components). Screen folders (`Loadout`, `Rules`, `Activity`, `Shell`, `Limits`,
`Settings`, and `TokenUsage` when it exists) only arrange those pieces. They contain no `.font(`, no `Palette.`, no `Color(`, no
`cornerRadius:` and no non-zero number in `.padding`, `spacing:` or `.frame(width:/height:)`.
[`StyleBoundaryTests`](../Tests/SpaceVibeTests/StyleBoundaryTests.swift) reads the source and fails on any such literal, so a
restyle is an edit to a token or a component, never to a screen. A screen that needs something new gets a component
first, shown in the gallery.

`Gallery/` is exempt: it lays out specimens. See everything with `SPACEVIBE_GALLERY=1 scripts/dev-fixture.sh`, or as PNGs
with `SPACEVIBE_SHOT_SCREEN=shell scripts/dev-fixture.sh --shots <dir>` (`gallery-dark.png`, `gallery-light.png`).

## Type

- **Inter 4 variable is the only face**, for prose, numbers and machine strings alike
  ([`InterFont`](../Sources/SpaceVibe/Tokens/InterFont.swift), `Resources/Fonts/InterVariable.woff2` with its `OFL.txt`).
  It registers per process on first use: from `Contents/Resources/Fonts` in the app
  ([`build-app.sh`](../scripts/build-app.sh) copies it before signing) and, in debug builds only, from the checkout.
- **Sizes 12, 14 and 16**, plus `figure` (24) for one leading number per Tokens card and `display` (72, line box 88) for the share left on the Limits page. Each role in
  [`ReinsType`](../Sources/SpaceVibe/Tokens/ReinsType.swift) fixes size, weight (400, 500, 600), line box (16, 20, 24) and
  tracking. Views take a role with `.reinsText(_:tone:)` and a colour by meaning with `TextTone`.
- **Settings > Font size moves 12, 14 and 16 together** by one point (Small 11/13/15, Large 13/15/17) across the whole
  app, at once: every role reads [`TypeScale`](../Sources/SpaceVibe/Tokens/TypeScale.swift), so a view that uses a role
  re-renders when it changes. Line boxes, spacing, icons, `figure` and `display` stay. Never build a role as a stored
  constant outside `ReinsType`: it would keep the size it had when it was made.
- **Hierarchy within a size comes from weight and tone.** Card title `title` 16/600, row name `rowTitle` 14/500, second
  line `caption` 12 in the tertiary tone.
- **Machine strings stay Inter** with `ss02` and `zero` on (`code`, `codeTitle`, `codeBody`): slashed zero, distinct l,
  I and 1. Prose never uses them.
- **Tabular digits only where numbers line up** (`number`, `count`, `figure`). Inter's `tnum` also widens the hyphen, so
  it is off for prose.

## Space, size, colour

- **Spacing** is [`Space`](../Sources/SpaceVibe/Tokens/Metrics.swift): 2, 4, 6, 8, 12, 16, 24, 32, with 2 and 6 only inside a
  component. Between blocks use `Rhythm`: cards 24, regions 32, two cards in one Activity lane 16.
- **Heights**: 20 key cap, 24 tag and segment, 28 every control, 32 section row and hint bar, 36 palette row, 48 every row,
  sidebar item and the top bar, 56 card header. **Radii**: 4 key cap, 6 tag and segment, 8 control, row block and sidebar
  item, 12 card; filter chips are capsules.
- **Colour** values live in `PaletteValue` ([Palette.swift](../Sources/SpaceVibe/Tokens/Palette.swift)) under the token names
  of the [v5 spec](specs/2026-11-06-reins-design-language-v5.md) and change app-wide at once (D53); this page is rewritten
  for v5 at its cut-over (X1). Screens not yet rebuilt read them through their old names: `well` is `bgSide`,
  `surface` `bgPanel`, `surfaceRaised` `bgRaise`, `divider` `hair`, `border` `hair2`, `selection` `sel`. The sidebar and
  the content area share the `well`, split by one 1 pt `divider`; the top bar and hint bar have no line. Cards are
  `surface` blocks on the well with no border, so the fill alone sets them off. Only overlays (palette, confirmations,
  toast) keep a border and a shadow.
- **Neutral surfaces; colour only where it means something.** Surfaces, lines, selection and focus are neutral. Green,
  amber and red (`ok`, `warn`, `bad`) mark state only; the category colours, Claude's clay and the blue accent stay outside
  their hue families ([`HuePolicyTests`](../Tests/SpaceVibeTests/HuePolicyTests.swift)). Codex's colour is the text colour.
  `Ink` twins carry text in a state or CLI colour, and tints use their fill at 15%. Every text and mark is checked on its
  composited ground in both appearances ([`ContrastTests`](../Tests/SpaceVibeTests/ContrastTests.swift)); a value raised to
  pass says so, with the spec's value, beside it in the palette. The
  [Limits state mapping](../Sources/SpaceVibe/Components/LimitFigure.swift) still overrides identity with warning/danger.
- **Controls have no outline.** Button, search field, scope picker, segmented control, filter chip and key cap fill with
  the [`ControlGround`](../Sources/SpaceVibe/Components/ControlGround.swift): `surface` on the well, `surfaceRaised` inside a
  card (a card, a dialog and the search field set it), and `selection` for the chosen segment or chip. Focus is a fill,
  never a ring (D57): [`focusFill`](../Sources/SpaceVibe/Components/FocusFill.swift) lays `sel` over the focused control,
  except a selected row or tile, which already wears it.

## Icons

- **Three generated sets and Reins's own verdict glyphs** (V5-R9, V5-R10, V5-R12, V5-R14 to V5-R16): MingCute Line for the
  category glyphs ([`CategoryGlyph`](../Sources/SpaceVibe/Components/CategoryIconData.swift): Skills `flash-line`, Subagents
  `robot-line`, Hooks `fish-symbol-line`), Phosphor Duotone for the sidebar and content glyphs
  ([`ContentGlyph`](../Sources/SpaceVibe/Components/ContentIconData.swift), Rules is its checklist glyph), and Solar Bold
  Duotone ([`ReinsGlyph`](../Sources/SpaceVibe/Components/ReinsIconData.swift)) only for the screens not yet rebuilt. The five
  hexagon verdict glyphs are shapes in [`VerdictGlyph`](../Sources/SpaceVibe/Components/VerdictGlyph.swift), one colour (`fg2`).
  The credits are in the About panel ([`Credits`](../Sources/SpaceVibe/App/Credits.swift)).
  [`IconPolicyTests`](../Tests/SpaceVibeTests/IconPolicyTests.swift) fails on an SF Symbol or any other image outside
  `Gallery/`; the CLI brand marks in [`CLIMark`](../Sources/SpaceVibe/Components/CLIMark.swift) are the one image.
- **Agent logos keep their brand colours.** [`CLIMark`](../Sources/SpaceVibe/Components/CLIMark.swift) draws the Claude and
  Gemini assets in their original colours and the Codex mark in black/white for the appearance. It adds no box, tint or
  border around a logo; the colour of a usage bar or a sidebar state tile never recolours the logo.
- **Generated Swift, not files.** [`generate-icons.mjs`](../scripts/generate-icons.mjs) turns the three
  `@iconify-json` packages (downloaded into a scratch folder, never committed) into the three data files: layers per glyph as
  path code in a 24 box (Phosphor's 256 grid is scaled). A glyph that is missing gets a line in the script's table, then a
  rerun; the files are never edited by hand. The tables name the icon behind each glyph. A glyph name that exists in two sets
  is picked by label: `ReinsIcon(.lock)` is Solar, `ReinsIcon(category: .skill)` and `ReinsIcon(content: .stack)` the v5 sets.
- **One colour per icon.** [`ReinsIcon`](../Sources/SpaceVibe/Components/ReinsIcon.swift) draws the layers in the current
  foreground style, the lighter at its set's opacity (Solar 50%, Phosphor 25% as the mock draws it, with the mock's thin
  outline around Phosphor shapes). Only a state tag and a banner tint an icon with their tone's ink.
- **Sizes** (`IconSize`): v5 uses 16 (controls, tabs, rows, menus, sidebar), 14 (popovers, file rows, notes, beside 12 pt
  text), 12 (chevrons, checks, the chip close) and 24 (the pane head's tile); never below 12. The old 22 and 20 stay until
  the cut-over.
- **The old chevron is drawn**, not taken from Solar Bold Duotone, whose chevron breaks up at small sizes: `Chevron` strokes
  Solar Linear's geometry (right, down, and the up-and-down pair of a menu). v5 uses Phosphor's caret at 12.

## Components

| Need | Component |
| --- | --- |
| A group of rows | [`GroupedList`](../Sources/SpaceVibe/Components/GroupedList.swift) (a card: 8 pt under the last row, a `RowDivider` between two rows that hides beside a filled row) with a [`CardHeader`](../Sources/SpaceVibe/Components/CardHeader.swift) (56, no line under it) as its first line; `SectionRow` for a sub-group; `.pinnedCardTop()` with `GroupedList(edges: .belowPinnedHeader)` for a header that stays put while rows scroll |
| One line | [`Row`](../Sources/SpaceVibe/Components/Row.swift) (48, `tall` for three lines or more; a block inset 8 from the card's edges that hover and selection fill at radius 8) with [`RowText`](../Sources/SpaceVibe/Components/RowText.swift), `EmptyRow`, `ShowMoreRow` |
| Progress | `UsageBar` in [`UsageCell`](../Sources/SpaceVibe/Components/UsageCell.swift): one continuous 6 pt capsule on `track` for every usage count (Loadout, Activity). [`Ruler`](../Sources/SpaceVibe/Components/Ruler.swift) is for Limits only: ten square cells whose two outer ends round by a quarter of the height (2 and 8), 8 high in the window list and 32 (`rulerDetailHeight`) under the figure, each a tenth of the real track with a 3 pt gap, the last filled cell cut at the share, empty cells `track` (`trackOnSelection` on a selected tile), a dashed outline when the share is not known |
| Limits | Layout H of the Limits mock: a 340 pt list (`limitsListWidth`) of [`LimitWindowTile`](../Sources/SpaceVibe/Components/LimitWindowTile.swift)s on the well (each its own `surface` block: 28 pt `CLIMark`, name, "CLI · resets in" line, small `Ruler`, share; `selection` over `surface` when chosen), 8 apart, and the selected window in a [`ContentCard`](../Sources/SpaceVibe/Components/ContentCard.swift) (a card with free content, 24 inside): mark and "CLI · window" title, [`LimitFigure`](../Sources/SpaceVibe/Components/LimitFigure.swift) (the share in `display`, toned by `LimitTone`, then "left of this window"), the 32 pt ruler, three [`FactTile`](../Sources/SpaceVibe/Components/FactTile.swift)s (a raised block inside the card, the one nesting) and the reading's source under them; [`LimitSidebarTile`](../Sources/SpaceVibe/Components/LimitSidebarTile.swift) with [`CLIMark`](../Sources/SpaceVibe/Components/CLIMark.swift) above the sidebar footer; the page itself is a [`SidebarItem`](../Sources/SpaceVibe/Components/SidebarItem.swift) after the tabs, its `mark` slot holding the stale clock |
| Cells | `UsageCell`, `NumberCell`, `StateCell`, `FixedCell`, `EmptyActionSlot`, `ReadOnlyMark`, `ColumnSpacer` ([Cells](../Sources/SpaceVibe/Components/Cells.swift)) |
| Labels | `Tag` (24, radius 6, `surfaceRaised`, neutral text; the tone is a 6 pt dot, or tints the icon when it has one; warn and danger keep their ink), `CLITag`, `CLIDot`, `Count`, `Kbd`; [`CLIMark`](../Sources/SpaceVibe/Components/CLIMark.swift)`(size: .glyph)` is the bare 14 pt brand glyph a `SegmentOption` can lead with |
| Icons | `ReinsIcon` (a `ReinsGlyph` at an `IconSize`), `Chevron` |
| Controls | `ReinsButtonStyle` kinds (normal, primary, danger, ghost, icon, plainIcon, inverse), `RowActionButton` (with a CLI badge), `SegmentedControl` (a segment may carry a CLI glyph and a shortcut), [`SegmentReadout`](../Sources/SpaceVibe/Components/SegmentedControl.swift) (the same frame for a value that is shown, not set: every option written out, the real one filled with `track`, or the warn tint), `FilterChip` (and its dismissible form), `ScopePicker`, `SearchField`, `TextInputField` |
| Messages | `Banner`, `EmptyState`, `NoteRegion`, `InsetBox`, `WarningNote`, `UsageLegend`, `ToastView`, `ConfirmationDialog`; [`StatusLead`](../Sources/SpaceVibe/Components/StatusLead.swift) (a page's one plain sentence on a `surface` block, led by a 40 pt tile in the tone's tint: neutral, success, warn) and [`CLISummaryBar`](../Sources/SpaceVibe/Components/CLISummaryBar.swift) (a 48 pt `surface` block on how the other CLI stands, on a page that shows one) |
| Settings | [`RailTab`](../Sources/SpaceVibe/Components/RailTab.swift) (96 x 60, 24 pt icon over the `label` name, the chosen one filled with `surface`), [`ThemeTile`](../Sources/SpaceVibe/Components/ThemeTile.swift) (a small Reins window drawn from the tokens with the appearance forced, System half and half; the chosen tile takes `selection`), [`ReinsSwitch`](../Sources/SpaceVibe/Components/ReinsSwitch.swift) (drawn, 32 x 20, `accentSolid` when on: AppKit's switch does not render in the screenshots), [`ReinsMark`](../Sources/SpaceVibe/Components/ReinsMark.swift) (the app mark from `Resources/AppIcon.svg` as shapes), [`RaisedBlock`](../Sources/SpaceVibe/Components/InsetBox.swift) (a borderless `surfaceRaised` block inside a card, like `FactTile`) |
| Page and shell | `PageLayout` (or `.pageTools()`, `.pageContent()`, `.pageBackground()`), `HintBar` (`shellKeys: false` drops `⌘K` and `Esc Close`), `SidebarItem` (48, `title` role in every state, the active one changes only its fill to `surface`) with `.sidebarSurface()`, `PaletteCard` and its parts, `Scrim` |

## Traps

- `Font.custom("Inter", …)` silently falls back to the system font: the family is `Inter Variable`. Build fonts only
  through `ReinsType`, which creates them by PostScript name.
- `@Entry` needs SwiftUI's macro plugin, which the Command Line Tools lack; container and environment keys are written out.
- Solar draws a few icons with overlapping half-opacity shapes (the Loadout `layers` glyph): the browser darkens the overlap,
  one light layer does not. Check a new glyph in the gallery's icon section before using it.
- Fixed widths that hold text were measured in Inter at these sizes (usage number 52, cost 72, state 128 since the v3 tag icon, Rules' Claude
  Code column 280, the Codex page's value column 300, the file history line 230). They grow with Font size through
  `TypeScale.width(_:at:)` and never shrink below the measured value. Recheck them when a role's size or weight changes,
  and give a new one the same treatment, or Large truncates it.
