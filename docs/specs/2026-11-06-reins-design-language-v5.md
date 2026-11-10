# Reins design language v5

Status: rewritten 2026-11-07 to cover the whole ledger (D1 to D68, 68 decision lines) and the mock the owner froze as the build reference on 2026-11-07 (D68, ledger line 79). Not built: no Swift for v5 exists. Light mode was not eye-checked after the D66 spacing change. Execution: [build plan](../plans/2026-11-07-reins-ui-v5-build.md).

Sources, in this order of authority:

- Decisions: [the Linear identity ledger](2026-11-06-reins-linear-identity-decisions.md). Cited as `D<n>`. Three IDs were written twice by two sessions (D63 to D65); the UI rows were renumbered D66 to D68 on 2026-11-07 (C1), so every ID is unique. A citation may still add the ledger line, for example `D63 (L81)`.
- Words and meanings: [PRODUCT.md](../../PRODUCT.md) (jobs, colour meanings) and [GLOSSARY.md](../../GLOSSARY.md) (one word, one meaning). They win any copy conflict ([AGENTS.md](../../AGENTS.md), "Read before work").
- Structure, blocks, look and behaviour: the frozen mock (below). Where the mock carries a word, state, number or element that a ledger line removed, the ledger wins and the case is listed under "Mock substitutions", so the side-by-side check knows the expected difference.
- Current rulebook (replaced at cut-over): [DESIGN-LANGUAGE.md](../DESIGN-LANGUAGE.md). Boundary and toolchain rules: [AGENTS.md](../../AGENTS.md).

Requirement IDs V5-R1 to V5-R48 and V5-A1 to V5-A17 keep their 2026-11-06 meaning where the requirement survives; a row whose content changed says so, and new rows start at V5-R49 and V5-A18. Environment variables use the `SPACEVIBE_` prefix that the go-core plan's task R1 introduces (it was being applied, uncommitted, in the shared checkout when this was written; before it lands, read `REINS_` for `SPACEVIBE_`).

## Reference mock (frozen, D68)

Outside git (F4), on the owner's Mac: `~/scratch/spacevibe-reins/linear-directions/`.

| Surface | Page | Approved as |
| --- | --- | --- |
| Agents > Skills | `c3/index.html` | list plus permanent detail pane (D17, D45) |
| Agents > Subagents | `b-subagents/index.html` | split layout (D61, D67) |
| Agents > Hooks | `b-hooks/index.html` | split layout |
| Agents > Rules | `b-rules/index.html` | split layout |
| Activity (Running, Failed, Files) | `b-activity/index.html` | split layout |
| Limits | `b-limits/index.html` | split layout, the bento test page (D56, D59) |

- Entry: `index.html#page=<skills|agents|hooks|rules|activity|limits>&theme=<dark|light>&accent=<1|2|3>`. Serve the folder with any static server (for example `python3 -m http.server <port> --directory ~/scratch/spacevibe-reins/linear-directions`) or open it as `file://`.
- Kit: `system/shared.css` (tokens; the "rhythm" block at its end holds the D66 spacing), `system/shared.js` (blocks, popover, menus, toast, palette, keys), `system/data.js` (synthetic sample data, one source for every page), `system/components.html` (specimen sheet), `system/check-page.sh` (UP1 check for mock pages).
- Briefs that state the intent: `BRIEF-wireframe.md` (the Answer card, one Filter button, Enter detail, one key one meaning) and `BRIEF-split.md` (D61 split).
- The frozen state is dark, accent 1, category set 1 (`?cat` absent), group-header treatment 1 (`hdr=1`): the hub's defaults (`index.html`, `system/shared.js` `init`).
- Mock-only, never built: the hub strip above the window, the floating dev panel (header treatment, accent dots, theme), the `⌘K` "Preview" presets, the `L` key and `?side=left` (spine side flip), the `?cat`, `?hdr`, `?accent`, `?theme` and `?state` parameters, and every toast that says "(mock only)" or "(stub)". The presets still name the states the build must render (V5-R62).

## Summary and why

Reins looked plain and had no identity of its own (ledger, Problem). v5 restyles the whole SwiftUI app after the Linear desktop app (D3, D4) and reorganises it (D43 to D50): the sidebar holds Agents, Activity and Limits; Agents holds the Skills, Subagents, Hooks and Rules tabs; Activity holds Running, Failed and Files. Every page uses one visual system (D54): neutral dark-first surfaces, one blue accent, recolourable thin icons, inset rounded rows, generous two-level spacing (D66). Pages differ only in how they arrange the shared blocks: Skills keeps a list with a permanent detail pane (D17); every other page is split in two halves, small cards on the left led by an Answer card, one tall card of bands on the right (D56, D59, D61, D67). Settings is already polished and only takes the shared token values (D1, D2, D53). The landing page and the app icon wait for the approved app (D14).

## UX brief (UX1)

Jobs, entities, vocabulary and colour meanings live in [PRODUCT.md](../../PRODUCT.md) ("UX principles") and [GLOSSARY.md](../../GLOSSARY.md); they are not copied here. Main flow: open a page, read its Answer card, act on the fix inside it or on the flagged row in the tall card (one hover or click, D41), undo from the toast if needed. Each page answers one question and serves one job (D38, D51, D52):

| Surface | Question the page answers | Job (PRODUCT.md order) | Primary datum |
| --- | --- | --- | --- |
| Skills | Which skills never run, and which CLI lacks which skill? | 1 clean up, 2 balance | the selected skill's sessions per CLI (pane) |
| Subagents | Which subagent never ran and can still run Bash? | 1 clean up, 3 control | the Answer sentence |
| Hooks | Which hook cannot run, and which is missing in Codex? | 1 clean up, 2 balance, 3 control | the Answer sentence |
| Rules | Is a tool open in one CLI and denied in the other? | 3 control | the Answer sentence |
| Activity | Who needs me now (Running), what keeps failing (Failed), what changed (Files)? | 4 watch | the Answer sentence per tab |
| Limits | Where should heavy work go until when? | 4 watch | the Answer sentence; each window's share left |

## Requirements

### Foundations

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R1 | The Linear desktop app is the reference for the visual language and interaction primitives (D3, D4). For the build, the frozen mock is the reference (D68); Settings is not a reference (D2). Where Linear and an earlier Reins rule differ, Linear wins. | D2, D3, D4, D68 (L79) |
| V5-R2 | Surfaces are neutral (R, G and B within 4 of each other in dark, within 8 in light, as in the kit). Colour lives only in the accent, category icons and the active tab chip, state tones and CLI logos. | D6 |
| V5-R3 | One accent in the blue family. Build value: shade 1 (`#4F86F7` dark, `#2563D9` light), the frozen mock's default; the owner confirms it at the final eye task (V5-A14). Shades 2 and 3 stay recorded in the token table. | D10, D68 (L79) |
| V5-R4 | Rules relaxed where Linear differs: cards and panels carry a 1 px hairline border, several type sizes, one vertical line between sidebar and content is not required. Inter stays the only face. Type roles in the token table (10, 11, 12, 13, 16, 20, 28, plus the palette field 14). Card titles are 16 (D61). | D7, D61 |
| V5-R5 | Depth comes from tonal layers (`bgSide` < `bgApp` < `bgPanel` < `bgRaise`), 1 px translucent hairlines and a 1 px top-edge highlight (`hi`) on panels, cards, buttons and overlays. No gradients, no illustrations. | D12 |
| V5-R6 | Dark is the primary appearance. Light has equal quality: every acceptance check runs in both, and no value exists in only one. Light was not looked at after the D66 spacing change (D68); its first eye check is the final eye task. | D13, D68 (L79) |
| V5-R7 | One token set for the whole app (no per-screen set). Token values change app-wide at once: Settings and every screen not yet rebuilt take the new surfaces and text without a redesign, and must keep passing contrast. | D1, D2, D15, D53 |
| V5-R8 | Screens compose components and tokens only (UP1 in the app). `StyleBoundaryTests` fails on a font, colour, radius, spacing, size, background, border, shadow, gradient or repeating animation in a screen folder, and on a screen folder it does not know. | D16, D54, D55 |

### Icons

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R9 | Icons are single-colour and recolourable (one foreground colour, a duotone's light layer at reduced opacity), never Linear's own glyphs. | D5, D19 |
| V5-R10 | Category glyphs (tab chips, row lead icons, pane head) come from MingCute Line: Skills `flash-line`, Subagents `robot-line`, Hooks `fish-symbol-line`. Rules uses the mock's checklist glyph (D32 names no Rules glyph). `All` and its glyph are gone (D49). Activity's tabs use the mock's pulse (Running), bug (Failed) and file (Files) glyphs. Whether the mock's category paths are MingCute is unverified (the sprite comment says Phosphor): the icon task compares them with `@iconify-json/mingcute` first. | D32, D46, D49 |
| V5-R11 | Category colour tells categories apart and nothing else. Build values are the frozen mock's set 1: Skills violet, Subagents magenta, Hooks cyan, Rules pink (token table). Activity's tabs use the accent (they are not categories). The owner confirms the set at the final eye task; V5-A16 decides whether Rules pink is far enough from the danger hue. | D8, D20, D29, D40, D68 (L79) |
| V5-R12 | Sidebar icons use the foreground colour (white in dark, ink in light), 80% opacity at rest, 100% on hover and when current. Glyphs as the mock draws them: stack (Agents), pulse (Activity), gauge (Limits), sliders (Settings), search, sun and moon. CHANGED: the 2026-11-06 version kept Solar for the sidebar; the frozen mock draws Phosphor Duotone glyphs there (see C13 and open question 6). | D20, D32, D68 (L79) |
| V5-R13 | A list or card row that carries a lead icon shows the same grey (`fg3`) category glyph on every row: Skills list rows and Hooks rows. Subagents, Rules, Activity and Limits rows carry no lead icon (mock). No per-item or per-verdict icon in a row. | D20 |
| V5-R14 | Reins's own hexagon verdict glyphs (`heavy`, `used`, `never`, `dead`, `nm`) use one neutral colour (`fg2`); the shape carries the meaning. Meanings follow D63 (L81) and the glossary: `used` Ran, `heavy` Ran in the top 20% tier, `never` Never ran, `nm` Unmeasurable; `dead` is not shown for skills or subagents (see Mock substitutions). They appear in the Skills pane's verdict panel, in Answer cards' verdict boxes (the neutral "Advice" glyph), and beside Status values in filter menus, never in a row. The row warning slot uses the triangle (Never ran in the warn tone, can't run in the danger tone), the clock (neutral: Unmeasurable, a stale or unknown reading, a newly added item) and the lock (plugin-owned, read-only). | D9, D19, D20, D24, D58, D63 (L81), D65 (L78) |
| V5-R15 | The About panel credits every icon set in use, each licence verified against its source before the build and recorded in `Credits.swift`: MingCute (category glyphs), Phosphor (content and sidebar glyphs, if open question 6 keeps them), and Solar for as long as one Solar glyph remains. | D32 |
| V5-R16 | Icon sizes: 16 for controls, tabs, rows, menus and sidebar; 14 in popovers, file rows, notes and inline with 12 pt text; 12 for chevrons, checks and the filter-chip close; 24 in the 48 pt pane-head tile. Never below 12. | D7 |
| V5-R17 | CLI logos keep their brand colours (Claude clay, Codex monochrome for the appearance, Gemini as shipped), with no box, tint or border. | D21 |

### Skills (Agents > Skills)

The Loadout page of the 2026-11-06 version, now the Skills tab (D43, D46). It is the only page with a list and a permanent pane (D45, D56).

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R18 | Layout: compact list on the left (46% of the panel width) with an order line above it, permanent detail pane on the right. The Matrix two-CLI columns and the empty Codex column are gone. | D17, D21, D45, D56 |
| V5-R19 | CHANGED (D66): the Agents tab head is 60 high (V5-R51). On Skills it holds the category tabs at the left and, at the right, the scope control, `Filter` and `View`, as in `c3`. No title bar. | D29, D66 |
| V5-R20 | CHANGED (D46, D49, D66): tabs `Skills`, `Subagents`, `Hooks`, `Rules`, each with its category glyph and a count; no `All`. Every tab sits on a chip 36 high (padding 0 14, 10 apart). Inactive tabs are neutral (`fg2` text, glyph and count on `fg` at 7%, 12% on hover). Only the active tab takes its category colour: chip at 26%, glyph, text (600) and count in the category colour, with the text and count mixed 68% with black in light. The count is 10 pt in a circle at least 16 x 16 (`fg` 12% inactive, category 40% active). No underline, no border or ring of any colour. | D26, D29, D46, D49, D66 |
| V5-R21 | The list is flat: no group headers by default, ordered by sessions descending. Usage shows only through the warning slot. | D26, D27, D33, D64 (L80) |
| V5-R22 | Row anatomy, left to right: leading slot (grey category glyph; becomes a checkbox on hover, in multi-select and when picked), name, CLI logo strip, warning slot. No counts, bars or rank numbers in a row. | D21, D23, D34 |
| V5-R23 | CHANGED (D66): rows are 44 high, inset rounded blocks (radius 8). The divider between rows is a 1 px hairline (`rowDivider`), inset from the text to 8 from the right edge, hidden beside a hovered, selected or picked row, before a group band and after the last row. The current row has a 2 pt accent bar at its left edge, 8 from top and bottom. No full-bleed lines. | D30, D66 |
| V5-R24 | The logo strip lists only CLIs detected on the machine. A logo is lit with a success badge at its corner when the skill exists in that CLI, dim (35% opacity, greyscale) when it does not. Reins writes only to Claude Code and Codex. | D21, D25 |
| V5-R25 | A logo is a toggle: click a dim logo to add the skill to that CLI, a lit one to remove it, each with a toast and Undo. No popover and no tooltip on logos; the accessible name states the CLI and state (toggle trait, selected value). Plugin-owned skills are read-only (disabled trait, not-allowed cursor). The last lit logo of a skill is not toggleable: `Remove` in the pane or the warning popover is the explicit action (answers the 2026-11-06 open question 1). | D21, D22, D31, D53 |
| V5-R26 | The same toggle works in the detail pane (for the skill) and in the bottom bar (for every picked skill at once). Hover on a removable lit logo turns its badge to the danger tone. | D28, D31 |
| V5-R27 | CHANGED (D63 L81): a warning slot (24) at the row end appears only on a skill that `Never ran`: triangle in the warn tone; a newly added skill (file added, not merely edited) shows the neutral clock and a quiet note such as "added 2 hours ago" instead, so a fresh install is not removed by mistake. Hover or keyboard focus opens the 272-wide popover: a plain sentence, then `Remove` (danger on hover, with Undo) and `Open file`. Normal rows keep the slot empty. | D22, D24, D41, D63 (L81) |
| V5-R28 | `Filter` opens a two-level menu (field, then value). Each pick becomes a removable chip (`field \| value \| x`) in a row under the tab head that exists only while a filter is active, with `Clear`. The field menu shows a count per field with active picks. | D37 |
| V5-R29 | CHANGED (D63 L81): filter fields and values: Status (`Never ran`, `Heavily used`); CLI (In Claude Code, In Codex, In both, In one only); Owner (Mine, Plugin); Rank (`Top 10 most used`, `Top 25 most used`, `Least used 10`, `Never ran`, tiers `Top 20%`, `Middle`, `Bottom 20%`); Last ran (Today, This week, Over 30 days ago, Never). AND across fields, OR within a field. | D34, D35, D63 (L81) |
| V5-R30 | `View` holds `Group by` (None by default, Status, CLI presence, Owner, Rank tier; `Kind` went with `All`, D49) and `Order by` (Name, Sessions by default, Last run). Group bands exist only while a grouping is on (V5-R55, treatment 1). The order line above the list reads "Ordered by sessions" plus "· Grouped by …" when grouped. | D27, D30, D33, D36, D49, D64 (L80) |
| V5-R31 | Rank is never printed on rows. It exists as filters, the `Rank tier` grouping and the pane's counts. | D23, D34 |
| V5-R32 | A bottom bar appears while one or more rows are picked: count, the logo strip acting on the whole selection, `Remove`, and a clear action. It floats 48 above the bottom edge and moves the toast up (104). | D28 |
| V5-R33 | CHANGED (D58, D64 L80): detail pane (padding 32 40 40, at most 640 wide, 24 between sections): head (48 tile with the category glyph in its colour, name 20/28, meta line, plugin tag when plugin-owned, logo strip at the right), plain-sentence description (`InventoryItem.description`), verdict panel (neutral verdict glyph plus sentence), "Sessions by CLI" with a meter per detected CLI (28/32 count with the unit "sessions", 8 pt bar, last run; a dashed line and "Not in <CLI>" when absent), "Lives in" file list, and actions (`Open file`, `Remove`). Counts live only here. | D8, D14, D19, D20, D23, D58, D64 (L80) |
| V5-R34 | Meter bars follow identity: Claude clay, Codex foreground. State uses the success, warn and danger tones only. An unmeasurable count is never drawn as zero. | D8, D23 |
| V5-R35 | The status bar (32) lists the working keys of the page and "Counted from local logs" at the right. | D31 |

### Interaction

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R36 | CHANGED: one key, one meaning across pages (BRIEF-wireframe rule 6), recommended map pending the owner's word (open question 2): `j`/`k` and arrows move the current row; `Return` opens the row detail (Skills: moves focus to the pane actions); `x` picks a row (Skills only); `a` adds or copies to the other CLI; `r` removes, with Undo (`Delete` too); `o` opens the file or session; `s` stops a session (Activity Running, through the confirmation); `c` copies (a failed command, or `/usage` on Limits); `u` shows unused windows (Limits); `/` opens Filter; `z` undoes; `1` to `4` switch Agents tabs and `1` to `3` Activity tabs; `⌘R` refreshes Limits (the mock's `r`); `⌘1` to `⌘3` switch sidebar pages; `Esc` closes. Each page's status bar shows its keys as `Kbd` caps. | D11, D68 (L79) |
| V5-R37 | `⌘K` (and the sidebar search row) opens the command palette, restyled with the same tokens (560 wide, 48 field, 32 rows, 32 footer). It lists real commands only. `Esc` closes any popover, menu, dialog or the palette and returns focus to its origin. | D11 |
| V5-R38 | CHANGED: every write (add, remove, copy, change a verdict, dismiss) shows a toast with `Undo` and its `Z` cap for 5 s (the kit's duration; was 7 s), and Undo restores the previous state exactly, bulk actions included. Every write to agent configuration goes through the Journal and keeps a restorable copy (PRODUCT.md). | D21, D24, D28, D31, D41, D65 (L78) |
| V5-R39 | Menus: arrows move, `Right` opens a submenu, `Left` closes it, `Return` toggles a value. Filter menus are checkbox menus, `Group by` and `Order by` radio menus; the picked value shows a tick. | D37 |

### Accessibility

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R40 | WCAG AA in both appearances: text 4.5:1 on its real composited surface (tab chips, count circles, the selected row, Answer text, `fg3` where it carries text); controls, meaning-carrying icons, logo state and the focus fill 3:1. | D13 |
| V5-R41 | CHANGED (D57): visible focus on every control is a fill change (`sel`, or the control's hover fill one step stronger), never an outline or ring, on buttons, inputs, tabs, rows, logos and bands. | D57 |
| V5-R42 | Reduced motion removes the 120 ms transitions, the popover rise, the logo-badge pop and the skeleton pulse. Nothing animates beyond fades and short transforms otherwise; no looping animation outside a loading skeleton. | D12 |
| V5-R43 | Colour never carries state alone: a verdict has a glyph and a sentence; a lit logo has a badge as well as opacity; every logo toggle, warning slot, tab, band and menu item has an accessible name and value (for example "Codex: not in Codex, press to add"). | D21, D31 |

### UX principles

Rules under the look: `~/.claude/rules/quality/ux.md` (UX1 to UX4), `~/.claude/rules/quality/ui-process.md` (UP1 to UP7) and the "UX principles" section of [PRODUCT.md](../../PRODUCT.md). Checked by V5-A15 to V5-A17 and V5-A24.

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R44 | Jobs in priority order (PRODUCT.md); a higher job wins a conflict. Each page states its question and job (UX brief table); every UI decision names the job it serves. | D38, D51, D52 |
| V5-R45 | CHANGED (D46, D64 L80, D65 L78): vocabulary follows GLOSSARY.md. `Agents` names the page only; `Subagent` is the item; `CLI` is Claude Code or Codex and never an agent; `Rule` is one permission entry; `Instructions` are `CLAUDE.md` and `AGENTS.md`; `Runs` count hooks only, `Sessions` count skills and subagents; `Ran`, `Never ran`, `Unmeasurable`, `Missing`, `Window`, `Session`, `Stop`, `Estimated cost`, `Journal`, `Undo` mean one thing each. Banned in visible strings, accessible names and docs of the built pages: a CLI called "agent", a subagent called "CLI", a generic "item" label, "pending", "not counted yet", "not measured yet", "dead" for an item that never ran, "runs" for skills or subagents. The `agent` wire value of `InventoryKind` stays (D64 L80). | D39, D46, D64 (L80), D65 (L78) |
| V5-R46 | Colour, one meaning. Green, amber and red are exclusive to state (`ok`, `warn`, `bad`). Category hues, CLI identity colours (Claude clay, Codex mono) and the accent stay outside the state hue families, and no two categories share a hue. | D40 |
| V5-R47 | Detection and action together. A flagged row offers its fix in the same row within one hover or click (warning popover, detail popover, Answer card). Every write has Undo. `Stop` is the one exception: no Undo, and a confirmation that names the pid and the consequence (V5-R59). | D41 |
| V5-R48 | The principles live in two places: shared rules in `~/.claude/rules/quality/` and Reins specifics in PRODUCT.md. Briefs to agents reference both and the frozen mock; acceptance checks them. | D42, D55 |

### App structure and shell

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R49 | The sidebar pages are `Agents` (`⌘1`), `Activity` (`⌘2`) and `Limits` (`⌘3`); `Settings` opens from the sidebar footer. `Agents` holds the tabs `Skills`, `Subagents`, `Hooks`, `Rules` (no `All`); `Activity` holds `Running`, `Failed`, `Files`. The `Loadout` and `Rules` sidebar pages go. | D43, D46, D47, D49, D50 |
| V5-R50 | Sidebar (220 wide, padding 0 16 16, on `bgSide`): window-button row (48); product row (40: the app mark in an accent tile, the product name from one constant, so the SV9 rename touches one place); search row (40, `⌘K` cap, opens the palette; 8 above, 20 below); the page items (40 high, 4 apart, glyph, label, and Agents' total item count at the right; current item `sel` fill and 500 weight); flexible space; CLI status rows (32 high, 4 apart, a hairline and 12 above them): Claude Code, Codex and Gemini CLI, each with its logo and a state (`reading` with a success dot; `not installed` or `no log` with a muted dot); footer: `Settings` (36) and the appearance toggle (36 x 36). The current Limits sidebar block is not in the mock and goes (C16). | D66, D68 (L79) |
| V5-R51 | Content panel: inset 12 from the window on top, right and bottom; `bgPanel`, radius 8, 1 px `hair` border, top-edge highlight. Inside, top to bottom: the tab head (60; tabs at the left from a 32 edge, actions at the right ending 32 from the edge; toolbar buttons 32 high, padding 0 12, borderless; menus open 52 below its top), the filter chip row (padding 8 12, only while a filter is active), the page canvas, and the status bar (32, hairline above, keys at the left, the data source at the right). Limits has an empty tab area and one `Refresh` button. | D29, D66 |
| V5-R52 | Split layout for Subagents, Hooks, Rules, Activity and Limits: a 12-column canvas with 32 padding and 24 between cards; the left half (6 columns) stacks the small cards, 24 apart, the Answer card first; the right half (6 columns) is one tall spine card holding the page's main list as bands. Below 700 pt of canvas width both halves span the full width, small cards first. When the canvas is taller than the window, it scrolls inside the panel (the cost D66 accepted); a small card with a fixed maximum height scrolls inside itself. | D45, D54, D56, D59, D61, D66, D67 (L77) |
| V5-R53 | Answer card: a card titled `Answer`, body padding 4 20 24 with 20 between parts. One sentence at the primary-datum size, derived from the page's data by one function (never a fixed string), then optionally a verdict box (neutral glyph, bold title, text, small line) and the fix actions inside the card. When nothing needs the user, the sentence says so plainly and the card shows no fix button. When more than one row needs the user, it names the first and says "N more are marked in the list". Sentence size: 28/32 600 as the mock renders it, pending open question 1 (PRODUCT.md says 20). | D51, D52, D59, D60, D68 (L79) |
| V5-R54 | Card (the Tile, D56): `bgRaise`, 1 px `hair` border, radius 8, top-edge highlight, no drop shadow, never nested. Header 52 (padding 0 12 0 16): title 16/24 600 (-0.01em), an optional count 13 `fg3` that names its unit and range ("4 commands, last 14 days"), an optional state glyph with a popover, optional 28-high actions, and a collapse chevron. Body: rows (padding 0 12 16), or free content (padding 4 20 24, 20 apart), or an empty state, or a loading skeleton of three bars. | D56, D61, D66 |
| V5-R55 | Band (disclosure group inside a card or the Skills list): header 44, radius 8, `bgBand` fill (treatment 1), chevron, an optional logo or glyph, label (13/600), count, optional state glyph and right-aligned extras. 32 above a band, 0 above the first; collapsed bands that follow each other sit 10 apart, except on Hooks, where a run of collapsed bands shows as a two-column grid of band headers 8 apart (mock). Bands that hold a problem come first and open; the others start collapsed unless nothing anywhere needs the user (then the first opens). The user's open and closed choices are remembered until the app quits; a write never folds the band of the row it changed. | D59, D61, D66 |
| V5-R56 | Row in a card: 44 high, the same block as the Skills list row (inset, radius 8, divider, current-row fill), holding in order whichever of these the page uses: name (450), secondary text (12, `fg3`, fixed widths per page), a bar (8 high, radius 4, `track`, fill neutral `fg2`, warn at 20% left or less, danger at 5% or less), a share (20/28 600), a count (13, `fg2`), the logo strip, the warning slot. | D54, D59, D60, D66 |
| V5-R57 | Row detail: `Return` on the current row, or a click on it, opens the detail popover anchored to the row (below it; above it near the bottom edge; clamped 8 inside the window): head (logo or glyph, name, a sub line), plain sentences (one per CLI where both apply), the actions with their key caps. Same 272-wide popover surface as the warning popover (padding 12, 12 apart, `bgPop`, `hair2` border, shadow, 120 ms rise). `Esc` returns focus to the row. | D41, D54, D68 (L79) |
| V5-R58 | Figures and chart blocks: `Stats`, 2 to 4 figures (20/28 600 over a 12/16 `fg3` label, columns at least 88 wide, 12 apart); `Column chart`, one bar per bucket, 72 high, 2 apart, top radius 2, neutral `fg3` fill, the current bucket `fg`, an empty bucket as a 2 pt `hair2` line, a hairline base, an axis line of 11 pt labels under it (first bucket, what is counted and over what range, "today"). Approved with the mock (D68). | D61, D68 (L79) |
| V5-R59 | Stop confirmation: a 400-wide dialog centred over the window on the scrim (padding 20 20 16, 8 apart): title `Stop "<session title>"?` (14/20 600); body "Sends SIGTERM to pid <pid> (<CLI>, <project>). Unsaved work in that session may be lost. This cannot be undone."; small line "Reins checks that the pid still belongs to this session before it sends anything."; actions at the right, 12 above: `Cancel` with `esc`, and the solid danger button `Stop session` with the stop glyph. Focus starts on `Cancel`; `Tab` cycles the two buttons. After a stop the toast reads "Sent SIGTERM to pid <pid>. "<title>" is stopped." with no Undo. The pid is the real `ActivitySession.pid`, re-validated first (S-R4). | D41, D65 (L78) |
| V5-R60 | A number appears once on a page, where it answers a question (D60): no small card repeats the spine's figures. Every number names what it counts and its time range. The Next resets card shows no share; no reset tick on bars. | D59, D60 |
| V5-R61 | The tab head of Subagents, Hooks, Rules and Activity holds the tabs and ONE `Filter` button (one menu level when the page has one field); no scope control, no `View`, no other button. Skills keeps its own head (V5-R19); Limits has `Refresh` only. Activity's Files tab has no filter. | D29, D37, D54, D68 (L79) |
| V5-R62 | Every page renders the states its mock presets name: Skills (normal, nothing matches with `Clear filters`, empty category); Subagents (sample, none yet, loading, Codex not installed, 40 subagents scrolling, all healthy); Hooks (sample, healthy, many, none, Codex not installed, loading); Rules (sample, healthy, none, loading, Codex not installed, 60 rules, invalid settings file); Activity (sample, healthy, nothing running, loading, many sessions, no failures, no files); Limits (sample, healthy, all low, 50+ windows, stale read, unknown window, no reading yet, not installed, unreadable, failed read with `Retry`, loading). | D54, D68 (L79) |

### Subagents (Agents > Subagents)

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R63 | Canvas (split, spine right): small cards `Answer` and `In one CLI only`; spine card `Subagents` with a `Group: <field>` button in its header (radio menu: CLI presence by default, Model, None). Answer sentence: "<N> subagents never ran and can run Bash." naming the first in a verdict box (presence, tools sentence, "Added <when>. No session in the local logs since.") with `Review` (selects the row in the spine and opens its detail) and `Remove`; otherwise "Every subagent has run." or "No unused subagent can run Bash." `In one CLI only` lists subagents whose other logo can be switched on, each with an `Add to <CLI>` chip, and a note naming the ones left out and why; the card is dropped when it has no row. | D51, D52, D61, D67 (L77), D68 (L79) |
| V5-R64 | Row: name, model (128 wide; hidden when grouped by model), sessions text ("12 sessions", "never ran"), logo strip (toggle per V5-R25; the only copy is not toggleable), warning slot: lock (plugin-owned, read-only), warn triangle (never ran and can run Bash), neutral clock (never ran, cannot run Bash; or newly added). Detail popover: one line per CLI (Claude Code: model and tools; Codex: model and effort, "No tool list per subagent"), sessions and last session, `Add to <CLI>` (`a`) and `Remove` (`r`); plugin-owned shows the lock note and no actions. Filters: Status (Never ran, plus Unmeasurable only if the engine reports it), CLI, Can touch (Bash; Edit, no Bash; Read only; Codex only), Owner. Hint bar right: "Sessions counted from local logs". A copy into the other CLI writes the name, description and instructions only (G10, settled 2026-11-10): the popover sentence above `Add to <CLI>` and the note under the `In one CLI only` card say so before the click (`SubagentsWording.copyNote(to:)`), and the toast keeps its note. That a Claude Code subagent with no `tools` line can use every tool is unverified (V5-R75). | D21, D24, D31, D41, D49, D64 (L80) |

### Hooks (Agents > Hooks)

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R65 | Canvas: small cards `Answer`, `Missing in Codex` and `Can't copy to Codex`; spine card `Hooks` with one band per event: the events both CLIs share in lifecycle order, then Claude Code-only events, then Codex-only events; an event only one CLI has shows that CLI's logo in its band header; a band with a hook that can't run carries the danger glyph and comes first. Answer sentence: "<N> hooks can't run, <M> are missing in Codex." (or one half, or "Nothing needs you."), with a row per dead hook (name, "<event> · script gone", `Remove`) and one row "Claude Code runs them, Codex doesn't" with `Copy <M> to Codex`. `Missing in Codex` rows: name, event and matcher, `+ Codex`. `Can't copy to Codex` rows: name and the short reason, a `Why` header button whose popover explains the reasons. A small card with no row is dropped. | D51, D52, D61, D67 (L77), D68 (L79) |
| V5-R66 | Row: grey hook glyph, name, matcher, logo strip (lit: remove from that CLI; the only copy is not toggleable; dim: copy there; no toggle at all when that CLI cannot take the hook), warning slot (danger triangle: script gone; neutral clock: Unmeasurable). One rule decides whether a hook can go to a CLI, used by the logos, `a`, the detail, both small cards and the Answer: the CLI has the event, runs the handler kind, the script exists. Codex hook runs are Unmeasurable (glossary; the engine's `UsageCellState.unmeasurable`), never a number. Detail popover: one line per CLI (handler kind, matcher, runs or "Unmeasurable" or "script <path> is gone"), `Copy to <CLI>` (`a`) and `Remove` (`r`), plus "Tool names in a matcher can differ between the CLIs (unverified)" when copying. Filters: CLI presence, Handler, Status (Can't run, Missing in Codex, Can't copy to Codex), Event. Hint bar right: "Read from hook config. Reins never runs a hook". | D21, D24, D31, D41, D53, D64 (L80), D65 (L78) |

### Rules (Agents > Rules)

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R67 | Canvas: small cards `Answer` and `Redundant rules`; spine card `Permissions` with a column head (Claude Code; Codex with a lock, or "Codex not installed") and one band per tool family (Bash, Edit/Write, Read, Web, MCP); each band header shows the family's count, Claude Code's stance (one verdict, or "Allow n · Ask n · Deny n") and Codex's fact in its own terms; a family open in one CLI and denied in the other carries the warn glyph and comes first, open. Under the bands: "Codex is read only here. Approval policy <value>, from ~/.codex/config.toml." Answer sentence: "<Family>: <open\|off> in Codex, <denied\|allowed> in Claude Code." with a Claude Code row whose verdict button opens the Allow/Ask/Deny menu for the whole family, a read-only Codex row with a lock, and "Also <families>."; otherwise "No tool is open in one CLI and denied in the other." `Redundant rules` rows: pattern, "Covered by <pattern>", `Remove`. | D47, D48, D51, D52, D61, D67 (L77), D68 (L79) |
| V5-R68 | Row: pattern (truncated, full text on hover), Claude Code verdict (168 wide). Detail popover: the pattern, what the verdict means ("Claude Code asks you each time."), a verdict button (menu) and `Remove`. Every change writes `~/.claude/settings.json` through the Journal with Undo ("Undone. ~/.claude/settings.json is back to how it was."). An invalid settings file shows the danger glyph on the spine, hides the rules ("Rules stay hidden until ~/.claude/settings.json parses, so Reins writes nothing over it."), and the Answer names the file and line with `Retry`. Filter: Verdict in Claude Code (one menu level). Codex is read only (D48). Hint bar right: "Read from ~/.claude/settings.json". Project and local scopes and adding a rule are not in the mock (open question 4). | D41, D47, D48, D68 (L79) |

### Activity

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R69 | Tabs `Running`, `Failed`, `Files`, each with its glyph and count, active chip in the accent. `Filter` (field CLI: Claude Code, Codex) on Running and Failed; the chip row stays on every tab so filtered counts are explained, and each Answer names the filter it answers for ("… in Codex"). Keys per tab as in V5-R36; hint bar right: "Read from local session logs". | D50, D61, D68 (L79) |
| V5-R70 | Running: `Answer` ("<N> waiting for you" with a verdict box: session title, "<CLI> asks: <question>", the command and project, and `Open` and `Stop…`; or "Nothing is waiting for you."); `Today` (`Stats`: tool calls today, estimated cost today, longest running session while it runs; a 14-day `Column chart` of estimated cost per day; a `Limits` button); spine `Running` ("<N> sessions") with one band per CLI (waiting first, open when it has a waiting session) plus a Gemini CLI band "no log". Row: title, project (112), state ("waiting", "idle", "running <tool>", 104), warn triangle when waiting. Detail popover: the question, "Answer in the terminal. Reins only shows the question.", `Open` (`o`) and `Stop…` (`s`). | D41, D50, D61, D65 (L78, L79) |
| V5-R71 | Failed: `Answer` ("<N> still failing" with a verdict box: command, reason, "<CLI>. No later run has passed.", `Copy` and `Open`; or "No command is still failing."); `Passed later` (one sentence and `Dismiss passed`, with Undo; dropped when empty); spine `Failed commands` ("<N> commands, <range>") with one band per CLI. Row: command, reason (up to 176), "<n> times", "still failing" or "passed later", warn triangle while still failing. Detail popover: reason and counts with the range, `Copy` (`c`), `Open` (`o`), `Dismiss` (with Undo). | D41, D50, D60, D61, D68 (L79) |
| V5-R72 | Files: `Answer` ("<file> is today's most-edited file." with its path and `Open`; or "No file was edited today."); `Busiest projects` ("file edits, <range>": bar rows with an edit count and an open button); spine `Edited files` ("<N> files") with bands `Today` and `Most edited, <range>`. Row: file name, folder (up to 200, right-aligned), "<n> edits". Detail popover: edits and `Open`. | D50, D60, D61, D68 (L79) |

### Limits

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R73 | Canvas: small cards `Answer`, `Next resets`, `Source`; spine card `Usage windows` with one band per CLI (Claude Code, Codex, Gemini CLI), each with its logo, count, a state glyph when a window is low and "read <age> ago" when stale. Answer: "Do heavy work in <CLI> until <time>." with a verdict box ("<other CLI> is the tighter one", "<window> has <n>% left.", stale reads named), and `Copy /usage` (`c`) in the card header; or "Hold heavy work until <time>." when both are low; or "No reading yet." `Next resets` rows: time, logo, "<CLI> <window>", no share (D60). `Source`: per CLI the plan and the read age (or not installed, or no reading), "Gemini CLI no log", `Refresh` and `Show unused` / `Hide unused`, and "Current snapshot only. No history." | D50, D51, D59, D60, D61, D68 (L79) |
| V5-R74 | Window row: name (128), a bar across the rest of the row, the share left (20/28 600, 64 wide) or "—" when unknown, warning slot. Fill neutral; warn at 20% left or less, danger at 5% or less (the current `LimitTone` thresholds); a reading 6 hours old or more is stale (neutral clock: "Read <age>. The real number may be lower." with `Refresh`); a passed reset is unknown (dashed track, "It is not 0%."). States per V5-R62; Gemini CLI reads "Not measurable. Gemini CLI exposes no usage numbers." Snapshot only (D50). The ten-cell `Ruler`, the 340 window list and the `LimitFigure` page are replaced. | D50, D59, D60, D66 |

### Data truth and arrangement

| ID | Requirement | Ledger |
| --- | --- | --- |
| V5-R75 | Every number, share, date, range and sentence shown is derived from the engine's data in the right direction (left vs used, promised vs actual) and checked against real data, not the mock's `data.js` (W23, UP6). An element whose data the app does not have is not built with invented values: it is left out, named as a departure for the eye task, and its data need goes to the engine owner (go-core plan, D-5). Known gaps are listed under "Data the app may not have". | D60, D63 (L81), D65 (L78) |
| V5-R76 | Pages differ only by the arrangement of the shared blocks. A page never restyles a block and adds no border, colour, type size, radius, shadow, gradient, looping animation or native control. A need the blocks cannot express gets a block spec, a gallery specimen and the owner's eye approval before a page uses it. | D44, D45, D54, D55, D56 |

## Token table

Values are read from `system/shared.css`. "Swift today" names what the row replaces or extends in [`Tokens`](../../Sources/Reins/Tokens) and [`Components`](../../Sources/Reins/Components); "new" has no counterpart. Mock-only values (`desk`, traffic-light colours, the dev panel) are not tokens.

### Surfaces and lines

| Token | Dark | Light | Swift today |
| --- | --- | --- | --- |
| `bgSide` (sidebar, window) | `#0B0C0D` | `#F4F4F5` | replaces `Palette.well` |
| `bgApp` (search field ground) | `#0F1011` | `#F4F4F5` | replaces `Palette.background` |
| `bgPanel` (content panel, list, pane) | `#131416` | `#FFFFFF` | replaces `Palette.surface` as the page ground |
| `bgRaise` (cards, buttons, meters, chips) | `#191A1D` | `#FBFBFB` | replaces `Palette.surfaceRaised` |
| `bgSunk` (verdict box) | `#0E0F10` | `#F6F6F7` | new |
| `bgPop` (menu, popover, toast, bottom bar, palette, dialog) | `#1B1C1F` | `#FFFFFF` | new |
| `bgBand` (band header) | `#1B1C20` | `#EEEFF2` | new |
| `hair` | white 7.5% | black 8% | replaces `Palette.divider` and `border` |
| `hair2` (control outline, overlay edge, chart base) | white 12% | black 14% | extends `Palette.border` |
| `rowDivider` | white 5.5% | black 6.5% | new |
| `hi` (top-edge highlight) | white 5% | white 90% | new |
| `hover` | white 4% | black 3.5% | replaces `Palette.hover` |
| `sel` (current row, current nav item, focus fill) | white 6.5% | black 5.5% | replaces `Palette.selection` |
| `track` | white 7% | black 6.5% | replaces `Palette.track` |
| `trackHi` | white 12% | black 10% | new |
| `kbdBg` / `kbdBorder` | white 6% / 10% | black 3.5% / 12% | extends `Kbd` |
| `scrim` | black 50% | `#141418` 25% | replaces `Palette.overlay` |

### Text

| Token | Dark | Light | Swift today |
| --- | --- | --- | --- |
| `fg` | `#F2F3F4` | `#1B1C1F` | replaces `Palette.text` |
| `fg2` | `#A3A7AE` | `#5E626A` | replaces `textSecondary` |
| `fg3` | `#6B7078` | `#8B8F97` | replaces `textTertiary` (raised where it carries text, V5-A2) |
| `fg4` (disabled, separators) | `#4A4E55` | `#B7BAC0` | new; not for text a user must read |

### Accent, state, identity

| Token | Dark | Light | Swift today |
| --- | --- | --- | --- |
| `accent` shade 1 (build value) | `#4F86F7` | `#2563D9` | replaces `Palette.accent` and `accentSolid` |
| `accent` shade 2 (candidate) | `#6D83F5` | `#3F4FD6` | |
| `accent` shade 3 (candidate) | `#3DA1EE` | `#0A6CC4` | |
| `accentBg` (picked row, filter count) | accent 16% | accent 10% | extends `selection` |
| `ok` | `#4CB782` | `#2F9E6B` | replaces `success` |
| `warn` | `#E2A33C` | `#C4811A` | replaces `warn` |
| `bad` | `#E5604F` | `#D2442F` | replaces `danger` |
| `mute` (off dot) | `#8A8F98` | `#7A7F88` | new |
| `onVerdict` (glyph cut-out) | `#0F1011` | `#FFFFFF` | extends `onAccent` |
| `claude` | `#D97757` | `#C65F3E` | replaces `Palette.claude` |
| `codex` | `#F2F3F4` | `#1B1C1F` | replaces `Palette.codex` (the blue `#1596D6` goes) |
| `*Ink`, `*Tint` twins | | | dropped unless a built page still needs one |

Verdict glyphs are one neutral colour (`fg2`, D58); the 2026-11-06 verdict-to-colour mapping is withdrawn. The kit's `nm` colour (`#8C94C8`) is not used.

### Category colours

| Token | Dark | Light | Notes |
| --- | --- | --- | --- |
| `catSkill` | `#A78BFA` | `#7C5CE0` | Skills |
| `catSubagent` | `#D974E0` | `#B83CC8` | Subagents; set 1 (set 2 swapped it with Hooks: `#4FC9E6` / `#0C86A6`) |
| `catHook` | `#35C0DA` | `#0E8BA8` | Hooks; set 1 (set 2: `#E56BD0` / `#C0389F`) |
| `catRule` | `#E8709F` | `#D2487F` | Rules; about 30° of hue from `bad`, checked by V5-A16 |
| Reserved state hues | `ok`, `warn`, `bad` families | same | no category, identity or accent hue falls inside them |
| Tab chip, inactive | `fg` 7%; hover 12% | same | text, glyph and count `fg2`; hover `fg` |
| Tab chip, active | category 26%; focus 34% | same | text (600), glyph, count in the category colour; in light, text and count mixed 68% with black |
| Tab count circle | inactive `fg` 12%; active category 40% | same | 10 pt, min 16 x 16, padding 0 4 |

### Type

Body is 13/20 weight 400, Inter with `cv11`, `ss03` and tabular figures. Roles, mapped to [`ReinsType`](../../Sources/Reins/Tokens/ReinsType.swift):

| Use | Mock | Swift today |
| --- | --- | --- |
| Tab count, filter count | 10/1, 500, tabular | new `micro` |
| Section and nav labels, kbd, menu headings, chart axis, secondary meta | 11/16, 500 (labels) or 400 | new `small` |
| Controls, menus, filter chips, captions, row secondary text, CLI status rows, status bar | 12/16, 400 or 500 | `caption`, `label` |
| Body, row name (450), buttons (500), tab label (500; active 600), band label (600), count in a row | 13/20 | replaces `body` 14 and `rowTitle` 14 |
| Palette field | 14/20 | `body` |
| Card title | 16/24, 600, -0.01em | `title` |
| Pane heading, row share, stat figure | 20/28, 600, -0.01em | new `heading` |
| Answer sentence, pane meter count | 28/32, 600, -0.02em (open question 1) | replaces `figure` 24 |

Settings > Font size keeps moving every role together (`TypeScale`).

### Rhythm and sizes (D66)

The mock's four spacing tokens are the custom properties of the rhythm block; every other value there is a component size. In Swift, spacing tokens live in `Rhythm` ([`PageLayout.swift`](../../Sources/Reins/Components/PageLayout.swift)) and sizes in `Metrics` ([`Metrics.swift`](../../Sources/Reins/Tokens/Metrics.swift)); a page holds none of them (V5-R8).

| Token or size | Value | Swift today |
| --- | --- | --- |
| `--rh-edge`: content edge (canvas padding, tab head side padding) | 32 | `Metrics.pagePadding` 24 |
| `--rh-card`: between cards (and between stacked small cards) | 24 | `Rhythm.cards` 24 |
| `--rh-group`: above a band | 32 | `Rhythm.regions` 32 |
| `--rh-side`: sidebar padding (sides, bottom) | 16 | new |
| Window content inset (panel margin top, right, bottom) | 12 | new |
| Sidebar width | 220 | `Metrics.sidebarWidth` 232 |
| Sidebar product row, search row, page item | 40, 40, 40 (padding 0 12, 4 apart; search 8 above, 20 below) | `sidebarItemHeight` 48 |
| Sidebar group label | 11/16, padding 24 12 8 | new |
| CLI status row | 32 (padding 0 12, 4 apart, 12 above, 8 below) | new |
| Sidebar footer button, icon button | 36, 36 x 36 | new |
| Tab head | 60 | `topBarHeight` 48 |
| Tab chip | 36 high, padding 0 14, 10 apart | new |
| Toolbar button (Filter, View, Refresh) | 32 high, padding 0 12 | `controlHeight` 28 |
| Filter chip row; chip | padding 8 12, 8 apart; chip 24, close 24 wide | `FilterChip` 28 capsule |
| Row (list and card), band header | 44, 44 | `rowMinHeight` 48 |
| Card header | 52, padding 0 12 0 16 | `cardHeaderHeight` 56 |
| Card body, rows; free content | padding 0 12 16; padding 4 20 24, 20 apart | new |
| Band spacing | 32 above, 0 above the first, 10 between collapsed bands; Hooks collapsed grid 2 columns, 8 apart | new |
| Card maximum heights (page layout) | Limits small cards 380, spine 680; Activity spine 680; Rules small cards 304 | new, per page in `Metrics` |
| Skills list | 46% width; order line 32 (padding 4 20 0 16); list padding 0 8 16 | `rowMinHeight` 48 |
| Logo toggle | 24 box (radius 6), 20 logo, 10 badge with a 6 glyph and a 1.5 ring in the ground colour | `CLIMark`, `loadoutActionsWidth` 60 |
| Warning slot | 24 | new |
| Menu | 208 wide (submenu 232), padding 4, item 28, radius 6 | new |
| Popover | 272 wide, padding 12, 12 apart, radius 8 | new |
| Detail pane (Skills) | padding 32 40 40, max 640, 24 apart; head tile 48; file row 32; meter padding 16; meter bar 8 (radius 4) | new |
| Bottom bar | 44 high, radius 8, 48 above the bottom | new |
| Toast | 40 high, radius 8, 24 from the right, 48 above the bottom (104 with the bottom bar), 5 s | `toastBottomInset` 48, `toastDuration` 7 s |
| Status bar | 32, padding 0 16, 16 apart | `hintBarHeight` 32 |
| Buttons | 32 (pane, Answer), 28 (popover, card header, bottom bar, dialog), padding 0 8 0 12, radius 6, `hair2` border, top highlight | `controlHeight` 28 |
| Dialog | 400 wide, padding 20 20 16, 8 apart, actions 12 above | `dialogWidth` 420 |
| Kbd | 18 high, min 18 wide, 2 px bottom edge | `kbdHeight` 20 |
| Palette | 560 wide, field 48, row 32, footer 32, 112 below the window top | `paletteWidth` 600, `paletteRowHeight` 36 |
| Radii | 4 (kbd, checkbox, chart bar top), 6 (controls, tab chips, nav items, logo, warning slot, menu items), 8 (panel, cards, rows, bands, menus, popovers, toast, dialog), 12 (window) | `groupRadius` 12 becomes 8 for cards |
| Motion | 120 ms hover and press; popover rise 120 ms; logo pop 180 ms; bar width 150 ms | `ReinsButtonStyle` 0.15 s |
| Shadows | popover and toast `0 8 32` black 40% plus `hi`; palette and dialog `0 24 64` black 50%; window ring 1 px at 8% | `overlayShadow*` |

## Components

States are the ones the gallery shows in both appearances. "New" blocks are built beside the old ones and the old ones are deleted at cut-over (W17); a component whose change is token values only is edited in place (D53). File names follow F3 (no generation suffix) and F5/F6.

| Component | States | Replaces or new |
| --- | --- | --- |
| Shell: sidebar with product row, search row, page items, CLI status rows, footer | rest, hover, current, focus; CLI reading, not installed, no log | replaces [`SidebarView`](../../Sources/Reins/Shell/SidebarView.swift), [`SidebarItem`](../../Sources/Reins/Components/SidebarItem.swift) (48) and [`LimitsSidebarBlock`](../../Sources/Reins/Limits/LimitsSidebarBlock.swift) |
| Content panel with tab head, filter chip row, status bar | default, filtered | replaces [`TopBarView`](../../Sources/Reins/Shell/TopBarView.swift), [`PageLayout`](../../Sources/Reins/Components/PageLayout.swift) ground and [`HintBar`](../../Sources/Reins/Components/HintBar.swift) |
| Tab chip with count circle | inactive, hover, active (per category, accent for Activity), focus, light | new |
| Toolbar button (Filter, View, Refresh, scope) with menus | rest, hover, open, focus, filtered count | replaces [`ScopePicker`](../../Sources/Reins/Components/ScopePicker.swift) body and the ghost kind of [`ReinsButtonStyle`](../../Sources/Reins/Components/ReinsButtonStyle.swift) |
| Filter chip (`field \| value \| x`) and chip row with `Clear` | default, hover close, focus | replaces [`FilterChip`](../../Sources/Reins/Components/FilterChip.swift) |
| Card (Tile) with header, count, state glyph, actions, chevron | open, collapsed, loading, empty | new; replaces [`GroupedList`](../../Sources/Reins/Components/GroupedList.swift), [`CardHeader`](../../Sources/Reins/Components/CardHeader.swift) and [`ContentCard`](../../Sources/Reins/Components/ContentCard.swift) on rebuilt pages |
| Answer card body (sentence, verdict box, actions, "more" note) | needs you, nothing needs you, loading | new; replaces [`StatusLead`](../../Sources/Reins/Components/StatusLead.swift) |
| Band (header and body; collapsed grid variant) | open, collapsed, problem, hover, focus | replaces [`GroupLabel`](../../Sources/Reins/Components/GroupLabel.swift) and `SectionRow` |
| Row (list and card) with lead slot, checkbox, slots, divider | rest, hover, current, picked, current and picked, focus | replaces [`Row`](../../Sources/Reins/Components/Row.swift) usage and [`LoadoutRowView`](../../Sources/Reins/Loadout/LoadoutRowView.swift) |
| Bar, share, count cells | neutral, warn, danger, unknown (dashed) | replaces [`Ruler`](../../Sources/Reins/Components/Ruler.swift) and [`UsageCell`](../../Sources/Reins/Components/UsageCell.swift) bars |
| Logo toggle and strip | lit, dim, hover on lit (danger badge), hover on dim, pressed, focus, read-only, only copy, just-changed pop | replaces [`CLIDot`](../../Sources/Reins/Components/CLIDot.swift) and Loadout's `RowActionButton` pair |
| Warning slot and popover; detail popover | empty, warn, danger, neutral clock, lock, open | new; reuses [`ConfirmationDialog`](../../Sources/Reins/Components/ConfirmationDialog.swift)'s overlay tokens |
| Stats and column chart | 2, 3, 4 figures; buckets with zero and current | new |
| Verdict glyph and verdict box | five glyphs, neutral | new |
| Skills detail pane (head, description, verdict, meters, files, actions) | normal, never ran, newly added, plugin read-only, one CLI only, nothing selected | replaces [`FactTile`](../../Sources/Reins/Components/FactTile.swift) and `UsageCell` use |
| Bottom bar | hidden, shown, mixed | new |
| Toast with Undo and `Z` | shown, bulk text, no-Undo (Stop) | extends [`Toast`](../../Sources/Reins/Components/Toast.swift) |
| Confirmation dialog (Stop) with the solid danger button | open, focus on Cancel | extends `ConfirmationDialog`, replaces [`ActivityStopConfirmation`](../../Sources/Reins/Activity/ActivityStopConfirmation.swift) look |
| Buttons (normal, primary, danger, solid danger, icon) with optional key cap | rest, hover, pressed, disabled, focus | extends `ReinsButtonStyle` |
| `Kbd` | cap, on accent, on solid danger | extends [`Kbd`](../../Sources/Reins/Components/Kbd.swift) |
| Palette | open, empty, selected row | restyles [`PaletteParts`](../../Sources/Reins/Components/PaletteParts.swift) and [`CommandPalette`](../../Sources/Reins/Shell/CommandPalette.swift) |
| Empty state and loading skeleton | no items, nothing matches with `Clear filters`, loading | extends [`EmptyState`](../../Sources/Reins/Components/EmptyState.swift) |

Not touched: [`RailTab`](../../Sources/Reins/Components/RailTab.swift), [`ThemeTile`](../../Sources/Reins/Components/ThemeTile.swift), [`ReinsSwitch`](../../Sources/Reins/Components/ReinsSwitch.swift), [`ReinsMark`](../../Sources/Reins/Components/ReinsMark.swift) (Settings; tokens only).

## Mock substitutions (the ledger wins over the mock's text)

The side-by-side check (V5-A1) expects these differences from the frozen mock and no others.

| # | In the mock | Built | Why |
| --- | --- | --- | --- |
| S1 | `c3` tabs `Skills · Agents · Hooks · All`, one list mixing skills, subagents and hooks (`c3/index.html:83`) | tabs `Skills · Subagents · Hooks · Rules`; the Skills tab lists skills only; no `Kind` grouping | D46, D49 |
| S2 | "runs" for skills and subagents (`c3` meters, order "Run count", Subagents rows "12 runs", "Runs counted from local logs") | "sessions", order "Sessions", "Sessions counted from local logs" | D64 (L80), GLOSSARY |
| S3 | "Not measured yet", "Not counted", "not counted yet" for a newly added skill or subagent | `Never ran` with the neutral clock and "added <when>" | D63 (L81) |
| S4 | "Dead" for a skill that never ran in either CLI (`c3:107`); Status values Never ran, Dead, Not measured, Heavily used | `Never ran` (in both); Status values Never ran, Heavily used | D63 (L81), GLOSSARY |
| S5 | Codex hook run counts (`system/data.js` `hookRows`) and the hook state "Runs not attributable yet" | Codex hook runs read `Unmeasurable`; a Claude Code hook with no run reads `Never ran` | GLOSSARY "Unmeasurable", D63 (L81) |
| S6 | Small-card stacks 8 apart on Hooks and Subagents (`b-hooks:11`, `b-subagents:12`) | 24 apart, as on Limits, Activity and Rules | D66 ("nothing is hard-coded in a page") |
| S7 | Verdict colours in `c3`'s data (`VERDICT`) and group composition strip | neutral glyphs; no composition strip (it served the `Kind` grouping) | D49, D58 |
| S8 | Sidebar product row "R" / "Reins" (`system/shared.js:142`) | the product name and mark from one constant (renamed by the go-core plan, SV9) | SV9 |
| S9 | Keys: `c3` `f` filter, `Backspace` remove, `a` "add to Codex"; Limits `r` refresh | the V5-R36 map | V5-R36, open question 2 |
| S10 | Hint text "⌘K preview states"; `⌘K` "Preview" and "Layout" entries | `⌘K` opens the real palette | mock-only |
| S11 | Synthetic pids, "(mock only)" and "(stub)" toasts, fixed clock, the assumed ranges "last 14 days" and "last 30 days" (`b-activity:54`) | real pids, real actions, the range the engine covers (or no range label, open question 5) | V5-R75 |
| S12 | Toast 5 s with `Undo Z` | same (the 2026-11-06 text said 7 s) | D68 (L79) |

## Acceptance criteria

| ID | Check |
| --- | --- |
| V5-A1 | Side-by-side parity (W20, D68): each built surface is compared with its frozen mock page at 1440 x 900, per surface: shell and sidebar; Skills (normal, filtered, grouped, multi-select with bottom bar, warning popover, pane states); Subagents; Hooks; Rules; Activity Running, Failed and Files; Limits; the Stop dialog, toast, palette, menus and popovers. Each surface is judged on structure, content (with only the "Mock substitutions" as differences), look and theme, in dark and in light. Token counts, test counts and green builds never stand in for this check. |
| V5-A2 | A contrast test reads the tokens and checks every text and meaning-carrying pair on its composited surface at 4.5:1 (text) or 3:1 (controls, focus fill, state icons, logo state), in both appearances, including inactive and active tab text, count circles, `fg3` text, warning glyphs on `bgPanel` and `bgRaise`, Answer sentences on `bgRaise`, and `onVerdict` on a verdict glyph. A miss fails; the token is fixed, not exempted. |
| V5-A3 | `StyleBoundaryTests` covers every screen folder (Agents, Skills, Subagents, Hooks, Rules, Activity, Limits, Shell, Settings, and Loadout until cut-over), fails on the patterns of V5-R8 (the existing ones plus `.background(` with a colour, `.border(`, `.shadow(`, `.overlay(` with a stroked shape, gradients and `repeatForever`), holds no v5 file in its allowlist (an old screen file that hits only a new pattern may sit there until the cut-over deletes it), and has a test that every folder under `Sources/Reins` is either a listed screen folder or explicitly exempt (`Tokens`, `Components`, `Gallery`, `App`). |
| V5-A4 | `IconPolicyTests`: category glyphs come only from the MingCute generated set, content and sidebar glyphs only from the generated sets the owner keeps (open question 6), verdict glyphs only from Reins's own set, CLI logos only from `CLIMark`; no `Image(systemName:)` outside `Gallery/`; sizes never below 12; the credits string names every set in use. |
| V5-A5 | Skills model tests: flat order by sessions descending; tab counts; each filter field and value (AND across fields, OR within one); rank filters and tiers with ties; each Group by and Order by; the Never ran warning and the newly added note; plugin items read-only. |
| V5-A6 | Write tests against `TempHome` (S-R1): add to and remove from a CLI, bulk add and remove, copy a hook to Codex, change a rule's verdict (one and a whole family), remove a rule, dismiss a failed command, plugin refusal, the only-copy rule (D53), and Undo restoring the exact prior bytes; each file write goes through the Journal and keeps a restorable copy. |
| V5-A7 | Keyboard walkthrough per page in the built app with the V5-R36 map, menu arrows and `Tab` order: every control is reachable and shows the focus fill. Recorded in the plan with the observed result. |
| V5-A8 | Every logo toggle, warning slot, tab, band, card collapse button and menu item exposes a name and a value to VoiceOver; reduced motion removes every transition and the skeleton pulse. Checked in the built app and recorded. |
| V5-A9 | The About panel shows a credit for every icon set in use, each with a licence verified against its source (V5-R15). |
| V5-A10 | The gallery shows every component of the Components table in every listed state, in both appearances (`SPACEVIBE_GALLERY=1`, and `SPACEVIBE_SHOT_SCREEN=shell scripts/dev-fixture.sh --shots <dir>` for `gallery-dark.png` and `gallery-light.png`). |
| V5-A11 | Sweep (W21): each token, radius, height and word that changes app-wide ends with "changed N of M" from a repo-wide search, each skipped site named with its reason. Settings and every not-yet-rebuilt screen, in both appearances, show no breakage after the token change (contrast, truncation, overlap). |
| V5-A12 | `scripts/test.sh` reports `Test run with N tests … passed` with N above 0 and above the count before the work; `scripts/build-app.sh` prints `minos 15.0`; at cut-over `docs/DESIGN-LANGUAGE.md` is rewritten for the shipped language (D1) and `bash ~/.claude/scripts/docs-anchors.sh` reports nothing new. |
| V5-A13 | Runtime check (W22): every UI check runs in the owner's runtime, the bundle `build/Reins.app` opened with `open -n` on a synthetic home with the dev switch, after stopping any older instance, never the real `~/.claude`; per surface the report says what changed and what did not. |
| V5-A14 | Owner eye approval happens in ONE final task, after V5-A1 to V5-A13 and V5-A15 to V5-A24 have run: every surface, dark and light (light for the first time since D66), beside the mock. It records the owner's words per surface and the picks named in the open questions (accent shade, category set, Answer size, key map, sidebar glyphs, departures). Only the W17 cut-over may need a second look. |
| V5-A15 | Vocabulary audit: a search over every visible string, accessible name and doc of the built pages finds none of the words V5-R45 bans. Output pasted in the plan. |
| V5-A16 | Colour audit: a test over the palette proves every category and identity hue and the accent family sit outside the `ok`, `warn` and `bad` hue ranges in both appearances, and that no two categories share a hue. It fails on a collision. |
| V5-A17 | Flow audit: a walk of each built page proves every flagged state has its action within one hover or click, every write has Undo, and `Stop` shows its named confirmation. Recorded per page. |
| V5-A18 | Answer tests: each page's Answer sentence and actions come from one model function, with cases for a problem, several problems ("N more"), nothing needs the user, no data or loading, and a CLI not installed, on fixture data. |
| V5-A19 | States: shots of every state in V5-R62 per page, both appearances, from synthetic fixtures. |
| V5-A20 | Real data (W23): for every figure, share, date and range on every page, the plan records its source field, the fixture's value and the value shown; data the engine lacks is listed as a departure and not faked. The owner looks at the pages on their real home during the final eye task (read only). |
| V5-A21 | W17: the dev switch is honoured only in a debug build or a local bundle that `scripts/build-app.sh` made without `--distribution`, never in a distribution build (a `LaunchMode` test plus a check of the build flags); the old surfaces stay the default until cut-over; the cut-over change deletes the old surfaces and the switch in one change, with "changed N of M" for the removed names. |
| V5-A22 | Fit at 1440 x 900, per page: which card scrolls inside (Rules, the Subagents spine and the Hooks stack are accepted by D66 and D68), nothing clipped or overlapping; below 700 pt of canvas width the halves stack. Recorded. |
| V5-A23 | Conformance (UP5): the style-boundary test reports zero hits, and crops of the shared blocks (row, band header, card header, tab head, Answer card, popover) are compared with the same crops of the mock at the same scale, both pasted. |
| V5-A24 | Numbers once (D60): per page, each figure appears once and names what it counts and over what range. Recorded per page. |

The UX audits (V5-A15 to V5-A17, V5-A24) belong to the build, not to a separate approval stop.

## Traceability (W20)

One row per ledger line (68). Where an ID repeats in the ledger, the row names the line.

| Decision | Owner's words (quoted) | Requirements | Acceptance |
| --- | --- | --- | --- |
| D1 (L14) | "chỉ có setting là được polish rồi, còn lại tất cả đều chưa ổn" | V5-R7, V5-R49 | V5-A1, V5-A11 |
| D2 (L15) | "setting không phải mốc hay tham chiếu gì cả" | V5-R1, V5-R7 | V5-A11 |
| D3 (L16) | "linear app desktop làm app tham khảo" | V5-R1 | V5-A1 |
| D4 (L17) | "có lấy màu, lấy gần như toàn diện" | V5-R1, V5-R4 | V5-A1 |
| D5 (L18) | "icon có thể đổi màu được như linear để nhận diện tốt" | V5-R9 | V5-A4 |
| D6 (L19) | "q3 trung tính" | V5-R2 | V5-A1, V5-A2 |
| D7 (L20) | "q4 theo linear hoàn toàn đi" | V5-R4, V5-R16 | V5-A1, V5-A3 |
| D8 (L21) | "aprove" (icon colour by data state and entity kind; narrowed by D20, D58) | V5-R11, V5-R33, V5-R34 | V5-A1, V5-A4 |
| D9 (L22) | "aprove" (one thin-stroke set plus an own verdict set) | V5-R14 | V5-A4 |
| D10 (L23) | "aprove" (blue accent, 2-3 shades for an eye pick) | V5-R3 | V5-A2, V5-A14 |
| D11 (L24) | "aprove" (Linear's interaction primitives; layout clause superseded by D45) | V5-R36, V5-R37 | V5-A7 |
| D12 (L25) | "aprove" (no gradients; tonal layers, hairlines, top highlight) | V5-R5, V5-R42 | V5-A1, V5-A8 |
| D13 (L26) | "ok" (dark primary, light equal and verified every build) | V5-R6, V5-R40 | V5-A1, V5-A2 |
| D14 (L27) | "ok" (app icon and landing follow later) | Out of scope; V5-R33 only reads it | V5-A11 (no change to `site/` or the icon) |
| D15 (L28) | "aprove" (plan v4 replaced; contrast test and sunken track kept) | V5-R7 | V5-A2, V5-A12 |
| D16 (L29) | "aprove" (3 mock directions, owner picks by eye, then Swift) | V5-R8; the frozen mock is the picked direction | V5-A1, V5-A14 |
| D17 (L30) | "option C layout khá tốt" | V5-R18 | V5-A1 |
| D18 (L31) | "phần progress đang có vấn đề UI…" (superseded by D23) | V5-R22, V5-R33 | V5-A1 |
| D19 (L32) | "icon không được lấy y nguyên của linear, nên đổi icon loại khác" | V5-R9, V5-R14 | V5-A4 |
| D20 (L33) | "chỉ dùng màu icon khác nhau cho các danh mục như agent, skill thôi" | V5-R11, V5-R12, V5-R13, V5-R14 | V5-A1, V5-A4 |
| D21 (L34) | "hiển thị một list logo agent ở đó" | V5-R22, V5-R24, V5-R25, V5-R38 | V5-A1, V5-A6 |
| D22 (L35) | "thêm một popover khi hover vào mỗi logo agent" (superseded by D31) | V5-R25 (no logo popover), V5-R27 | V5-A1 |
| D23 (L36) | "số lần chạy skill thì hiển thị trong trang detail" | V5-R22, V5-R31, V5-R33 | V5-A1 |
| D24 (L37) | "cần một icon warning để khi hover vào sẽ có tooltip hiển thị hoặc popover" | V5-R14, V5-R27, V5-R64, V5-R66 | V5-A1, V5-A5, V5-A17 |
| D25 (L38) | "ok hết" (only detected CLIs; writes to Claude Code and Codex only) | V5-R24 | V5-A5 |
| D26 (L39) | "phần danh mục này chưa phân biệt được rõ…" (tabs kept; verdict groups superseded by D33) | V5-R20, V5-R21 | V5-A1 |
| D27 (L40) | "ok hết" (Group by and Order by) | V5-R30 | V5-A5 |
| D28 (L41) | "ok hết" (multi-select with the strip in the bottom bar) | V5-R26, V5-R32, V5-R38 | V5-A6, V5-A7 |
| D29 (L42) | "mỗi tab item phải có background chip ấy" + "các tab này chỉ khi active mới có màu đó" | V5-R11, V5-R19, V5-R20, V5-R51, V5-R61 | V5-A1, V5-A2 |
| D30 (L43) | "các line border ở các item này đang rất kém" | V5-R23, V5-R30 | V5-A1 |
| D31 (L44) | "toggle vào agent là add/remove" | V5-R25, V5-R26, V5-R35, V5-R43 | V5-A1, V5-A6, V5-A8 |
| D32 (L45) | "chọn Mingcute Line icon đi" | V5-R10, V5-R12, V5-R15 | V5-A4, V5-A9 |
| D33 (L46) | "cứ hiển thị theo list dọc thôi" | V5-R21, V5-R30 | V5-A1, V5-A5 |
| D34 (L47) | "filter thì sẽ có rank" | V5-R29, V5-R31 | V5-A5 |
| D35 (L48) | "tôi muốn có nhiều kiểu filter hay group hơn" | V5-R29 | V5-A5 |
| D36 (L49) | "ok approve" (Group by kinds) | V5-R30 | V5-A5 |
| D37 (L50) | "ok approve" (Filter button, two-level menu, chips) | V5-R28, V5-R39, V5-R61 | V5-A1, V5-A7 |
| D38 (L51) | "q1-q5 approve" (jobs in priority order) | V5-R44 | V5-A17 |
| D39 (L52) | "q1-q5 approve" (vocabulary; amended by D46) | V5-R45 | V5-A15 |
| D40 (L53) | "q1-q5 approve" (one colour, one meaning) | V5-R11, V5-R46 | V5-A16, V5-A14 |
| D41 (L54) | "q1-q5 approve" (detection and action together) | V5-R27, V5-R38, V5-R47, V5-R57, V5-R59 | V5-A17 |
| D42 (L55) | "q1-q5 approve" (principles in two places) | V5-R48 | V5-A15, V5-A16, V5-A17 |
| D43 (L56) | "Loadout nên đổi thành Agents trong này sẽ bao gồm cả Rule luôn cho gọn" | V5-R49 | V5-A1, V5-A15 |
| D44 (L57) | "mỗi category có một layout khác nhau" (refined by D45, D54) | V5-R76 | V5-A1, V5-A23 |
| D45 (L58) | "ok hết" (own canvas per page; partly superseded by D54) | V5-R18, V5-R52, V5-R76 | V5-A1 |
| D46 (L59) | "ok hết" (Agents is the page; Subagents the item; Rule a permission entry; Instructions) | V5-R10, V5-R20, V5-R45, V5-R49 | V5-A15 |
| D47 (L60) | "ok hết" (Rules is the permission grid; Instructions later) | V5-R49, V5-R67, V5-R68 | V5-A1 |
| D48 (L61) | "ok hết" (Codex read only in Rules) | V5-R67, V5-R68 | V5-A1, V5-A6 |
| D49 (L62) | "ok hết" (`All` dropped; Subagents may show counts) | V5-R10, V5-R20, V5-R30, V5-R49, V5-R64 | V5-A1 |
| D50 (L63) | "ok hết" (Limits snapshot only; Failed and Files are Activity tabs) | V5-R49, V5-R69 to V5-R74 | V5-A1, V5-A19 |
| D51 (L64) | "ok hết" (form follows the question; answer first) | V5-R44, V5-R53, V5-R63, V5-R65, V5-R67, V5-R73 | V5-A18 |
| D52 (L65) | "ok hết" (the element sheet briefs every page) | V5-R44, V5-R53 | V5-A18, V5-A24 |
| D53 (L66) | "ok hết" (tokens change app-wide at once; the last lit logo is not toggleable) | V5-R7, V5-R25, V5-R66 | V5-A6, V5-A11 |
| D54 (L67) | "học của Loadout về các UI nhỏ, các block, còn layout phải khác" | V5-R8, V5-R52, V5-R56, V5-R57, V5-R61, V5-R62, V5-R76 | V5-A3, V5-A23 |
| D55 (L68) | "phải rút ra những cái rules về frontend để thành bộ luật cho agent" | V5-R8, V5-R48, V5-R76 | V5-A3, V5-A23 |
| D56 (L69) | "tôi thích kiểu chia thành nhiều card nhỏ theo bento ấy" | V5-R18, V5-R52, V5-R54, V5-R76 | V5-A1, V5-A10 |
| D57 (L70) | "không dùng ring cho input hay button nào cả" | V5-R41 | V5-A7, V5-A2 |
| D58 (L71) | "bộ icon ở đây giữ 1 màu trung tính đi" | V5-R14, V5-R33 | V5-A4, V5-A1 |
| D59 (L72) | "các agent limit nên nằm trong 1 card dọc luôn" + "ok trang Limit ổn" | V5-R53, V5-R55, V5-R56, V5-R73, V5-R74 | V5-A1, V5-A14 |
| D60 (L73) | "số trong này có tác dụng gì" + "ok update đi" | V5-R60, V5-R73, V5-R75 | V5-A24 |
| D61 (L74) | "hãy chia layout như Limits, chia thành 2 nửa…" + "mỗi card cần cho title lớn hơn" | V5-R4, V5-R52, V5-R54, V5-R58, V5-R70 | V5-A1, V5-A22 |
| D62 (L75) | "Thử Hooks trước (Recommended)" + "yes approve" (superseded by D67, dropped before any build) | none: the simple layout is not built | V5-A1 (split layout on every page) |
| D66 (L76) | "nên làm kiểu thoáng tay lên" + "ok vậy giờ áp cho toàn app, sidebar cũng phải thoáng" | V5-R19, V5-R20, V5-R23, V5-R50, V5-R51, V5-R52, V5-R55, rhythm table | V5-A1, V5-A11, V5-A22 |
| D67 (L77) | "bỏ luôn 4,5,6 sau khi làm thoáng lên thì các option cũ nhìn đẹp hơn" | V5-R52, V5-R63, V5-R65, V5-R67 | V5-A1 |
| D65 (L78) | "approve 1-4" (Session, Activity, Tokens and Cost, Undo and Journal terms) | V5-R38, V5-R45, V5-R59, V5-R66 | V5-A15 |
| D68 (L79) | "ok chốt giao diện" | V5-R1, V5-R3, V5-R6, V5-R11, V5-R12, V5-R53, V5-R57, V5-R58, V5-R62; reference mock section | V5-A1, V5-A14, V5-A22 |
| D64 (L80) | "ok hết" (Runs for hooks, Sessions for skills and subagents; `agent` wire value stays) | V5-R21, V5-R30, V5-R33, V5-R45, V5-R64 | V5-A15 |
| D63 (L81) | "skill chỉ có dựa vào đã chạy lần nào hoặc chưa chạy" + "ok approve" | V5-R14, V5-R27, V5-R29, V5-R75 | V5-A5, V5-A15 |

## Out of scope

Each line was checked against the ledger. Lines that narrow a decision say so and wait for the owner's yes (open question 7).

- Settings redesign (D1, D2). It takes the shared token values (V5-R7) and is verified not to break (V5-A11).
- The landing page `site/` and the app icon (D14).
- User-chosen icon colours (D8).
- Filters by Scope and Added (D35).
- Gemini CLI as a write target (D25).
- Each CLI's settings panel, Instructions and Codex permission editing (D47, D48: a later phase; the Agents spec's panels wait for it).
- Limits history (D50).
- The mock-only controls listed under "Reference mock".
- Engine work for data the app lacks (V5-R75): it belongs to the engine owner (go-core plan, D-5). NARROWS D61 ("Activity gains charts and more figures") and D63 (L81)'s "added" note until that data exists: needs the owner's yes.
- Any change to ReinsCore behaviour, the Node oracle or the Go core from this track.

## Conflicts found

Recorded for the owner; the documents follow the resolution named in each row.

| # | Conflict | Evidence | Resolution in these documents |
| --- | --- | --- | --- |
| C1 | RESOLVED 2026-11-07: the ledger repeated D63 to D65 (two sessions wrote the same IDs); the UI rows (spacing, layout kept, mock frozen) were renumbered D66 to D68 | ledger lines 76, 77 and 79 | the glossary rows keep D63 (L81), D64 (L80) and D65 (L78); no citation is ambiguous now |
| C2 | The go-core plan's open decision D-5 ("does new UI work pause") and its S.1 pixel-identical shot gate collide with a UI rebuild; its R1 renames every `REINS_*` variable to `SPACEVIBE_*` (in progress, uncommitted, in the shared checkout on 2026-11-07), R3 renames `Sources/Reins` | `docs/plans/2026-11-07-go-core-and-spacevibe-identity.md` lines 237, 471, 177, 313, 515-526 | the build plan's first gate is D-5; the dev switch is defined once so R1 renames it |
| C3 | D53 (token values change app-wide at once) vs W17 (the old version stays the default) | ledger line 66; `~/.claude/rules/core/workflow.md` W17 | colour token values change app-wide once (D53); D66 sizes and the new blocks are new tokens used only behind the switch |
| C4 | Answer sentence size: the mock renders `.num` at 28 px; PRODUCT.md says the answer sentence is 20 px; BRIEF-wireframe calls `.num` "20px" | `system/shared.css:291`; `PRODUCT.md:32`; `BRIEF-wireframe.md` rule 2 | build 28 (D68) pending open question 1 |
| C5 | Small cards 8 apart on Hooks and Subagents vs D66's 24 and "nothing hard-coded in a page" | `b-hooks/index.html:11`, `b-subagents/index.html:12` | 24 (S6) |
| C6 | D66's "collapsed bands become a one-line chip strip (36 high)" is not in the mock: Hooks shows a two-column grid of 44-high band headers, other pages stack collapsed bands 10 apart | ledger line 76; `b-hooks/index.html:22`; `system/shared.css:591,598` | build as the mock (D68, later than D66) |
| C7 | `c3` still shows `Agents` and `All` tabs | `c3/index.html:83` | D46, D49 (S1) |
| C8 | Mock words and states the ledger removed: "runs" for skills and subagents, pending states, "Dead" for never ran, Codex hook run counts | `c3/index.html:90,279`; `b-subagents/index.html:84`; `system/data.js:48-67` | ledger and glossary (S2 to S5) |
| C9 | One key, two meanings: `r` refreshes Limits but removes elsewhere; `f` vs `/` for Filter; `Backspace` vs `r` for remove | `b-limits/index.html:190`; `b-hooks/index.html:329,331`; `c3/index.html:443,446` | V5-R36 recommended map, open question 2 |
| C10 | Toast duration: kit 5 s vs app and 2026-11-06 text 7 s | `system/shared.js:238`; `Sources/Reins/Tokens/Metrics.swift:160` | 5 s (D68) |
| C11 | Focus: the 2026-11-06 text asked for a 2 pt accent ring; D57 bans rings | ledger line 70 | fill (V5-R41) |
| C12 | Verdict colours in the 2026-11-06 token table vs D58 neutral glyphs | ledger line 71; `system/shared.css:523` | neutral (V5-R14) |
| C13 | Sidebar glyphs: the mock draws Phosphor Duotone (stack, pulse, gauge, sliders) where the 2026-11-06 text kept Solar; the owner's 2026-11-05 note "the sidebar set is not reused inside pages" vs the mock reusing `sliders` and `stack` in content | `system/shared.js:94,134,152,194`; agent memory "reins-ui-taste" 2026-11-05 | build as the mock (V5-R12), open question 6 |
| C14 | Accent shade and category set were "to be picked by eye"; the frozen mock shows the defaults (accent 1, set 1) | `index.html` (`accent` default "1"); `system/shared.css:69-72` | build values, confirmed at V5-A14 |
| C15 | Rules in the mock has no scope control (project, local) and no add-rule row, both in the current app | `Sources/Reins/Rules/RulesScopes.swift`, `Sources/Reins/Rules/RulesAddRow.swift`; `b-rules/index.html:142-197` | open question 4 (removes existing flows, W1) |
| C16 | The mock sidebar has no Limits block; the current app shows one on every page | `Sources/Reins/Limits/LimitsSidebarBlock.swift`; `system/shared.js:139-155` | it goes (V5-R50), confirmed at V5-A14 |
| C17 | The Agents spec's page (one card per CLI at `⌘2`, AG1, compared with mock C′ in AG10) is superseded in placement and look by D43 to D49 and D68 | `docs/specs/2026-11-05-reins-agents.md` "Interface", AG1 and AG10 | the build plan supersedes those UI tasks; its engine tasks, its push panel and AG8 wait for the per-CLI settings panel (D47, D48) |
| C18 | Rules families in the mock (Bash, Edit/Write, Read, Web, MCP) differ from the engine's capabilities (read, edit, run, network, push, secrets); the mock maps MCP to "Project trust" in Codex | `b-rules/index.html:52`; `system/data.js:85-88`; `Sources/ReinsCore/RulesTypes.swift:12-24` | Hypothesis, unverified (V5-R75): the Rules task maps families from `RuleItem.tool` and checks each Codex fact against `RulesCodexPermissions` |

## Data the app may not have (W23, UP6)

Each item is "Hypothesis, unverified" until its check runs; the check is the next step.

| # | Shown in the mock | What the code has | Deciding check |
| --- | --- | --- | --- |
| G1 | Subagent model and tools; "can run Bash"; group by Model; filter Can touch | `InventoryItem` has name, description, owner, file, scope, cells; no model or tools (`Sources/ReinsCore/InventoryTypes.swift:118-141`); `Frontmatter.swift` parses neither | read a fixture agent file's frontmatter and Codex `.toml`; if the engine must parse them, that is engine work (D-5) |
| G2 | Hook handler kind (command, http, prompt, mcp_tool, agent); filter Handler; "Can't run <kind> handlers" | `InventoryHook` has event, matcher, command, timeout, async (`InventoryTypes.swift:213-236`) | read the CLIs' hook docs (UP6) and the fixture `settings.json`; engine work if needed |
| G3 | Which events and handler kinds Codex supports (the copy rule) | `system/data.js:69-72` marks it unverified | Codex hooks documentation |
| G4 | Activity Today: tool calls today, estimated cost today, longest running session, estimated cost per day for 14 days | `ActivityStats` holds `logs` and `truncated` only (`Sources/ReinsCore/Activity.swift:69-74`); sessions carry their own cost | engine work, or the card is left out (out-of-scope line, open question 7) |
| G5 | Time ranges of the failed list and the most-edited list | `ActivityFailure` has first and last; `ActivityFileRow` has last; the window the engine scans is unverified (`b-activity:54` calls its ranges assumptions) | read `Activity.swift` options for the scan window |
| G6 | The waiting session's question ("Allow Bash?") and command | `ActivitySession.stateReason`; content unverified | the Activity fixture's waiting session |
| G7 | "Added <when>" for a newly added item (file added, not merely edited) | `Inventory.attachUsage` gets an `addedAt` per file (`Sources/ReinsCore/InventoryUsageAttach.swift:16-38`); birth time vs modification time unverified | read where `addedAt` comes from |
| G8 | Limits read age and plan | `CLILimits` has `state`, `plan` and `source` (`Sources/ReinsCore/Limits.swift:36-54`); `LimitWindow` has the share used, reset time and `active`; read time unverified | the Limits fixture variants (`SPACEVIBE_FIXTURE_LIMITS=typical\|edge`) |
| G9 | Sidebar CLI status rows (reading, not installed, no log) | derivation unverified | the roots the shell already resolves |
| G10 | What "Add to Codex" writes for a subagent ("a stub, pick its model") and "Add to Claude Code" ("Read tool only") | Settled 2026-11-10 (owner call C3): the copy writes name, description and instructions only, and the UI says so before `Add` (V5-R64). The mock's two lines are dropped. Still unverified: that a Claude Code subagent with no `tools` line can use every tool | `SubagentsModelTests` `copyNoteBeforeAdd`; the golden `mutate.json` is unchanged |
| G11 | `Open` on a session or a failed command ("in <CLI>") | S-R4 allows only `ps`, `lsof` and `kill`; opening a terminal session is unverified and may be outside S-R4 | open question 5 |
| G12 | Rules' Codex facts per family (C18) | `RulesCodexPermissions` | as C18 |
| G13 | `Dismiss` on a failed command and `Dismiss passed`, with Undo | no dismissal store in the engine; whether a dismissal survives a relaunch is undecided | build it in memory for the session unless the engine gains a store (engine work, D-5) |

## Open questions

Each carries a recommendation the build follows unless the owner says otherwise; the owner's answers are recorded at the final eye task (V5-A14), except where a row says it blocks.

1. **Answer sentence size.** Recommended: 28/32 as the mock renders it, and PRODUCT.md's "20px" line is amended in a separate change with the owner's yes. Alternative: 20/28 everywhere.
2. **Key map.** Recommended: V5-R36 (`r` remove everywhere, `⌘R` refresh on Limits, `/` filter everywhere, `Delete` also removes). Alternative: keep each mock page's keys as drawn.
3. **Accent shade 1 and category set 1** as the build values (C14). Recommended: yes.
4. **Rules project and local scopes, and adding a rule** (C15). The mock removes both; this removes existing flows (W1). Recommended: keep the engine untouched, build Global as the mock shows, and ask before the Rules cut-over; blocks that cut-over only.
5. **`Open` on a session or a failed command** (G11) and the **time ranges** (G5). Recommended: `Open` opens the project folder or the log file in the default app, never starts a CLI (S-R4); a range label shows only when the engine reports the window.
6. **Sidebar and content glyph family** (C13). Recommended: as the mock draws them (Phosphor Duotone for sidebar and content, MingCute Line for the category glyphs, Reins's own verdict glyphs), with credits verified.
7. **Elements without data** (out-of-scope line, G1 to G4). Recommended: build every element whose data exists; leave the rest out with a named departure; the engine work goes to the go-core plan per its D-5. Needs the owner's yes because it narrows D61 and D63 (L81) for now.
8. **Cards that scroll inside at 1440 x 900** (Hooks stack, Subagents spine, Rules): accepted by D66 and D68; the eye task confirms.
9. **Light mode** has not been looked at since D66; the eye task is its first check.
