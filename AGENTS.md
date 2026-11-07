> Global standard: ~/.claude v2026-09-29

# Reins

## Read before work

Always: [PRODUCT.md](PRODUCT.md) (purpose, jobs in priority order, colour meanings; wins any UI or copy conflict) and [GLOSSARY.md](GLOSSARY.md) (one word, one meaning; use these terms in comments, labels and docs). Read the rest only when the task touches it:

- UI of any page: [design language](docs/DESIGN-LANGUAGE.md), then the spec and plan of that page.
- A decision or its wording: the [identity decisions](docs/specs/2026-11-06-reins-linear-identity-decisions.md). Cite the D-id; never narrow one (W20).
- A `ReinsCore` subsystem: its page in the [internals index](docs/internals/README.md); where no page exists yet ([plan](docs/plans/2026-11-07-reins-internals-docs.md)), the spec and "Known traps" below.

A change to a documented responsibility, interface, state transition, path or failure behavior updates the owning page in the same PR. A refactor that keeps the contract needs no prose change. Each fact lives in one page; link to it, do not copy it.

## Swift app (current direction)

The product is being rebuilt as a native SwiftUI app: [spec](docs/specs/2026-11-02-reins.md), [plan](docs/plans/2026-11-02-reins-swiftui.md). The Electron app is gone (removed 2026-11-04); the Node `core/` stays as the parity oracle until plan task S8.3 (see "Node core" below).

Stack: SwiftPM, swift-tools 6.0, Swift 5 language mode, macOS 15+, Command Line Tools only (no Xcode). Everything in this repo's Swift code, comments and tests is English.

| Command                       | Purpose                                                                                                   |
| ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| `scripts/test.sh`             | All Swift tests against temporary folders. Look for `Test run with N tests ... passed`: N must be above 0 |
| `scripts/build-app.sh [--distribution]` | Release build, `build/Reins.app` with the icon rendered from `Resources/AppIcon.svg`, signature, `vtool` deployment-target print. `--distribution`: Developer ID required, secure timestamp, `REINS_UPDATE_FEED_URL` required |
| `scripts/dev.sh`              | Build, sign, relaunch. Opens a window and reads the real `~/.claude` and `~/.codex` unless the env points elsewhere |
| `scripts/test-update.sh`      | End-to-end update test through a feed on 127.0.0.1: a wrong signature is refused, the right one installs. Needs the Developer ID identity and no running Reins |
| `scripts/generate-update-feed.sh <dir> <https-prefix>` | Signed `appcast.xml` next to notarized, stapled DMGs. Publishes nothing |
| `scripts/release.sh --prepare \| --notarize` | One committed revision as a signed DMG; `--notarize` adds notarization, stapling, `appcast.xml` and `SHA256SUMS` in `build/distribution/`. Publishes nothing (B9) |
| `node scripts/generate-icons.mjs <icons.json>` | Rewrites `Sources/Reins/Components/ReinsIconData.swift` from `@iconify-json/solar` (`npm pack` it into a scratch folder; never commit it). Rerun gives no diff |
| `node scripts/make-golden.mjs [section]` | Rewrites `Tests/ReinsCoreTests/Fixtures` (synthetic HOME, manifest, `golden/*.json`, `zst/`) from the Node core. Rerun gives no diff |

Layout: `Sources/CZstd` (vendored decompress-only zstd, see its README), `Sources/ReinsCore` (the engine; Foundation only, no UI import), `Sources/Reins` (the app), `Tests/ReinsCoreTests` (swift-testing; `Support/` has `TempHome` and `FixtureHome`), `Tests/ReinsTests` (app logic that needs no window).

Design language: [docs/DESIGN-LANGUAGE.md](docs/DESIGN-LANGUAGE.md). Screens only compose [`Sources/Reins/Components`](Sources/Reins/Components) and the tokens in [`Sources/Reins/Tokens`](Sources/Reins/Tokens); [`StyleBoundaryTests`](Tests/ReinsTests/StyleBoundaryTests.swift) fails on a font, colour, radius or spacing literal in a screen folder. Inter (OFL, `Resources/Fonts`) is the only typeface.

Public site: [`site/`](site/README.md) is the page for `reins.spacevibe.dev` (Next.js static export + Tailwind, its own `package.json` and lockfile, built with `npm run build` inside `site/`). It is independent of the root `package.json` (core tests only) and of the Swift build; its example rows mirror the synthetic fixture home, never a real `~/.claude` (S-R2).

Toolchain rules (taken from `spacevibe-board`, re-verified here):

- **B1. The deployment target is pinned.** The toolchain defaults to `arm64-apple-macosx28.0`; a binary built at that target refuses to launch on macOS 27 (`-10825`). `platforms: [.macOS(.v15)]` in [Package.swift](Package.swift) and `LSMinimumSystemVersion` 15.0 in [Resources/Info.plist](Resources/Info.plist) must agree. [`scripts/build-app.sh`](scripts/build-app.sh) prints `vtool -show-build-version` (expect `minos 15.0`).
- **B2. Use `scripts/test.sh`, never bare `swift test`.** swift-testing lives in `Library/Developer/Frameworks` under the Command Line Tools; the script passes the framework and rpath flags and sets `REINS_TEST=1`. Bare `swift test` fails to compile (`no such module 'Testing'`) here and can run nothing elsewhere. XCTest is not available.
- **B3. Bundle id `dev.spacevibe.reins` and the signing identity are load-bearing.** macOS keys folder consent (Documents, Desktop) on bundle id plus team. `build-app.sh` signs with the Developer ID identity when it is in the keychain (name overridable with `REINS_SIGNING_IDENTITY`), otherwise ad-hoc, which makes macOS ask again after each rebuild. Never change the bundle id as a drive-by.
- **B4. Swift 5 language mode on every target, deliberately.** Do not flip a target to Swift 6 as a drive-by change.
- **B5. zstd is vendored, never linked from the system.** macOS ships no usable libzstd (no header in the SDK, none in `/usr/lib`, no zstd in the Compression framework), and Homebrew's copy is absent on a clean Mac. [`Sources/CZstd`](Sources/CZstd/README.md) is an unmodified copy of facebook/zstd 1.5.7 `lib/` (decompress only, BSD); update it from a release tarball and change the version and checksum in its README.
- **B7. `ReinsCore` stays portable** ([spec, Platform](docs/specs/2026-11-02-reins.md)): Foundation only, no AppKit or other Apple-only import, no Darwin-only API outside `#if canImport(Darwin)` (see `modificationTime` in [TailReader.swift](Sources/ReinsCore/TailReader.swift)), vendored zstd. POSIX calls (`open`, `pread`, `realpath`, `getpwuid`) are used directly and exist on Linux but not Windows; a Linux build is unverified until plan task S0.6. Tests may use Apple frameworks (`CryptoKit`).
- **B6. Golden tests read the fixture at a fixed path.** Hook and project ids are hashes of absolute paths, so [`FixtureHome`](Tests/ReinsCoreTests/Support/FixtureHome.swift) materializes the tree at `/private/tmp/reins-fixture-home` (the path [`make-golden.mjs`](scripts/make-golden.mjs) ran the Node core on). That tree is read-only and shared; a test that writes uses `FixtureHome.materialize(into:)` or `TempHome`.
- **B8. The update signing key is load-bearing.** The private half of `SUPublicEDKey` ([Info.plist](Resources/Info.plist)) is in the owner's login Keychain under the Sparkle account `dev.spacevibe.reins`. Never regenerate it once a release has shipped: installed copies would refuse every later update. On another machine move it with `generate_keys -x` and `-f`. `Sparkle` is linked by the `Reins` target only, never `ReinsCore` (B7), and [`build-app.sh`](scripts/build-app.sh) signs its helpers inside out before the app.
- **B9. A release is `scripts/release.sh --notarize` on a clean `main`.** It builds from `git archive HEAD`, signs with a secure timestamp, notarizes through the Keychain profile named in `REINS_NOTARY_PROFILE` (created once with `xcrun notarytool store-credentials`), staples, and writes the DMG, `SHA256SUMS` and the signed `appcast.xml` to `build/distribution/`. Both version keys in [Info.plist](Resources/Info.plist) change on every release: `CFBundleVersion` is the whole number Sparkle compares, and the script refuses one that is not above the last `v*` tag. Shipped copies read the feed at `https://github.com/mxrsv/spacevibe-reins/releases/latest/download/appcast.xml`, so every GitHub release carries the DMG plus an asset named exactly `appcast.xml`, and the repository must stay public under that name or installed copies stop updating. The tag, the push and `gh release create` are done by hand; the script prints them.

Boundary rules for the Swift app:

- **S-R1. Tests and agents never touch the real config.** Tests build a `TempHome` or use `FixtureHome`. [`Roots.resolve`](Sources/ReinsCore/Roots.swift) throws when `REINS_TEST=1` and a root, or the real path behind it (symlinks included), is under the real home from `getpwuid`; [`scripts/test.sh`](scripts/test.sh) sets that flag. `scripts/dev.sh` and the built app read the real `~/.claude` and `~/.codex`: set `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `REINS_HOME` to a temporary folder before testing a write by hand.
- **S-R2. No real data in committed files.** Fixtures and goldens come from `scripts/fixture-home.mjs` (synthetic names only) through [`make-golden.mjs`](scripts/make-golden.mjs), which refuses a tree containing the real home path or user name; [`FixtureHomeTests`](Tests/ReinsCoreTests/FixtureHomeTests.swift) re-checks. Screenshots from a real config stay out of git (they go in the gitignored `shots/`).
- **S-R3. Secrets are never read into the UI or logged.** Errors from `OrderedJSON`, `TOMLReader` and `ZstdStream` carry a position or a fixed reason, never file content; keep it that way in new code.
- **S-R4. The app never executes a hook or a recorded command.** The only processes it will start are the fixed `ps`, `lsof` and `kill` of the Activity engine, with the pid re-validated first, and Sparkle's own installer helpers.
- **S-R5. The app opens no network listener, and its only requests are Sparkle's update check and download**, started by [`UpdateController`](Sources/Reins/App/UpdateController.swift) in a normal launch of a build with `REINS_UPDATE_FEED_URL` set; a build without it, fixture launches and `REINS_TEST=1` make none. No crash reporter, no analytics, no system profile, no other request.

The Node `core/` is an oracle for parity and is deleted at plan task S8.3. Do not change its behavior to suit Swift; when a golden has to change, run `node scripts/make-golden.mjs`, read the diff and commit it with the test that needs it.

## Node core (parity oracle)

The Electron app was removed on 2026-11-04 (its code is in git history before that commit). What remains of the Node side is [core/](core), the plain Node ESM engine (inventory, usage scan, mutations, journal, Activity) that the Swift core was ported from and that generates the golden files; plan task S8.3 deletes it with `scripts/make-golden.mjs` and `scripts/golden/` once the owner agrees the goldens no longer need regenerating.

| Command | Purpose |
| --- | --- |
| `npm test` | `test.mjs` and `core/*.test.mjs`, against a temporary `HOME` |
| `node scripts/make-golden.mjs [section]` | Rewrites `Tests/ReinsCoreTests/Fixtures` from the Node core (see above) |

- `mocks/` holds earlier throwaway mocks kept for reference. Do not import from them. Two are tracked with synthetic data as targets. `mocks/tokens-board/` serves the [Tokens plan](docs/plans/2026-11-03-reins-tokens.md) and is deleted when that plan's T8 passes. `mocks/agents/` serves the [Agents](docs/plans/2026-11-05-reins-agents.md) and [design language v4](docs/plans/2026-11-05-reins-design-language-v4.md) plans and is deleted at Agents A12; its `assets/` link to the font and marks in `Resources/`.
- **R6.** [`stopSession`](core/activity.mjs) is the only Node code that signals a process, and it sends SIGTERM only to a pid it found itself and matched to the session at that moment. With `REINS_TEST=1` it answers from the fixture.

## Known traps

- Codex keeps older rollouts as `.jsonl.zst`. Find and open logs through [core/log-files.mjs](core/log-files.mjs), which handles both forms; a reader that only matches `.jsonl` silently misses most of a machine's Codex history.
- A hook's identity is the hash of event plus command. Hashing the command alone inflates run counts.
