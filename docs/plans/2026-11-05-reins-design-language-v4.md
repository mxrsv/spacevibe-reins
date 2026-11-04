# Reins: design language v4

Spec: [2026-11-03-reins-design-language.md](../specs/2026-11-03-reins-design-language.md), section "v4 changes" (acceptance criteria DL7, DL10, DL11, with DL4 and DL9 still holding).
Related: the [Agents plan](2026-11-05-reins-agents.md) uses the card button and the verdict picker built here.
Mock: `~/scratch/spacevibe-reins/agent-navigation/controls.html?icons=tabler&buttons=a`, outside git. It shows the Agents page with the v4 look, and a sheet of every button kind in every state in both appearances.
Checkout: `spacevibe-reins` on `main`, shared with other sessions. Commit with `git commit -- <paths>` only.
Started 2026-11-05. Status: the spec was committed (`2b2615f`); no Swift written yet.

## Approach

```
scripts/generate-icons.mjs            a second source: Tabler outline (stroked paths) into its own generated file
Sources/Reins/Components/             PageIcon + PageIconData (Tabler), ReinsIcon stays Solar for the sidebar
Sources/Reins/Tokens/Palette, Metrics control fills, hairline, shadow, highlight, accent hover and pressed, segment track,
                                      onSuccess and onDanger, cardButtonHeight
Sources/Reins/Components/             ReinsButtonStyle (raised, pressed, loading), SegmentedControl (sunken, accent chosen,
                                      tone variant), FilterChip, ScopePicker, CardButton (new)
Sources/Reins/Gallery/                the button sheet: every kind in every state
```

- **Order.** Tokens and generated icons come first, then components, then screens. Every commit leaves every screen consistent, the same order as v2 and v3.
- **No switch.** No one outside the owner runs the app, and the restyle lands through shared components, so `main` stays releasable without one (W17 exception).
- **Two glyph types.**
  - `ReinsGlyph` (Solar) is allowed only in `Shell/SidebarView` and the sidebar footer.
  - `PageGlyph` (Tabler) is used everywhere else.
  - `IconPolicyTests` enforces both by file.
- **Tabler drawing.** Tabler glyphs are stroked, not filled: the generator keeps the stroke paths, and `PageIcon` strokes them with round caps and joins at `2 × size / 24`.

## Tasks

- [x] V1. Spec, committed as `2b2615f`.
- [ ] V2. `generate-icons.mjs` reads `@iconify-json/tabler` (packed into a scratch folder, never committed) and writes `PageIconData.swift` for the page glyphs that the mock uses. Credits gain the MIT notice (DL7).
- [ ] V3. Add `PageIcon` and `PageGlyph`. Every icon outside the sidebar moves to it: Loadout, Rules, Activity, Limits, Settings, the top bar, the palette, toasts and dialogs. Extend `IconPolicyTests` (DL7).
- [ ] V4. Tokens from the spec's v4 table. Add a contrast test reading `Palette` for white on `accentSolid` and on the light success and danger fills, and `#141414` on warn and on the dark fills (DL11).
- [ ] V5. Components:
  - `ReinsButtonStyle` kinds: raised, pressed (down 0.5 pt, inner shadow), disabled, and loading (a spinner in place of the leading icon, the width fixed);
  - `SegmentedControl`: a sunken track, the chosen segment in accent, and a tone variant for verdict pickers;
  - `FilterChip` and `ScopePicker`, raised;
  - `CardButton`: 32 high, with an icon, a name and a value, in plain and ghost kinds.
- [ ] V6. Gallery: the button sheet with ten kinds by seven states in both appearances (DL10). Shots: `REINS_GALLERY=1` and `REINS_SHOT_SCREEN=shell` through `scripts/dev-fixture.sh --shots <dir>`.
- [ ] V7. Shots of Loadout, Rules, Activity, Limits and Settings in both appearances. The Rules add row uses the verdict picker. Update `docs/DESIGN-LANGUAGE.md`: icons by job, the button table, and the new components (D1).
- [ ] V8. Run `impeccable distill` and `clarify` on the changed surfaces, then get the owner's eye approval of the gallery sheet and the screen shots next to the mock (DL9, DL10).

## Verification

- `scripts/test.sh`, which must report more than 0 passed, including `IconPolicyTests`, `StyleBoundaryTests` and the contrast test.
- `scripts/build-app.sh`, which must print `minos 15.0`.
- The gallery and screen shots from `scripts/dev-fixture.sh --shots <dir>` in light and dark, beside `controls.html?icons=tabler&buttons=a`.

## Handoff

2026-11-05: the plan is written. Nothing else has started.

/goal Build design language v4 per docs/specs/2026-11-03-reins-design-language.md ("v4 changes") and docs/plans/2026-11-05-reins-design-language-v4.md: tasks V2 to V7 in order, one commit each. Done means scripts/test.sh passes with IconPolicyTests and the contrast test (DL7, DL11), and the gallery sheet and screen shots in light and dark match ~/scratch/spacevibe-reins/agent-navigation/controls.html?icons=tabler&buttons=a (DL10). Leave V8, the owner's eye approval, to the owner. Never push or release, and never touch the real ~/.claude or ~/.codex.
