# Reins design language v5

Status: draft for the owner's review, 2026-11-06. Decisions: [the Linear identity ledger](2026-11-06-reins-linear-identity-decisions.md) (D1-D37, all settled; cited below as `D<n>`). Product truth: [PRODUCT.md](../../PRODUCT.md). Current rulebook: [DESIGN-LANGUAGE.md](../DESIGN-LANGUAGE.md). Boundary rules: [AGENTS.md](../../AGENTS.md).

Reference mock (outside git, F4): `~/scratch/spacevibe-reins/linear-directions/c3/index.html`, the Loadout page the owner approved by eye on 2026-11-06. Values below were read from its CSS; where the mock and a ledger line disagree, the ledger wins (see "Mock gaps").

## Summary and why

Reins looks plain and has no identity of its own (D1 problem statement). v5 restyles the whole SwiftUI app after the Linear desktop app (D3, D4): neutral dark-first surfaces, one blue accent, a thin icon family, rounded inset rows, a permanent detail pane and keyboard-first interaction. It replaces the unbuilt v4 plan (D15; only its contrast test and sunken segmented track survive). This spec owns the shared language (tokens, components, icon policy, interaction primitives) and the Loadout page as its first adopter. Rules, Activity and Limits follow in later specs ("Next pages"). Settings is polished and out of scope (D1, D2); the landing page and app icon wait for the approved app (D14).

## Requirements

### Foundations

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R1 | The Linear desktop app is the single reference. Settings is not a reference. Wherever Linear and an earlier Reins rule differ, Linear wins. | D2, D3, D4 |
| V5-R2 | Surfaces are neutral (R, G and B within 4 of each other in dark; within 8 in light, as in the mock). Colour lives only in the accent, category icons, tab chips, state tones and CLI logos. | D6 |
| V5-R3 | One accent in the blue family, cleaner and deeper than today's `#476EAE`/`#A4BFEB`. The mock's three shades are the candidates; shade 1 is the default until the owner picks at final approval. | D10 |
| V5-R4 | Rules relaxed where Linear differs: cards without borders, one vertical line, sizes 12/14/16 only. Inter stays the only face. Type roles gain the sizes in the token table (10, 11, 13, 20, 28). | D7 |
| V5-R5 | Depth comes from tonal layers (`bg-side` < `bg-app` < `bg-panel` < `bg-raise`), 1 px translucent hairlines and a 1 px top-edge highlight (`hi`) on panels, buttons and overlays. No gradients, no illustrations. | D12 |
| V5-R6 | Dark is the primary appearance. Light has equal quality: every acceptance check runs in both, and no value exists in only one. | D13 |
| V5-R7 | The language is one token set shared by every screen (no per-screen switch; the v4 plan's "no switch" reasoning holds). Values change app-wide; Settings must keep working and pass contrast, but is not redesigned. See Open questions. | D1, D2, D15 |
| V5-R8 | Screens compose components and tokens only. `StyleBoundaryTests` keeps failing on a font, colour, radius or spacing literal in a screen folder, now including the new tokens. | D16 |

### Icons

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R9 | Icons are single-colour and recolourable (`currentColor`), drawn thin-stroke. Linear's own glyphs are not copied. | D5, D19 |
| V5-R10 | Category icons (tabs, row icons, group headers, detail-pane head) use MingCute Line: Skills `flash-line`, Agents `robot-line`, Hooks `fish-symbol-line`, All `layers-line`. | D32 |
| V5-R11 | Category colour: Skills violet, Agents teal, Hooks amber, All neutral foreground (values in the token table). The colour tells categories apart and nothing else. Entity-kind colour for rules and CLIs is not used in this spec. | D8, D20, D29 |
| V5-R12 | Sidebar icons use the foreground colour (white in dark, ink in light), 80% opacity at rest, 100% on hover and when current. The sidebar icon set is unchanged (Solar), so Solar stays for the sidebar only. | D20, D32 |
| V5-R13 | Every list item shows the same grey icon (`fg3`) for its category: no per-item or per-verdict icon in the list. | D20 |
| V5-R14 | Reins draws its own verdict icon set (hexagon badges: heavily used, used, never ran, dead, not measured). It appears only in the detail pane's verdict panel and in the Status filter submenu rows, never in a list row. The warning slot uses a warning glyph (triangle for Never ran and Dead, clock for Not measured). | D9, D19, D20, D24 |
| V5-R15 | The About panel credits MingCute with its author and licence. The licence text is verified against the set's repository before the build (see Open questions) and recorded in `Credits.swift`. | D32 |
| V5-R16 | Icon sizes: 16 for controls, tabs, rows and menus; 14 inside popovers, files and notes; 12 for chevrons, checks and the filter-chip close; 24 inside the 48 px pane head tile. Never below 12. | D7 |
| V5-R17 | CLI logos keep their brand colours (Claude clay, Codex monochrome for the appearance, Gemini as shipped), with no box or tint, as in the current rulebook. | D21 |

### Loadout structure

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R18 | Layout: compact list on the left (46% of the panel), permanent detail pane on the right. The Matrix two-CLI columns and empty Codex column go away. Overall app layout is otherwise unchanged. | D11, D17, D21 |
| V5-R19 | No title bar on the page. One top row, 44 high, holds the category tabs at the left and the scope control, Filter and View at the right. | D29 |
| V5-R20 | Tabs `Skills`, `Agents`, `Hooks`, `All`, each with its category icon and a count. Every tab sits on a chip. Inactive tabs are neutral (grey text, icon and count on a faint neutral chip, a little stronger on hover). Only the active tab takes its colour: tinted chip, coloured icon, text and count, with a darkened text variant in light. No underline, no border or ring of any colour. The count is 10 px inside a circle tinted by the tab's state. | D26, D29 |
| V5-R21 | The list is flat in every tab, including `All`: no group headers, ordered by run count descending. Verdicts show only through the warning icon. | D26, D27, D33 |
| V5-R22 | Row anatomy, left to right: leading slot (grey category icon; becomes a checkbox on hover, in multi-select and when picked), name, CLI logo strip, warning slot. No run counts, bars or rank numbers in a row. | D21, D23, D34 |
| V5-R23 | Rows are inset rounded blocks (radius 8). The divider between rows is a 1 px hairline at about 6% opacity, inset from the icon to the right edge, hidden beside a hovered, selected or picked row, before a group header and after the last row. No full-bleed lines. | D30 |
| V5-R24 | The CLI logo strip lists only CLIs detected on the machine. A logo is lit with a success badge at its corner when the item exists in that CLI, dim (35% opacity, greyscale) when it does not. Reins writes only to Claude Code and Codex. | D21, D25 |
| V5-R25 | A logo is a toggle. Click a dim logo: add the item to that CLI. Click a lit logo: remove it from that CLI. Each shows a toast with Undo. No popover and no tooltip on logos. The accessible name states the CLI and state, plus `aria-pressed` semantics (SwiftUI: toggle trait, selected value). Plugin-owned items are read-only: disabled trait and the not-allowed cursor. | D21, D22, D31 |
| V5-R26 | The same toggle works in the detail pane (for the item) and in the bottom bar (for the whole selection, adding or removing for every picked item at once). Hover on a removable lit logo turns its badge to the danger tone. | D28, D31 |
| V5-R27 | A warning slot at the row end (24 px) is present only on abnormal rows: Never ran (warn tone), Dead (danger tone), Not measured yet (neutral clock, not a warning). Hover or keyboard focus opens a popover (272 wide): a plain sentence, then `Remove` (danger on hover, with Undo) and `Open file`; Not measured offers no Remove. Normal rows keep the slot empty. | D22, D24 |
| V5-R28 | Filter button opens a two-level menu (field, then value). Each pick becomes a removable chip (`field | value | x`) in a row under the tabs that exists only while a filter is active, with a clear action. The field menu shows a count per field with active picks. | D37 |
| V5-R29 | Filter fields and values: Status (Never ran, Dead, Not measured, Heavily used); CLI (in Claude Code, in Codex, in both, in one only); Owner (mine, plugin); Rank (`Top 10 most used`, `Top 25`, `Least used 10`, `Never ran`, tiers `Top 20%`, `Middle`, `Bottom 20%`); Last ran (today, this week, over 30 days ago). Scope and Added are left for later. | D34, D35 |
| V5-R30 | View menu holds `Group by` (None default, Status, CLI presence, Owner, Rank tier, plus Kind in `All`) and `Order by` (Name, Run count default, Last run). Group headers exist only while a grouping is on: 40 high, borderless rounded bands (treatment 1, the default), sticky, collapsible. The spaced label with one inset hairline (treatment 2) is the owner's alternative and is not built unless chosen at approval. | D27, D30, D33, D36 |
| V5-R31 | Rank is never printed on rows. It exists as filters (V5-R29), the `Rank tier` grouping and the pane's run counts. | D23, D34 |
| V5-R32 | A bottom bar appears while one or more rows are picked: count, the logo strip acting on the whole selection, Remove, and a clear action. It sits above the status bar and moves the toast up. | D28 |
| V5-R33 | Detail pane: head (48 tile with the category icon in its colour, name 20/28, meta line, ownership tag, and the logo strip at the right), plain-sentence description, verdict panel (own verdict icon plus sentence), a meter per detected CLI with run count, bar and last run (a dashed line when the item is absent there; "Not measured yet" when unmeasured), files list, and actions (`Open file`, `Remove`). Run counts live only here. | D8, D14, D19, D20, D23 |
| V5-R34 | Bar colours follow identity: Claude clay, Codex foreground. State uses success, warn and danger only. A bar for an unmeasured item is never drawn as zero. | D8, D23 |
| V5-R35 | A bottom status bar (32) lists the working shortcuts and "Counted from local logs". The mock's stale `A add to Codex` hint is replaced by the toggle behaviour (V5-R25). | D31 |

### Interaction

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R36 | `j`/`k` (and arrows) move the current row; `x` picks or unpicks it; `Return`/`Space` moves focus to the pane actions; `o` opens the file; `Backspace`/`Delete` removes with Undo; `f` opens Filter; `1`-`4` switch tab; `z` undoes the last change. Shortcuts show as `Kbd` caps in the status bar. | D11 |
| V5-R37 | `Cmd+K` opens the command palette, restyled with the same tokens (560 wide, 48 field). `Esc` closes any popover, menu or the palette and returns focus to its origin. | D11 |
| V5-R38 | Every add, remove (CLI or whole item) shows a toast with Undo for 7 s, and Undo restores the previous state exactly, including for bulk actions. Removal keeps the existing restorable copy of configuration files (PRODUCT.md). | D21, D24, D28, D31 |
| V5-R39 | Menus: arrows move, `Right` opens a submenu, `Left` closes it, `Return` toggles a value. Menus are checkbox menus (`aria-checked`), and the picked value shows a tick. | D37 |

### Accessibility

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R40 | WCAG AA in both appearances: text 4.5:1 on its real composited surface (including tab chips, count circles, the selected row, and inactive vs active tab text); controls, icons carrying meaning, logos' state and focus indicators 3:1. | D13 |
| V5-R41 | Visible focus on every control: 2 pt accent ring (inset on rows, tabs and logos; 2 pt offset on buttons). | D11 |
| V5-R42 | Reduced motion removes the 120 ms transitions, the popover rise and the logo-badge pop. Nothing animates beyond fades and a short transform otherwise. | D12 |
| V5-R43 | Colour never carries state alone: verdicts have an icon and a sentence; a logo's lit state has a badge as well as opacity; every logo toggle, warning slot and tab has an accessible name and value (for example "Codex: not in Codex, press to add"). | D21, D31 |

## Token table

Dark and light values are from the mock's CSS. "Swift today" names the token in [`Tokens`](../../Sources/Reins/Tokens) that the row replaces or extends; "new" has no counterpart. Mock-only values (`desk`, traffic lights, the floating dev panel) are not tokens.

### Surfaces and lines

| Token | Dark | Light | Swift today |
| --- | --- | --- | --- |
| `bgSide` (sidebar) | `#0B0C0D` | `#F4F4F5` | replaces `Palette.well` for the sidebar |
| `bgApp` | `#0F1011` | `#F4F4F5` | replaces `Palette.background` |
| `bgPanel` (content panel, list, pane) | `#131416` | `#FFFFFF` | replaces `Palette.surface` as the page ground |
| `bgRaise` (buttons, meters, chips, pane tile) | `#191A1D` | `#FBFBFB` | replaces `Palette.surfaceRaised` |
| `bgSunk` (verdict panel) | `#0E0F10` | `#F6F6F7` | new |
| `bgPop` (menu, popover, toast, bottom bar, palette) | `#1B1C1F` | `#FFFFFF` | new; replaces overlay fill |
| `bgBand` (group band) | `#1B1C20` | `#EEEFF2` | new |
| `hair` | white 7.5% | black 8% | replaces `Palette.divider` (8%) and `border` |
| `hair2` (control outline, overlay edge) | white 12% | black 14% | extends `Palette.border` |
| `rowDivider` | white 5.5% | black 6.5% | new (V5-R23) |
| `bandTopRule` (treatment 2 only) | white 24% | black 26% | new, optional |
| `hi` (top-edge highlight) | white 5% | white 90% | new |
| `hover` | white 4% | black 3.5% | replaces `Palette.hover` (7% / 5%) |
| `sel` (selected row, active nav) | white 6.5% | black 5.5% | replaces `Palette.selection` (blue tint becomes neutral) |
| `track` | white 7% | black 6.5% | replaces `Palette.track` |
| `trackHi` | white 12% | black 10% | new |
| `kbdBg` / `kbdBorder` | white 6% / white 10% | black 3.5% / black 12% | extends `Kbd` fills |
| `scrim` | black 50% | `#141418` 25% | replaces `Palette.overlay` |

### Text

| Token | Dark | Light | Swift today |
| --- | --- | --- | --- |
| `fg` | `#F2F3F4` | `#1B1C1F` | replaces `Palette.text` |
| `fg2` | `#A3A7AE` | `#5E626A` | replaces `textSecondary` |
| `fg3` | `#6B7078` | `#8B8F97` | replaces `textTertiary` (contrast to be raised where used for text, V5-A2) |
| `fg4` (disabled, separators) | `#4A4E55` | `#B7BAC0` | new; not for text a user must read |

### Accent and state

| Token | Dark | Light | Swift today |
| --- | --- | --- | --- |
| `accent` shade 1 (default) | `#4F86F7` | `#2563D9` | replaces `Palette.accent` and `accentSolid` |
| `accent` shade 2 | `#6D83F5` | `#3F4FD6` | candidate |
| `accent` shade 3 | `#3DA1EE` | `#0A6CC4` | candidate |
| `accentBg` (picked row, filter count) | accent 16% | accent 10% | extends `selection` |
| `accentBd` | accent 40% | accent 40% | new |
| `ok` | `#4CB782` | `#2F9E6B` | replaces `success` |
| `warn` | `#E2A33C` | `#C4811A` | replaces `warn` |
| `bad` | `#E5604F` | `#D2442F` | replaces `danger` |
| `mute` / `nm` (not measured) | `#8A8F98` / `#8C94C8` | `#7A7F88` / `#6E78B8` | new |
| `onVerdict` (glyph cut-out) | `#0F1011` | `#FFFFFF` | extends `onAccent` |
| `claude` | `#D97757` | `#C65F3E` | replaces `Palette.claude` |
| `codex` | `#F2F3F4` | `#1B1C1F` | replaces `Palette.codex` (blue `#1596D6` goes) |
| Tints and `*Ink` twins | | | `claudeInk`, `codexInk`, `*Tint` are dropped unless a screen still needs them; to be decided per later spec |

Verdict to colour: heavily used `ok`, used `accent`, never ran `warn`, dead `bad`, not measured `nm`. The warning slot for Not measured uses `fg3`.

### Category colours

| Token | Dark | Light | Notes |
| --- | --- | --- | --- |
| `catSkill` | `#A78BFA` | `#7C5CE0` | Skills |
| `catAgent` | `#3FB8A5` | `#1E9D8A` | Agents |
| `catHook` | `#E8A64B` | `#C98410` | Hooks |
| `catAll` | `fg` | `fg` | All (neutral) |
| `entRule`, `entCli` | `#E8709F`, `#7DA2E8` | `#D2487F`, `#4C74C9` | defined in the mock, unused here (V5-R11) |
| Tab chip, inactive | `fg` 7%; hover 12% | same | text and icon `fg2`; hover `fg` |
| Tab chip, active | cat 26% | cat 26% | text, icon, count in cat colour; in light the text and count use cat mixed 68% with black |
| Tab count circle | inactive `fg` 12%; active cat 40% | same | 10 px, min 16 x 16, padding 0 4, radius 999 |

### Type

Body is 13/20 weight 400, Inter with `cv11`, `ss03`, `tnum`. The mock's roles, mapped to [`ReinsType`](../../Sources/Reins/Tokens/ReinsType.swift):

| Use | Mock | Swift today |
| --- | --- | --- |
| Count circle | 10/1, 500, tabular | new `micro` |
| Section label, kbd, secondary meta, path | 11/16, 500 (labels), 400 | new `small` |
| Controls, menus, filter chips, captions, tab count text | 12/16, 400 or 500 | `caption`, `label` |
| Body, row name, buttons, tab label | 13/20, 400 / 450 / 500; active tab 600 | replaces `body` 14, `rowTitle` 14 |
| Pane heading | 20/28, 600, tracking -0.01em | new `heading` |
| Pane figure | 28/32, 600, tracking -0.02em | `figure` (24) is replaced for Loadout |
| Group band | 13/20, 600 | `bodyStrong` |

Open for the build: whether the app-wide base becomes 13 or stays 14 with Loadout at 13. Decision goes in Open questions.

### Size, radius, spacing

| Token | Value | Swift today |
| --- | --- | --- |
| Radii | 4 (kbd, checkbox, chip tag), 6 (controls, tabs, nav items, logo, warn slot), 8 (panel, rows, menus, popovers, pane tile, bands, toast, buttons in overlays), 12 (window) | `kbdRadius`, `tagRadius`/`segmentRadius`, `controlRadius`/`rowRadius`, `groupRadius` 12 becomes 8 for panels |
| Sidebar | width 220, padding 0 8 8, item 32 high, item gap 2, group label 11/16, padding-top 16 | `sidebarWidth` 232, `sidebarItemHeight` 48 |
| Panel | margin 8 (top, right, bottom), 1 px `hair` border, radius 8 | new |
| Top row | 44 high; tabs chip 28 high, padding 0 10, gap 6, icon 16; toolbar buttons 28 | `topBarHeight` 48 |
| Filter chip row | padding 8 12, gap 8, chip 24 high, close 24 wide | `FilterChip` 28 capsule |
| List | padding 0 8 16, order bar 32, row 36, row padding 0 8 0 10, gap 8, divider left 34 right 8 | `rowMinHeight` 48 |
| Group band | 40 high, radius 8, margin-top 12 (4 first), padding 0 12 0 10 | new |
| Logo | 24 box (radius 6), image 20, badge 10 with 6 glyph and 1.5 ring in the surface colour | `CLIMark` small, `loadoutActionsWidth` 60 |
| Warning slot | 24 | new |
| Menu | 208 wide (submenu 232), padding 4, item 28 high, radius 6, 12 type | new |
| Popover | 272 wide, padding 12, gap 12, radius 8 | new |
| Pane | padding 32 40 40, max width 640, gap 24, head tile 48, file row 32, meter padding 16, bar 8 high radius 4 | new |
| Bottom bar | 44 high, radius 8, 48 above the bottom edge | new |
| Toast | 40 high, radius 8, 48 above the bottom edge (104 while the bottom bar shows) | `toastBottomInset` 48 |
| Status bar | 32 high, padding 0 16, gap 16 | `hintBarHeight` 32 |
| Buttons | 32 (pane) / 28 (overlays, bar), radius 6, 1 px `hair2`, top highlight | `controlHeight` 28 |
| Kbd | 18 high, min width 18, 2 px bottom edge | `kbdHeight` 20 |
| Palette | 560 wide, field 48, row 32, footer 32 | `paletteWidth` 600 |
| Motion | 120 ms hover and press; popover rise 120 ms; logo pop 180 ms; bar 150 ms | `ReinsButtonStyle` 0.15 s |
| Shadows | popover `0 8 32` black 40% plus `hi`; palette `0 24 64` black 50%; window ring 1 px at 8% | `overlayShadow*` |
| Focus | 2 pt accent, offset -2 (inset) or 2 (buttons) | `FocusRing` |

## Components

States listed are the ones the gallery must show in both appearances. "Replaces" names the file in [`Components`](../../Sources/Reins/Components) or [`Loadout`](../../Sources/Reins/Loadout).

| Component | States | Replaces or new |
| --- | --- | --- |
| `Panel` (content panel with border, radius 8, top highlight) | default | new; replaces `PageLayout` ground and `ContentCard` for the page frame |
| `SidebarItem` (32, white icon, count) | rest, hover, pressed, current, focus | replaces [`SidebarItem`](../../Sources/Reins/Components/SidebarItem.swift) (48) |
| `CategoryTab` (chip, icon, label, count circle) | inactive, hover, active (per category and neutral All), focus, light | new; replaces tabs in [`LoadoutTab.swift`](../../Sources/Reins/Loadout/LoadoutTab.swift) and [`RailTab`](../../Sources/Reins/Components/RailTab.swift) is untouched (Settings) |
| `CategoryIcon` (MingCute Line, tinted) | four categories, grey in rows | new; extends [`ReinsIcon`](../../Sources/Reins/Components/ReinsIcon.swift) with a second glyph source |
| `VerdictIcon` (own hexagon set) | heavy, used, never, dead, not measured | new |
| `ListRow` (36, leading slot, name, strip, warning slot, divider) | rest, hover, current, picked, current and picked, focus | replaces [`Row`](../../Sources/Reins/Components/Row.swift) usage in Loadout, [`LoadoutRowView`](../../Sources/Reins/Loadout/LoadoutRowView.swift) |
| `PickCheckbox` (16, swaps with the category icon) | hidden, hover, multi-select, picked | new |
| `RowDivider` (inset hairline, hides beside filled rows) | visible, hidden | extends `RowDivider` in [`GroupedList`](../../Sources/Reins/Components/GroupedList.swift) |
| `LogoToggle` (24 box, logo, badge) | lit, dim, hover on lit (danger badge), hover on dim, pressed, focus, read-only, just-changed pop | new; replaces [`CLIDot`](../../Sources/Reins/Components/CLIDot.swift) as a row control and Loadout's `RowActionButton` pair |
| `LogoStrip` (row, pane head, bottom bar) | per detected CLI, mixed lit state for bulk | new; builds on [`CLIMark`](../../Sources/Reins/Components/CLIMark.swift) |
| `WarningSlot` (24) with `WarningPopover` | empty, warn, danger, not measured, hover, focus, popover open | new |
| `Popover` (surface, 272) | open, with text and actions | new; reuses [`ConfirmationDialog`](../../Sources/Reins/Components/ConfirmationDialog.swift)'s overlay tokens |
| `MenuSurface` and `MenuItem` (checkbox, submenu arrow, count) | rest, hover, focus, checked, expanded | new; replaces [`ScopePicker`](../../Sources/Reins/Components/ScopePicker.swift) menu body |
| `ToolbarButton` (ghost 28: Filter, View) | rest, hover, pressed, open, focus, filtered count | replaces the ghost kind of [`ReinsButtonStyle`](../../Sources/Reins/Components/ReinsButtonStyle.swift) |
| `ScopeControl` (outlined 24) | rest, hover, open | replaces `ScopePicker` |
| `FilterChip` (`field | value | x`) and `FilterChipRow` | default, hover close, focus | replaces [`FilterChip`](../../Sources/Reins/Components/FilterChip.swift) (capsule) for filters; the capsule remains elsewhere until those pages are restyled |
| `GroupBand` (40, chevron, label, count, composition strip) | expanded, collapsed, hover, focus | replaces [`GroupLabel`](../../Sources/Reins/Components/GroupLabel.swift) in Loadout |
| `OrderBar` (32, "Ordered by runs") | default | new |
| `BulkBar` (44, count, strip, Remove, clear) | hidden, shown, mixed | new |
| `DetailPane` with `PaneHead`, `VerdictPanel`, `CLIMeter`, `FileList`, `PaneActions` | normal, abnormal (three verdicts), plugin read-only, one CLI only, empty selection | new; replaces [`FactTile`](../../Sources/Reins/Components/FactTile.swift) and `UsageCell` use in Loadout |
| `ReinsButtonStyle` kinds (normal, primary, danger, ghost, icon) | rest, hover, pressed, disabled, focus | extends the existing style; v4's raised button is dropped |
| `SegmentedControl` | rest, chosen, hover, focus; sunken track | extends [`SegmentedControl`](../../Sources/Reins/Components/SegmentedControl.swift); kept for the Rules switch (D15) |
| `Kbd` | cap, on accent | extends [`Kbd`](../../Sources/Reins/Components/Kbd.swift) |
| `Toast` (with Undo and `Kbd`) | shown, with bulk text | extends [`Toast`](../../Sources/Reins/Components/Toast.swift) |
| `StatusBar` | default | replaces [`HintBar`](../../Sources/Reins/Components/HintBar.swift) |
| `Palette` card | open, empty, selected row | restyles `PaletteParts` and `CommandPalette` |
| `EmptyState` | no items, no match with a clear-filters button | extends [`EmptyState`](../../Sources/Reins/Components/EmptyState.swift) |

Not touched: `RailTab`, `ThemeTile`, `ReinsSwitch`, `ReinsMark` (Settings), `Ruler`, `LimitWindowTile`, `LimitFigure` (Limits; later spec).

## Acceptance criteria

| ID | Check |
| --- | --- |
| V5-A1 | Side-by-side parity (W20). The built Loadout page is compared with `~/scratch/spacevibe-reins/linear-directions/c3/index.html` as it stood at approval, per surface: tabs and top row, list and rows, logo strip, warning slot and popover, filter menu and chip row, View menu, grouped state, bottom bar, detail pane (normal, abnormal, plugin, one CLI), toast, command palette. Each surface is judged on structure, content, look and theme, in dark and in light. Token counts, test counts and green builds never stand in for this check. |
| V5-A2 | A contrast test reads the tokens and checks every text and meaning-carrying pair on its composited surface at 4.5:1 (text) or 3:1 (controls, focus, state icons), in both appearances, including inactive and active tab text, count circles, `fg3` where it carries text, warning icons on `bgPanel`, and `onVerdict` on verdict fills. The test fails on a miss; failing pairs are fixed in the token, not exempted. |
| V5-A3 | `StyleBoundaryTests` is updated for the new tokens and still fails on a font, colour, radius or spacing literal in `Loadout`, `Shell`, `Rules`, `Activity`, `Limits` and `Settings`; its allowlist stays empty. |
| V5-A4 | `IconPolicyTests` is updated: category icons come only from the MingCute generated file, sidebar icons only from the Solar generated file, verdict icons only from the own set, CLI logos from `CLIMark`; no `Image(systemName:)` outside `Gallery/`; the credits string names both sets. |
| V5-A5 | Model tests cover: flat order by run count descending in every tab; tab counts; each filter field and value, combined (AND across fields, OR within a field); rank filters and tiers on ties; each Group by and Order by; verdict and warning-slot mapping; plugin items are read-only. |
| V5-A6 | Model tests cover the toggle: add to a CLI, remove from a CLI, bulk add and remove, plugin refusal, the last-lit-logo rule from the Open question, and Undo restoring the exact prior state; file writes go through the existing journal and keep a restorable copy. All against `TempHome` (S-R1). |
| V5-A7 | Keyboard walkthrough in the built app: `j`/`k`, `x`, `Return`, `o`, `Backspace`, `f`, `1`-`4`, `z`, `Cmd+K`, `Esc`, menu arrows, and `Tab` order reach every control with a visible ring. Recorded in the plan with the observed result. |
| V5-A8 | Accessibility: every logo toggle, warning slot, tab and menu item exposes a name and a value to VoiceOver; reduced-motion on removes all transitions. Checked in the built app and recorded. |
| V5-A9 | The About panel shows the MingCute credit with a licence verified against the set's repository (V5-R15), and the Solar credit remains for the sidebar. |
| V5-A10 | The gallery shows every component in the Components table in every listed state, in both appearances, via `REINS_GALLERY=1` and `scripts/dev-fixture.sh --shots <dir>`. |
| V5-A11 | Sweep (W21). Each token, radius and height that changes ends with "changed N of M" from a repo-wide search, each skipped site named with its reason. Settings, Rules, Activity and Limits screenshots in both appearances show no breakage (contrast, truncation, overlap); redesigns of them are not asserted. |
| V5-A12 | `scripts/test.sh` reports more than 0 tests passed, `scripts/build-app.sh` prints `minos 15.0`, and `docs/DESIGN-LANGUAGE.md` is rewritten for the shipped language (D1 living docs), with its link anchors passing `docs-anchors.sh`. |
| V5-A13 | Runtime check (W22): shots and the walkthrough run in the owner's dev command and checkout with older instances stopped, on the synthetic fixture home, never the real `~/.claude`. |
| V5-A14 | Owner eye approval happens in ONE final task, after V5-A1 to V5-A13 pass: the Loadout shots, dark and light, beside the mock, plus the gallery. It also records the accent shade pick (V5-R3) and the group-band treatment (V5-R30). No eye gate between tasks. |

## Traceability (W20)

Every decision in the ledger has a row. D18, D22 and D26 are superseded or partly superseded; their rows name what replaced them.

| Decision | Quoted | Requirements | Acceptance |
| --- | --- | --- | --- |
| D1 | "chỉ có setting là được polish rồi" | V5-R7, V5-R8 | V5-A1, V5-A11 |
| D2 | "setting không phải mốc hay tham chiếu" | V5-R1, V5-R7 | V5-A11 |
| D3 | "linear app desktop làm app tham khảo" | V5-R1 | V5-A1 |
| D4 | "lấy gần như toàn diện" | V5-R1, V5-R4 | V5-A1 |
| D5 | "icon có thể đổi màu được" | V5-R9, V5-R11 | V5-A4 |
| D6 | "q3 trung tính" | V5-R2 | V5-A1, V5-A2 |
| D7 | "theo linear hoàn toàn đi" | V5-R4, V5-R16 | V5-A1, V5-A3 |
| D8 | icon colour by state and kind (narrowed by D20) | V5-R11, V5-R33, V5-R34 | V5-A1, V5-A4 |
| D9 | one thin-stroke set plus own verdict set | V5-R10, V5-R12, V5-R14 | V5-A4 |
| D10 | blue accent, 2-3 shades for an eye pick | V5-R3 | V5-A2, V5-A14 |
| D11 | Linear's interaction primitives | V5-R18, V5-R36, V5-R37, V5-R41 | V5-A7 |
| D12 | gradient ban stays; tonal layers | V5-R5, V5-R42 | V5-A1, V5-A8 |
| D13 | dark primary, light equal | V5-R6, V5-R40 | V5-A1, V5-A2 |
| D14 | app icon and landing later | Out of scope; V5-R33 only reads it | V5-A11 |
| D15 | plan v4 replaced | V5-R7 (contrast test V5-A2, sunken track on `SegmentedControl`) | V5-A2, V5-A12 |
| D16 | 3 mock directions, owner picks, then Swift | V5-R8 | V5-A1, V5-A14 |
| D17 | "option C layout khá tốt" | V5-R18 | V5-A1 |
| D18 | superseded by D23 (no counts in rows) | V5-R22, V5-R33 | V5-A1 |
| D19 | "icon không được lấy y nguyên của linear" | V5-R9, V5-R14 | V5-A4 |
| D20 | white sidebar icons, grey item icons | V5-R11, V5-R12, V5-R13, V5-R14 | V5-A1, V5-A4 |
| D21 | logo strip per row | V5-R22, V5-R24, V5-R25, V5-R38 | V5-A1, V5-A6 |
| D22 | superseded by D31 (no logo popover) | V5-R25, V5-R27 | V5-A1 |
| D23 | "số lần chạy ... trong trang detail" | V5-R22, V5-R31, V5-R33, V5-R34 | V5-A1 |
| D24 | warning icon with popover | V5-R14, V5-R27, V5-R38 | V5-A1, V5-A5 |
| D25 | only detected CLIs | V5-R24 | V5-A5 |
| D26 | tabs kept; verdict groups superseded by D33 | V5-R20, V5-R21 | V5-A1 |
| D27 | Group by and Order by | V5-R30 | V5-A5 |
| D28 | `x` multi-select with strip in the bar | V5-R26, V5-R32, V5-R38 | V5-A6, V5-A7 |
| D29 | simplified top, tab chips | V5-R11, V5-R19, V5-R20 | V5-A1, V5-A2 |
| D30 | softened list lines | V5-R23, V5-R30 | V5-A1 |
| D31 | logo is a toggle, no popover | V5-R25, V5-R26, V5-R35, V5-R43 | V5-A1, V5-A6, V5-A8 |
| D32 | "chọn Mingcute Line icon đi" | V5-R10, V5-R12, V5-R15 | V5-A4, V5-A9 |
| D33 | flat list, no default grouping | V5-R21, V5-R30 | V5-A1, V5-A5 |
| D34 | rank filters | V5-R29, V5-R31 | V5-A5 |
| D35 | filter kinds | V5-R29 | V5-A5 |
| D36 | group by kinds | V5-R30 | V5-A5 |
| D37 | Linear-style two-level filter UI | V5-R28, V5-R39 | V5-A1, V5-A7 |

## Out of scope

Each line was checked against the ledger and narrows no decision.

- Redesign of Rules, Activity and Limits (their spec comes later; D1 keeps them in the track, D11 keeps their layouts).
- Settings redesign (D1, D2). It inherits shared tokens (V5-R7) and is verified not to break (V5-A11).
- Landing page `site/` and the app icon (D14).
- User-chosen icon colours (D8 settled that data state and entity kind decide the colour).
- The sidebar icon set swap (D32 keeps the sidebar icons as they are).
- Filters by Scope and Added (D35 leaves them for later).
- Gemini CLI as a write target (D25: Reins writes only to Claude Code and Codex).
- Any change to ReinsCore behaviour or the Node oracle.

## Mock gaps

- The mock draws category icons from Phosphor Duotone; D32 supersedes this with MingCute Line. Parity (V5-A1) accepts the glyph difference and checks size, colour and position.
- The mock's status bar still shows `A add to Codex`; D31 supersedes it (V5-R35).
- The mock has no MingCute path data, no stroke weights for the new icons, and no value for the Not measured warning glyph beyond the clock; the build picks MingCute `time-line` unless the owner objects.
- The mock's dev panel (header treatment, accent, theme) and traffic lights are not product UI.
- The mock has no loading, error or empty-library states. The build uses `EmptyState` with the new tokens; these are reviewed in the final eye pass.

## Open questions

1. **Removing the only CLI copy through the logo toggle.** If an item exists in one CLI only and the owner clicks its lit logo, the item disappears entirely. Recommended: the last lit logo is not toggleable (disabled trait, accessible name says so) and `Remove` in the pane or popover is the explicit action. Needs the owner's yes before V5-A6 is written.
2. **Do token values change app-wide at once?** Recommended yes (V5-R7), so Settings and the other pages take the new surfaces and text at once while their layouts wait; the alternative is a parallel token set that doubles the maintenance. A visible mismatch between Loadout and unconverted pages in the interim is accepted.
3. **Base text size.** The mock uses 13 for body. Recommended: Loadout and the shell use 13; other pages stay at their roles until their specs, and the Settings > Font size control keeps scaling every role together.
4. **MingCute licence.** The set's licence is not yet verified. If it needs more than a credit line (V5-R15), the icon choice returns to the owner before the build.
5. **Accent shade and group-band treatment** are picked at the final eye approval (V5-A14).

## Next pages

Rules, Activity and Limits reuse this language (tokens, components, icon policy, interaction primitives) and keep their approved layouts. Their own requirements come in later specs.

- **Rules:** one page per CLI behind a `Claude Code | Codex` switch; the Codex page is read only. It reuses `SegmentedControl` (sunken track), `Panel`, `ListRow` and the state tones.
- **Activity:** keeps its lanes and state column; adopts the new rows, tags and tones.
- **Limits:** keeps the list plus detail with a segmented ruler ([`Ruler`](../../Sources/Reins/Components/Ruler.swift)); adopts the new surfaces and the detail-pane pattern.

Execution lives in a plan written after this spec is accepted (W2); the old [v4 plan](../plans/2026-11-05-reins-design-language-v4.md) and the "v4 changes" section of the [2026-11-03 spec](2026-11-03-reins-design-language.md) are then marked superseded by this one (D15).
