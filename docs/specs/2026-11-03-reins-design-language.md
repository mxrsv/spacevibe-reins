# Reins: design language and component base

Status: decided 2026-11-03. Parent spec: [2026-11-02-reins.md](2026-11-02-reins.md) (product, interface, acceptance criteria AC1 to AC9). Plan: [2026-11-03-reins-design-language.md](../plans/2026-11-03-reins-design-language.md).

Mock: `~/scratch/spacevibe-reins/design-language/index.html` on the owner's Mac (synthetic data, outside git; F4). Its screens section toggles `v2` (the target), `v1` and the current app's screenshots; its last table, "Bảng đổi token", is the old-to-new map this spec summarises.

## Why

The owner judged the app "assembled from parts": seven text sizes (11, 11.5, 12, 13, 15, 20, 22), sixteen spacing values, ten control heights and seven radii, group titles smaller than row names, white cards on a near-white page and one 16 pt gap between everything. Pieces did not read as one system, and a restyle had to touch every screen file.

## Decisions

Accepted by the owner on 2026-11-03 ("ok chốt"): all of mock v2 including the fixed 120 pt state column in Activity, the seven structural changes listed under "Components", option B for the Tokens tab's leading number (one named `figure` role), and Inter for every text role with no monospaced face.

### Typography

- **One family: Inter 4 variable** (SIL OFL 1.1), bundled with the app, for UI text, numbers and machine strings alike. No system font, no monospaced font.
- **Sizes 12, 14 and 16 only**, each with a line box on the 4 pt grid: 12/16, 14/20, 16/24. The single exception is `figure` 24/32, used for at most one leading number per Tokens card.
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

### Spacing, sizes, radii, colour

- **Spacing scale:** 2, 4, 6, 8, 12, 16, 24, 32. 2 and 6 are used only inside one component.
- **Rhythm:** card to card 24, region to region 32, two cards in one Activity lane 16. Top bar 48 high, toolbar 8 below it, first card 24 below the toolbar (or below the top bar when a screen has no toolbar). Page side padding 24, bottom 32.
- **Heights:** 20 (tag, key cap), 24 (segment inside its frame), 28 (every control: button, chip, segmented frame, scope picker, search field), 32 (sidebar item, section row, hint bar), 36 (palette row), 48 (every row, card header, top bar). A row with three or more lines grows from 48 with 12 pt vertical padding.
- **Radii:** 4 (tag, key cap), 6 (segment), 8 (control, field, sidebar item), 12 (card, banner, toast, palette); filter chips are capsules. An inner radius equals the outer radius minus the padding between them.
- **Colour values in `Palette.swift` do not change.** One semantic token is added: `well`, the content area behind cards (light: the `surfaceRaised` value; dark: the `background` value). Cards stay `surface`, so they read as blocks against the well.
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

- Separators between rows use `track`, inset 48 from the leading edge (16 padding + 20 lead + 12 gap) and 16 from the trailing edge. A section row has no separator under it and 16 pt of space before the next section.
- "Add to <CLI>" is a ghost button (no outline, a plus icon, `textSecondary`, hover fill); it stays visible.
- Loadout's remove buttons are 28 pt icon buttons with the CLI's dot as a corner badge.
- Loadout's "Counted from …" note moves to the end of the usage legend.
- A Rules decision tag (Deny, Ask, Allow) sits 8 pt after its pattern.
- Activity: the state tag sits right-aligned in a 120 pt column; Stop is a 28 pt icon button; failure rows use 12 pt vertical padding with the machine error line in `code` and `textSecondary`; the "Cannot be measured" notes form one region after both lanes, two columns 24 apart, with the shared cost note once below them.
- Hint bar: 32 high on `well`, with a top hairline.

### Component base

- **Screens compose base components only.** Files under `Sources/Reins/{Loadout,Rules,Activity}` (and `TokenUsage` when it exists) contain no font, colour, corner radius or numeric spacing and size literals. Those live in `Sources/Reins/Tokens/` and `Sources/Reins/Components/`. `Shell/` follows the same rule; `Gallery/` is exempt.
- **The component gallery is the component list:** every base component in every state it has, in both appearances, captured by the shot harness.
- `docs/DESIGN-LANGUAGE.md` is the living description of the tokens and components once they ship (D1).

## Acceptance criteria

- **DL1.** Every text in the app renders in Inter: no `Font.system` and no system or monospaced design anywhere in `Sources/Reins`, and the bundled font registers in both the packaged `.app` and the bare binary used by `scripts/dev-fixture.sh --shots`.
- **DL2.** Text uses only the roles above; sizes outside 12, 14, 16 and the `figure` exception do not exist in `Metrics.swift` or anywhere else.
- **DL3.** A policy test fails when a screen folder gains a style literal, and its allowlist for screen folders and `Shell/` is empty.
- **DL4.** Changing one role or token in `Tokens/` restyles every screen that uses it, with no screen file edited (follows from DL3; shown once in the gallery).
- **DL5.** The gallery shows every base component; screenshots of Loadout, Rules, Activity and the shell in both appearances match mock v2 by the owner's eye.
- **DL6.** `scripts/test.sh` passes and `scripts/build-app.sh` prints `minos 15.0` with the font inside the signed bundle.
