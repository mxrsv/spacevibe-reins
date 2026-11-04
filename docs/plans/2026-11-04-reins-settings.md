# Reins: Settings

Spec: [2026-11-04-reins-settings.md](../specs/2026-11-04-reins-settings.md) (ST1 to ST7).
Mock: `~/scratch/spacevibe-reins/settings/index.html`, combination A2.
Checkout: `spacevibe-reins` on `main`, shared with other sessions; commit with `git commit -- <paths>` only.
Started 2026-11-04. Status: S1 to S9 done and committed (`9ba6917`, `3088300`, and the follow-up for Sparkle's no-update error); S10 waits for the owner's eye approval.

## Approach

```
Sources/Reins/Tokens/   TypeScale (the Font size step), ReinsType roles read it, AppearanceStore gains theme + font size
Sources/Reins/Components/  RailTab, ThemeTile, ReinsSwitch, ReinsMark, Chevron .left, HintBar without the fixed keys
Sources/Reins/Settings/  SettingsScreen, AppearanceSettings, UpdateSettings, SettingsWording, SettingsShots
Sources/Reins/Shell/     open/close Settings, ⌘, , gear button, palette entry
Sources/Reins/App/       UpdateController: observable status, background probe, automatic-check switch
```

- **Type scale.** `TypeScale.shared.step` is `@Observable`; every `ReinsType` role is a computed static that reads it and
  returns a cached role. A view body that uses a role then re-renders when the step changes, through `.reinsText` and the
  `Text`-returning form alike, and frames that read `ReinsType.x.lineBox` follow. Text-holding widths in `Metrics` read
  `TypeScale.width(_:at:)`.
- **Theme.** The live store sets `NSApp.appearance` (nil for System) instead of `.preferredColorScheme`, which on macOS
  does not return to the system appearance once it has been set.
- **Update.** `UpdateController` becomes `@Observable`, is Sparkle's updater delegate too, and lives on
  `AppEnvironment` so Settings and the shots reach it from the environment.

## Tasks

- [x] S1. Spec and plan.
- [x] S2. `TypeScale`, roles as computed statics, `FontSizeChoice`; tests (ST3).
- [x] S3. `ThemeSetting` and font size in `AppearanceStore`, `NSApp.appearance`, the toggle and palette entry; tests (ST2).
- [x] S4. Six Solar glyphs (settings, palette, monitor, text, globe, update) through `generate-icons.mjs`.
- [x] S5. Components: `RailTab`, `ThemeTile`, `ReinsSwitch`, `ReinsMark`, `Chevron(.left)`, `HintBar` without fixed keys;
      gallery specimens (ST6).
- [x] S6. `UpdateController` status, probe, switch; tests (ST4).
- [x] S7. Shell: open and close, `⌘,`, gear, palette, `Esc`; the Settings screen (ST1, ST5).
- [x] S8. `Metrics` text widths follow the size (ST3).
- [x] S9. Shots: `REINS_SHOT_SCREEN=settings` (both themes, every update state, Large), Large Loadout and Activity;
      `StyleBoundaryTests` gains `Settings`; DESIGN-LANGUAGE.md (ST6).
- [ ] S10. `impeccable distill` and `clarify`, then the owner's eye approval of the shots (ST7).

## Verification

`scripts/test.sh` (N > 0 passed), `scripts/build-app.sh` (`minos 15.0`), `REINS_SHOT_SCREEN=settings
scripts/dev-fixture.sh --shots <dir>`, `scripts/test-update.sh` when no Reins is running.

## Handoff

2026-11-04, session `spacevibe-reins-4b`, `main`, not pushed.

Verified:
- `scripts/test.sh`: `Test run with 403 tests in 43 suites passed`. The first run failed 58 golden and fixture checks
  because the shared `/private/tmp/reins-fixture-home` had 18 of its 222 files with a matching stamp; deleting it and
  rerunning rebuilt it and everything passed (not caused by this change; see the trap below).
- `scripts/build-app.sh`: signed `build/Reins.app`, `vtool` prints `minos 15.0`.
- `REINS_SHOT_SCREEN=settings scripts/dev-fixture.sh --shots <dir>`: 26 PNGs (both themes: Appearance, System chosen,
  Large, six Update states, the palette over Settings, and the demo shell's Loadout, Activity and Rules tabs at Large,
  not the screens read from the fixture) and the checks "Settings opens on Appearance", "the palette opens over
  Settings", "choosing a tab closes Settings". At Large, the demo Loadout's `12,345` wrapped before the `Metrics` widths
  followed the size and fits after.
- Sparkle source (2.x, `SPUProbingUpdateDriver.m` builds an `SPUBasicUpdateDriver`, whose not-found path calls
  `updaterDidNotFindUpdate:error:`): a probe that finds nothing reports `Up to date`. `status(afterCycle:)` also maps
  `SUNoUpdateError` to `Up to date` in case a cycle ends without that callback.
- `impeccable distill` and `clarify` on the surface: one copy change, a failed check now says "Could not read the update
  source." instead of the time of the check that failed.

Not verified here (no Screen Recording or keystroke permission for this session):
- In a live window: System following macOS, the theme tiles' colours, the back button's line with the window buttons,
  `⌘,` and `Esc`.
- `scripts/test-update.sh`: the owner's `/Applications/Reins.app` was running, and the script needs no Reins running. So
  the `Check Now` round trip against a real feed has no end-to-end check.
- Font size changing a live window without a relaunch: every shot renders fresh with the step already set.
- The real Loadout, Rules and Activity screens (fixture runs) at Large.
- Limits at Large (its shots need the Limits fixture; not added to the settings run).

Departures from mock A2: `Checking…` carries the refresh icon, not a spinner; the failed state is new; the Language card
is 64 pt (a card keeps 8 pt under its header); the tiles' window buttons are neutral dots, not red, yellow and green.

Trap found: the shared fixture keeps the fixture's old modification times, so a temp cleaner can delete its files while
`.fixture-stamp` still matches, and `FixtureHome.materialize()` then reuses a partial tree. Not fixed here (outside scope).

Remaining: S10, the owner's eye approval of the shots and of the live window.

/goal Build Reins Settings per docs/specs/2026-11-04-reins-settings.md: ST1–ST6 verified with scripts/test.sh, build-app.sh and the settings shots, then ST7 eye approval from the owner.
