> Global standard: ~/.claude v2026-09-29

# Reins

## Read before work

Always: [PRODUCT.md](PRODUCT.md) (purpose, jobs in priority order, colour meanings; wins any UI or copy conflict) and [GLOSSARY.md](GLOSSARY.md) (one word, one meaning; use these terms in comments, labels and docs). Read the rest only when the task touches it:

- UI of any page: [design language](docs/DESIGN-LANGUAGE.md), then the spec and plan of that page.
- A decision or its wording: the [identity decisions](docs/specs/2026-11-06-reins-linear-identity-decisions.md). Cite the D-id; never narrow one (W20).
- An engine subsystem (the Go core under `core/`): its page in the [internals index](docs/internals/README.md); where no page exists yet ([plan](docs/plans/2026-11-07-reins-internals-docs.md)), the spec and "Known traps" below.

A change to a documented responsibility, interface, state transition, path or failure behavior updates the owning page in the same PR. A refactor that keeps the contract needs no prose change. Each fact lives in one page; link to it, do not copy it.

## Swift app (current direction)

The product is being rebuilt as a native SwiftUI app: [spec](docs/specs/2026-11-02-reins.md), [plan](docs/plans/2026-11-02-reins-swiftui.md). The Electron app is gone (removed 2026-11-04); the engine is the Go core in `core/` ([overview](docs/internals/overview.md)).

Stack: SwiftPM, swift-tools 6.0, Swift 5 language mode, macOS 15+, Command Line Tools only (no Xcode). Everything in this repo's Swift code, comments and tests is English.

| Command                       | Purpose                                                                                                   |
| ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| `cd core && go vet ./... && SPACEVIBE_TEST=1 go test -count=1 ./...` | Go core tests (module `spacevibe.dev/core`, `CGO_ENABLED=0`). `scripts/test.sh` runs them first |
| `scripts/build-core.sh <out> [version]` | Builds the Go core `spacevibe` for the host arch with `-trimpath` and the version stamped in. `build-app.sh` puts it at `Contents/Helpers/spacevibe`; `test.sh` and `dev-fixture.sh` export `SPACEVIBE_CORE_BINARY` |
| `scripts/test.sh`             | Go tests, then all Swift tests against temporary folders. Look for `Test run with N tests ... passed`: N must be above 0 |
| `scripts/build-app.sh [--distribution]` | Release build, `build/SpaceVibe.app` with the icon rendered from `Resources/AppIcon.svg`, signature, `vtool` deployment-target print. `--distribution`: Developer ID required, secure timestamp, `SPACEVIBE_UPDATE_FEED_URL` required |
| `scripts/dev.sh`              | Build, sign, relaunch. Opens a window and reads the real `~/.claude` and `~/.codex` unless the env points elsewhere |
| `scripts/test-update.sh`      | End-to-end update test through a feed on 127.0.0.1: a wrong signature is refused, the right one installs. Needs the Developer ID identity and no running Reins |
| `scripts/generate-update-feed.sh <dir> <https-prefix>` | Signed `appcast.xml` next to notarized, stapled DMGs. Publishes nothing |
| `scripts/release.sh --prepare \| --notarize` | One committed revision as a signed DMG; `--notarize` adds notarization, stapling, `appcast.xml` and `SHA256SUMS` in `build/distribution/`. Publishes nothing (B9) |
| `node scripts/generate-icons.mjs <solar> <mingcute> <ph>` | Each argument is that package's `icons.json`. Rewrites `ReinsIconData.swift` (`@iconify-json/solar`, old screens), `CategoryIconData.swift` (`mingcute`, Skills, Subagents, Hooks) and `ContentIconData.swift` (`ph`, sidebar and content glyphs) in `Sources/SpaceVibe/Components`. `npm pack @iconify-json/solar@1.2.13 @iconify-json/mingcute@1.2.10 @iconify-json/ph@1.2.2` into a scratch folder and untar (never commit it); the headers record the version, a rerun gives no diff. [`Credits`](Sources/SpaceVibe/App/Credits.swift) holds each licence notice, and the Apache-2.0 text for MingCute ships as `Resources/Licenses/*.txt` through `build-app.sh` |

Layout: `core/` (the Go engine, one module, tests beside the code), `Sources/SpaceVibe` (the app, UI only), `Tests/SpaceVibeTests` (swift-testing: app logic that needs no window, plus `CoreClient` tests against the built core).

Design language: [docs/DESIGN-LANGUAGE.md](docs/DESIGN-LANGUAGE.md). Screens only compose [`Sources/SpaceVibe/Components`](Sources/SpaceVibe/Components) and the tokens in [`Sources/SpaceVibe/Tokens`](Sources/SpaceVibe/Tokens); [`StyleBoundaryTests`](Tests/SpaceVibeTests/StyleBoundaryTests.swift) fails on a font, colour, radius or spacing literal in a screen folder. Inter (OFL, `Resources/Fonts`) is the only typeface.

Public site: [`site/`](site/README.md) is the page for `reins.spacevibe.dev` (Next.js static export + Tailwind, its own `package.json` and lockfile, built with `npm run build` inside `site/`). It is independent of the Swift build; its example rows mirror the synthetic fixture home, never a real `~/.claude` (S-R2).

Toolchain rules (taken from `spacevibe-board`, re-verified here):

- **B1. The deployment target is pinned.** The toolchain defaults to `arm64-apple-macosx28.0`; a binary built at that target refuses to launch on macOS 27 (`-10825`). `platforms: [.macOS(.v15)]` in [Package.swift](Package.swift) and `LSMinimumSystemVersion` 15.0 in [Resources/Info.plist](Resources/Info.plist) must agree. [`scripts/build-app.sh`](scripts/build-app.sh) prints `vtool -show-build-version` (expect `minos 15.0`).
- **B2. Use `scripts/test.sh`, never bare `swift test`.** swift-testing lives in `Library/Developer/Frameworks` under the Command Line Tools; the script passes the framework and rpath flags and sets `SPACEVIBE_TEST=1`. Bare `swift test` fails to compile (`no such module 'Testing'`) here and can run nothing elsewhere. XCTest is not available.
- **B3. Bundle id `dev.spacevibe.app` and the signing identity are load-bearing.** macOS keys folder consent (Documents, Desktop) on bundle id plus team. `build-app.sh` signs with the Developer ID identity when it is in the keychain (name overridable with `SPACEVIBE_SIGNING_IDENTITY`), otherwise ad-hoc, which makes macOS ask again after each rebuild. Never change the bundle id as a drive-by. The old id `dev.spacevibe.reins` belongs to the deprecated v0.1.0 and is not migrated (preferences, folder consent and the defaults domain start fresh, SV15).
- **B4. Swift 5 language mode on every target, deliberately.** Do not flip a target to Swift 6 as a drive-by change.
- **B6. Golden tests read the fixture at a fixed path.** Hook and project ids are hashes of absolute paths, so [`goldentest`](core/internal/goldentest/fixture-home.go) materializes the tree at `/private/tmp/reins-fixture-home` (the path the frozen goldens were generated on, SV5). That tree is read-only and shared; a Go test that writes copies it into `t.TempDir()`, and a Swift test uses its own copy from `CoreFixtureHome`.
- **B8. The update signing key is load-bearing.** The private half of `SUPublicEDKey` ([Info.plist](Resources/Info.plist)) lives in the owner's login Keychain under the Sparkle account `dev.spacevibe.app`. The owner must create that key pair before the first release, once, with `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.spacevibe.app`, paste the printed public key into `SUPublicEDKey` and back it up at once with `generate_keys --account dev.spacevibe.app -x <file>` into the password manager (agents never run `generate_keys`: it writes the Keychain). Until then Info.plist still carries the key of the old account `dev.spacevibe.reins`, which belongs to the deprecated v0.1.0 and is never used for the new bundle; no build with that key may ship. Then flip `SIGNING_ACCOUNT` in [`generate-update-feed.sh`](scripts/generate-update-feed.sh) and `SPARKLE_ACCOUNT` in [`test-update.sh`](scripts/test-update.sh) to `dev.spacevibe.app`. Never regenerate the new key once a release has shipped: installed copies would refuse every later update. On another machine move it with `generate_keys -x` and `-f`. `Sparkle` is linked by the `Reins` target only, and [`build-app.sh`](scripts/build-app.sh) signs its helpers inside out before the app.
- **B9. A release is `scripts/release.sh --notarize` on a clean `main`.** It builds from `git archive HEAD`, signs with a secure timestamp, notarizes through the Keychain profile named in `SPACEVIBE_NOTARY_PROFILE` (created once with `xcrun notarytool store-credentials`), staples, and writes the DMG, `SHA256SUMS` and the signed `appcast.xml` to `build/distribution/`. The key in [Info.plist](Resources/Info.plist) must be the new account's (B8) before the first release; v0.1.0 copies are not updated to the new app (SV11). Both version keys in [Info.plist](Resources/Info.plist) change on every release: `CFBundleVersion` is the whole number Sparkle compares, and the script refuses one that is not above the last `v*` tag. Shipped copies read the feed at `https://github.com/mxrsv/spacevibe-reins/releases/latest/download/appcast.xml`, so every GitHub release carries the DMG plus an asset named exactly `appcast.xml`, and the repository must stay public under that name or installed copies stop updating. The tag, the push and `gh release create` are done by hand; the script prints them.

Boundary rules for the Swift app:

- **S-R1. Tests and agents never touch the real config.** Go tests use `t.TempDir()` or the fixture home, Swift tests use `CoreFixtureHome`. [`roots.Resolve`](core/internal/roots/roots.go) and its [guard](core/internal/roots/guard.go) refuse when `SPACEVIBE_TEST=1` and a root, or the real path behind it (symlinks included), is under the real home from `getpwuid`; [`scripts/test.sh`](scripts/test.sh) sets that flag. `scripts/dev.sh` and the built app read the real `~/.claude` and `~/.codex`: set `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `SPACEVIBE_HOME` to a temporary folder before testing a write by hand.
- **S-R2. No real data in committed files.** Fixtures and goldens come from `scripts/fixture-home.mjs` (synthetic names only) and are frozen (SV5); [`TestLeakNoRealHomeOrUserNameUnderTestdata`](core/internal/goldentest/leak_test.go) re-checks that none holds the real home path or user name. Screenshots from a real config stay out of git (they go in the gitignored `shots/`).
- **S-R3. Secrets are never read into the UI or logged.** Errors from [`ojson`](core/internal/ojson), [`toml`](core/internal/toml) and the [zstd reader](core/internal/logs/zstd-stream.go) carry a position or a fixed reason, never file content; keep it that way in new code.
- **S-R4. The app never executes a hook or a recorded command.** The only processes it will start are the fixed `ps`, `lsof` and `kill` of the core's [process adapter](core/internal/proc/adapter.go), with the pid re-validated first, and Sparkle's own installer helpers.
- **S-R5. The app opens no network listener, and its only requests are Sparkle's update check and download**, started by [`UpdateController`](Sources/SpaceVibe/App/UpdateController.swift) in a normal launch of a build with `SPACEVIBE_UPDATE_FEED_URL` set; a build without it, fixture launches and `SPACEVIBE_TEST=1` make none. No crash reporter, no analytics, no system profile, no other request.

- `mocks/` holds earlier throwaway mocks kept for reference. Do not import from them. Two are tracked with synthetic data as targets. `mocks/tokens-board/` serves the [Tokens plan](docs/plans/2026-11-03-reins-tokens.md) and is deleted when that plan's T8 passes. `mocks/agents/` serves the [Agents](docs/plans/2026-11-05-reins-agents.md) and [design language v4](docs/plans/2026-11-05-reins-design-language-v4.md) plans and is deleted at Agents A12; its `assets/` link to the font and marks in `Resources/`.
- **R6.** [`activity.Stop`](core/internal/activity/stop.go) is the only code that signals a process, and it sends SIGTERM only to a pid it found itself and matched to the session at that moment. With `SPACEVIBE_TEST=1` it answers from the fixture.

## Known traps

- Codex keeps older rollouts as `.jsonl.zst`. Find and open logs through [log-files.go](core/internal/logs/log-files.go), which handles both forms; a reader that only matches `.jsonl` silently misses most of a machine's Codex history.
- A hook's identity is the hash of event plus command. Hashing the command alone inflates run counts.
