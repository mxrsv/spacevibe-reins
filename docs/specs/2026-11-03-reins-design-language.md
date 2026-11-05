# Reins: design language and component base

Status: decided 2026-11-03; v3 changes decided 2026-11-04, v4 changes decided 2026-11-05 (sections "v3 changes" and "v4 changes"; where a later version and an earlier line disagree, the earlier line below is already rewritten). Parent spec: [2026-11-02-reins.md](2026-11-02-reins.md) (product, interface, acceptance criteria AC1 to AC9). Plans: [2026-11-03-reins-design-language.md](../plans/2026-11-03-reins-design-language.md) (v2, shipped) and [2026-11-04-reins-design-language-v3.md](../plans/2026-11-04-reins-design-language-v3.md).

Mock: `~/scratch/spacevibe-reins/design-language/index.html` on the owner's Mac (synthetic data, outside git; F4). Its screens section toggles `v2` (the target), `v1` and the current app's screenshots; its last table, "Bảng đổi token", is the old-to-new map this spec summarises. Since 2026-11-04 the mock also has `v3` (the default): an overview of Loadout, Rules, Activity and Limits side by side, a v3 component sheet and a v3 section of that table. The v4 mock is [`mocks/agents/controls.html`](../../mocks/agents/controls.html)`?icons=tabler&buttons=a`, tracked: the Agents page with the page icon set and button family applied, and a sheet of every button kind in every state in both appearances.

## Why

The owner judged the app "assembled from parts": seven text sizes (11, 11.5, 12, 13, 15, 20, 22), sixteen spacing values, ten control heights and seven radii, group titles smaller than row names, white cards on a near-white page and one 16 pt gap between everything. Pieces did not read as one system, and a restyle had to touch every screen file.

## Decisions

Accepted by the owner on 2026-11-03 ("ok chốt"): all of mock v2 including the fixed 120 pt state column in Activity, the seven structural changes listed under "Components", option B for the Tokens tab's leading number (one named `figure` role), and Inter for every text role with no monospaced face.

### Typography

- **One family: Inter 4 variable** (SIL OFL 1.1), bundled with the app, for UI text, numbers and machine strings alike. No system font, no monospaced font.
- **Sizes 12, 14 and 16 only**, each with a line box on the 4 pt grid: 12/16, 14/20, 16/24. The exceptions are `figure` 24/32, used for at most one leading number per Tokens card, and `display` 72/88 (v3), used only for the share left on the Limits page.
- **Weights 400, 500 and 600.** Hierarchy inside a size comes from weight and colour, not size. A selected segment may turn 600 only if its width is reserved by a hidden 600 copy, so the control never changes width.
- **Tracking by size:** 12 = 0, 14 = −0.006 em, 16 = −0.011 em, 24 = −0.01 em.
- **Digits are tabular where numbers line up** (runs, cost, counts: the `number` and `count` roles), not in prose: Inter's `tnum` also gives the hyphen a digit's width (found in T1, 2026-11-03). Machine strings (commands, paths, config keys, rule patterns) stay Inter and switch on the `ss02` and `zero` features (slashed zero, distinct l · I · 1); prose never does.

| Role | Size / box | Weight | Default colour | Used for |
| --- | --- | --- | --- | --- |
| `caption` | 12 / 16 | 400 | `textTertiary` | second lines, column labels, hints, notes, counts |
| `captionStrong` | 12 / 16 | 600 | `textSecondary` | section rows, note headings |
| `label` | 12 / 16 | 500 | by tone | tags, key caps |
| `body` | 14 / 20 | 400 | `text` | buttons, chips, segments, fields, sidebar, numbers in cells |
| `bodyStrong` | 14 / 20 | 600 | `text` | banner titles, primary button, empty-state titles |
| `rowTitle` | 14 / 20 | 500 | `text` | row names |
| `title` | 16 / 24 | 600 | `text` | page title, card titles (palette input uses 400) |
| `code` | 12 / 16 | 400 | `textTertiary` | commands, paths, keys on a second line |
| `codeTitle` | 14 / 20 | 500 | `text` | row names that are machine strings |
| `number` | 14 / 20 | 400 (600 for a zero) | `text` | runs and cost in a column, tabular digits |
| `count` | 12 / 16 | 400 (600 for an alert) | `textTertiary` | counts beside a label, tabular digits |
| `figure` | 24 / 32 | 600 | `text` | one leading number per Tokens card |
| `display` | 72 / 88 | 600 | `text` | the leading number on the Limits page, one at a time; tracking −0.03 em, tabular |

### Spacing, sizes, radii, colour

- **Spacing scale:** 2, 4, 6, 8, 12, 16, 24, 32. 2 and 6 are used only inside one component.
- **Rhythm:** card to card 24, region to region 32, two cards in one Activity lane 16. Top bar 48 high, toolbar 8 below it, first card 24 below the toolbar (or below the top bar when a screen has no toolbar). Page side padding 24, bottom 32.
- **Heights:** 24 (tag, segment inside its frame), 20 (key cap), 28 (every control: button, chip, segmented frame, scope picker, search field), 32 (section row, hint bar), 36 (palette row), 48 (every row, top bar, sidebar item), 56 (card header). A row with three or more lines grows from 48 with 12 pt vertical padding.
- **Radii:** 4 (tag, key cap), 6 (segment), 8 (control, field, sidebar item), 12 (card, banner, toast, palette); filter chips are capsules. An inner radius equals the outer radius minus the padding between them.
- **Colour values in `Palette.swift`:** every surface, border, hover, divider and text grey is neutral (R = G = B); the navy tint of the first palette read as a blue cast on every screen (owner, 2026-11-04). Dark: `background` and `well` `#161616`, `surface` `#2A2A2A` (a card sits about 20 levels above the well), `surfaceRaised` `#343434`, `border` `#3A3A3A` at 70%, `hover` white at 7%, `text` `#F2F2F2`, `textSecondary` `#B3B3B3`, `textTertiary` `#A3A3A3`. Light: `background` `#F8F8F8`, `well` and `surfaceRaised` `#F2F2F2`, `surface` white, `border` `#DADADA`, `hover` black at 5%, `text` `#141414`, `textSecondary` `#474747`, `textTertiary` `#5E5E5E`. The 2026-11-05 shared-colour-tone refinement below updates the accent, selection tint and CLI/state colours together. `well` is the content area behind cards and the sidebar's ground, so cards read as blocks against it.
- Fixed widths that hold numbers: usage number 52 (fits "12,345"), cost 72 (fits "~$148.20" in Inter; 64 was measured with SF), Activity state column 120, Loadout actions 60 (two 28 pt slots and 4 pt between).

### Components

The seven structural changes:

1. Loadout shows Skills, Agents and Hooks as three cards, each with its own header carrying the CLI column labels.
2. A group title is always the first line inside its card (`CardHeader`: 48 high, `surface`, `title` plus a `caption` count). `GroupLabel` outside a card is removed.
3. The "running" tag uses the `success` tone with a dot; CLI colours mark identity only (dots, bars, CLI tags).
4. Key caps use `label` (Inter 12/500), not a monospaced face.
5. "N errors" is a `warn` tag everywhere, the gallery included.
6. The segmented control reserves the 600 width (see Typography).
7. Every row is 48 high: 6 pt vertical padding around a 20 + 16 two-line block, or a 28 pt control.

The v2 changes:

- Between two rows of a card sits a faint divider (v3: text colour at 8% opacity, inset 40 from the row's leading edge, 8 from the trailing edge); it is hidden at a hovered or selected row and the row after it. A section row has no divider under it and 16 pt of space before the next section.
- "Add to <CLI>" is a ghost button (no outline, a plus icon, `textSecondary`, hover fill); it stays visible.
- Loadout's remove buttons are 28 pt icon buttons with the CLI's dot as a corner badge.
- Loadout's "Counted from …" note moves to the end of the usage legend.
- A Rules decision tag (Deny, Ask, Allow) sits 8 pt after its pattern.
- Activity: the state tag sits right-aligned in a 120 pt column; Stop is a 28 pt icon button; failure rows use 12 pt vertical padding with the machine error line in `code` and `textSecondary`; the "Cannot be measured" notes form one region after both lanes, two columns 24 apart, with the shared cost note once below them.
- Hint bar: 32 high on `well`, no line.

### v3 changes (decided 2026-11-04)

Accepted by the owner on 2026-11-04 ("ok chốt") after eye review of mock v3 on Loadout, Rules, Activity and Limits. They come from the Limits mock rounds and apply to the whole app, not to Limits alone. The Tokens tab has no mock; it takes these tokens when it ships.

- **Ground.** Sidebar and content area share `well`. One 1px vertical line (text colour at 8% opacity) separates them. The top bar and hint bar have no line. `Palette.sidebar` is no longer used by the shell.
- **Cards.** A `surface` block on the well: no border, radius 12, 8 pt padding below the last row, header 56 high (title `title` 16/600 plus the count). Cards do not nest; the Limits tiles are the one documented exception (one level, they are blocks of their own).
- **Rows.** No border. Hover and selection fill an 8-radius block inset 8 from the card's edges; the divider rule is under Components.
- **Sidebar.** Item 48 high in the `title` role (16/600) in every state; icon 22 in `textSecondary`; 8 pt between items; padding 16 at the sides. The active item changes only its fill (`surface`), never text, weight or icon. The count is `body` in `textTertiary`; an alert count stays `danger` and 600. The Limits block sits above the footer (parent spec, Interface).
- **Icons.** Solar Bold Duotone (480 Design, CC BY 4.0) replaces SF Symbols, so the licence text must be reachable from the app. Since v4 it draws navigation only: the sidebar's items and footer. Page content uses Tabler (v4 changes). Icons are neutral: both layers take one colour (the lighter layer keeps the glyph's 50% opacity). Sizes: 22 in the sidebar, 20 as a row lead, 16 in buttons and tags, never below 14 (the Bold weight loses detail at 12). A state tag or banner tints its icon with the tone's ink; nowhere else is an icon coloured. Each icon is drawn as two SwiftUI shapes from generated code: no SVG at run time and no CoreSVG, which rejects packed arc flags and gradients.
- **Progress.** The ten-cell ruler is for Limits only (owner, 2026-11-04). Its cells are square slices, not capsules; only the ruler's two outer ends round, by a quarter of its height (owner, 2026-11-04, after the mock-H rework): 8 high in the list and 32 under the Limits figure, 3 pt gaps, the last filled cell clipped to the share; empty cells `surfaceRaised`; an unknown share is a dashed outline. Cell width is the track width divided by ten. Tint `warn` at 20% left or less and `danger` at 5% or less. The usage bar of Loadout and Activity (and every other category) keeps the continuous 6 pt capsule on `track`, with the dashed capsule for "not counted yet"; the sidebar's Limits tiles show a number and no bar.
- **Status badges.** `Tag` is 24 high, radius 6, `surfaceRaised` fill, neutral text and a 6 pt dot in the tone colour; `warn` and `danger` keep their ink for the text. A tag with an icon or without a tone has no dot. CLI tones keep marking identity only.
- **Controls.** The search field, text fields and key caps have no outline: `surface` fill on the well, `surfaceRaised` inside a card. Buttons, the scope picker, the segmented control, filter chips and card buttons follow "Buttons" under v4 changes.
- **Unchanged.** Radii 4, 6, 8, 12 and the spacing scale 2 to 32; sizes 12, 14, 16; weights; Inter only.

### v4 changes (decided 2026-11-05)

Picked by the owner on 2026-11-05 from `controls.html`: Tabler for page icons and button direction A, "Khối có chiều sâu" (a raised block). The owner had said on 2026-11-05 that the sidebar's icon set must not be reused inside pages and that Reins had no button set of its own. Like v3, these apply to the whole app through `Tokens/` and `Components/`, not to the Agents page alone.

- **Two icon sets, split by job.**
  - The sidebar (its items and its footer) keeps Solar Bold Duotone.
  - Everything inside a page uses Tabler Icons (MIT): the top bar, cards, rows, buttons, tags, menus, panels, dialogs and toasts.
  - A page never draws a Solar glyph and the sidebar never draws a Tabler glyph.
  - Tabler is an outline set on a 24 grid with a 2 stroke and round caps and joins. Sizes stay 16 in buttons and tags, 20 as a row lead and never below 14.
  - It is generated into Swift path code like Solar, rendered as a stroked shape, with no SVG at run time.
  - The MIT notice sits beside the Solar credit in the About panel.
- **Buttons: a raised block.**
  - **Fill:** the button is a block with a 0.5 pt hairline, a 1 pt-offset shadow with a 2 pt blur, and a 1 pt highlight along its top edge.

    | Token | Light | Dark |
    | --- | --- | --- |
    | `controlFill` | `#FFFFFF` | `#3D3D3D` |
    | `controlFillHover` | `#FAFAFA` | `#454545` |
    | `controlFillPressed` | `#EBEBEB` | `#323232` |
    | `controlHairline` | black 16% | black 70% |
    | `controlShadow` | black 12% | black 45% |
    | `controlHighlight` | white 90% | white 9% |
  - **Pressed:** the block moves down 0.5 pt and its shadow turns inner.
  - **Primary:** `accentSolid` with the same top highlight, a black 25% hairline and an accent-tinted shadow. The planned v4 hover (`#466A9D`) and pressed (`#2D4773`) fills follow the muted blue palette refinement below.
  - **Ghost and icon buttons:** no fill until hover; pressed fills `track`.
  - **Disabled:** keeps the hairline and shadow, drops the highlight; text in the tertiary tone.
  - **Loading:** a spinner replaces the leading icon, and the label and the width stay.
  - **Focus:** the ring is unchanged (2 pt `accent`).
- **Chosen state is the accent.** A card button whose panel is open, a selected filter chip and the chosen segment fill with `accentSolid`, with white text and icons.
- **Segmented control.**
  - The track is sunken: an inner shadow, and in dark a `#1F1F1F` fill below `surface`.
  - **Verdict pickers** (Allow / Ask / Deny, Allow / Prompt / Forbidden) fill the chosen segment with its tone instead of the accent: `success`, `warn` or `danger`, solid.
  - The text on those fills (`onSuccess`, `onDanger`) is white on the light success and danger fills and `#141414` on warn and on every dark fill.
  - A risky option (Never, Full access) takes the solid `warn` fill when chosen.
- **Card button (new component).**
  - It is the agent card's way into a panel: a 16 icon, the name in `rowTitle` and its value in `count`, or in `code` for a file or model name.
  - It is 32 high, the one exception to the 28 control height, because it is the page's main entry point.
  - Advanced is the same button as a ghost.
- **New tokens:**
  - `controlFill`, `controlFillHover`, `controlFillPressed`, `controlHairline`, `controlShadow` and `controlHighlight`;
  - `accentHover` and `accentPressed`;
  - `segmentTrack` (sunken);
  - `onSuccess` and `onDanger`;
  - `cardButtonHeight` 32.
- **Unchanged.** Fields, tags, cards, rows, the sidebar item, radii, spacing and type. Shared colours follow the palette refinement below.

### Shared colour tone (decided 2026-11-05)

The owner approved several distinct colours with one cohesive, restrained tone, using Paradev as the reference.
This is neither a monochrome palette nor a requirement to copy Paradev's exact Claude/Codex hex pair.
The owner's subsequent choice on 2026-11-05 pins the Codex fill to Paradev's `#1596D6` in both appearances,
with the matching 15% tint and separate readable Ink; the other hues remain as coordinated above.

- Keep the neutral surfaces and existing layout. Coordinate identity, semantic and interaction colours together:
  clay, blue, green, ochre and brick red with comparable perceptual lightness/chroma, without neon or isolated pastel fills.
- Reuse `Palette` and the existing CLI mappings. Derive each 15% tint from its fill; give coloured text a separate,
  same-hue `Ink` variant for each appearance. The lighter dark-mode Ink is for readable text/marks, not the bar fill.
- Keep warning/danger semantics and the remaining-quota thresholds (20% / 5%), unknown dashes and true empty zero.
- Keep selected-tile tracks quiet enough to distinguish the coloured fill. Verify Ink on ordinary, selected and nested
  tinted surfaces at >=4.5:1. The explicitly chosen Codex fill has lower than 3:1 contrast on light tracks; its decorative
  bars must retain adjacent numeric labels. Meaningful controls and focus indicators still require >=3:1.
- Future Tokens charts take the same identity tokens. Low-opacity area shading is supplementary to a full-colour line;
  this palette adjustment does not add the unimplemented native Tokens screen or recolour its separate historical mock.
- Review the native light/dark fixtures, including selected and warning/danger states, as one batch before visual acceptance.

### Component base

- **Screens compose base components only.** Files under `Sources/Reins/{Loadout,Rules,Activity}` (and `TokenUsage` when it exists) contain no font, colour, corner radius or numeric spacing and size literals. Those live in `Sources/Reins/Tokens/` and `Sources/Reins/Components/`. `Shell/` follows the same rule; `Gallery/` is exempt.
- **The component gallery is the component list:** every base component in every state it has, in both appearances, captured by the shot harness.
- `docs/DESIGN-LANGUAGE.md` is the living description of the tokens and components once they ship (D1).

## Acceptance criteria

- **DL1.** Every text in the app renders in Inter: no `Font.system` and no system or monospaced design anywhere in `Sources/Reins`, and the bundled font registers in both the packaged `.app` and the bare binary used by `scripts/dev-fixture.sh --shots`.
- **DL2.** Text uses only the roles above; sizes outside 12, 14, 16 and the `figure` and `display` exceptions do not exist in `Metrics.swift` or anywhere else.
- **DL3.** A policy test fails when a screen folder gains a style literal, and its allowlist for screen folders and `Shell/` is empty.
- **DL4.** Changing one role or token in `Tokens/` restyles every screen that uses it, with no screen file edited (follows from DL3; shown once in the gallery).
- **DL5.** The gallery shows every base component; screenshots of Loadout, Rules, Activity and the shell in both appearances match mock v2 by the owner's eye.
- **DL6.** `scripts/test.sh` passes and `scripts/build-app.sh` prints `minos 15.0` with the font inside the signed bundle.
- **DL7.** No `Image(systemName:)` or `systemImage:` remains in `Sources/Reins` outside `Gallery/` (a policy test). Every icon comes from a generated set: Solar in the sidebar, Tabler everywhere else, enforced by a policy test on the sidebar and screen folders. The CC BY 4.0 and MIT notices are shown in the app.
- **DL8.** A test pins the Limits ruler: the filled cells and the clipped last cell for 0, 4, 39 and 100 percent at a given track width, and that an unknown share draws the dashed outline.
- **DL9.** Screenshots of Loadout, Rules, Activity, Limits and the shell in both appearances match mock v3 by the owner's eye, in one batch after the last task.
- **DL10.** The gallery shows every button kind (primary, secondary, ghost, danger, icon, card button, segmented, verdict picker, filter chip, scope picker) in every state it has (default, hover, pressed, focus, chosen, disabled, loading), in both appearances. It matches the v4 mock's sheet by the owner's eye.
- **DL11.** White on `accentSolid` and on the light success and danger fills, and `#141414` on warn and on the dark fills, each measure at least 4.5:1 in a test that reads the palette.
