> Global standard: ~/.claude v2026-09-29

# Reins

## Swift app (current direction)

The product is being rebuilt as a native SwiftUI app: [spec](docs/specs/2026-11-02-reins.md), [plan](docs/plans/2026-11-02-reins-swiftui.md). Everything below this section describes the superseded Electron app and the Node `core/`; it is deleted at plan task S8.3, not before.

Stack: SwiftPM, swift-tools 6.0, Swift 5 language mode, macOS 15+, Command Line Tools only (no Xcode). Everything in this repo's Swift code, comments and tests is English.

| Command                       | Purpose                                                                                                   |
| ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| `scripts/test.sh`             | All Swift tests against temporary folders. Look for `Test run with N tests ... passed`: N must be above 0 |
| `scripts/build-app.sh`        | Release build, `build/Reins.app`, signature, `vtool` deployment-target print                              |
| `scripts/dev.sh`              | Build, sign, relaunch. Opens a window and reads the real `~/.claude` and `~/.codex` unless the env points elsewhere |
| `scripts/test-update.sh`      | End-to-end update test through a feed on 127.0.0.1: a wrong signature is refused, the right one installs. Needs the Developer ID identity and no running Reins |
| `scripts/generate-update-feed.sh <dir> <https-prefix>` | Signed `appcast.xml` next to notarized, stapled DMGs. Publishes nothing |
| `node scripts/make-golden.mjs [section]` | Rewrites `Tests/ReinsCoreTests/Fixtures` (synthetic HOME, manifest, `golden/*.json`, `zst/`) from the Node core. Rerun gives no diff |

Layout: `Sources/CZstd` (vendored decompress-only zstd, see its README), `Sources/ReinsCore` (the engine; Foundation only, no UI import), `Sources/Reins` (the app), `Tests/ReinsCoreTests` (swift-testing; `Support/` has `TempHome` and `FixtureHome`), `Tests/ReinsTests` (app logic that needs no window).

Toolchain rules (taken from `spacevibe-board`, re-verified here):

- **B1. The deployment target is pinned.** The toolchain defaults to `arm64-apple-macosx28.0`; a binary built at that target refuses to launch on macOS 27 (`-10825`). `platforms: [.macOS(.v15)]` in [Package.swift](Package.swift) and `LSMinimumSystemVersion` 15.0 in [Resources/Info.plist](Resources/Info.plist) must agree. [`scripts/build-app.sh`](scripts/build-app.sh) prints `vtool -show-build-version` (expect `minos 15.0`).
- **B2. Use `scripts/test.sh`, never bare `swift test`.** swift-testing lives in `Library/Developer/Frameworks` under the Command Line Tools; the script passes the framework and rpath flags and sets `REINS_TEST=1`. Bare `swift test` fails to compile (`no such module 'Testing'`) here and can run nothing elsewhere. XCTest is not available.
- **B3. Bundle id `dev.spacevibe.reins` and the signing identity are load-bearing.** macOS keys folder consent (Documents, Desktop) on bundle id plus team. `build-app.sh` signs with the Developer ID identity when it is in the keychain (name overridable with `REINS_SIGNING_IDENTITY`), otherwise ad-hoc, which makes macOS ask again after each rebuild. Never change the bundle id as a drive-by.
- **B4. Swift 5 language mode on every target, deliberately.** Do not flip a target to Swift 6 as a drive-by change.
- **B5. zstd is vendored, never linked from the system.** macOS ships no usable libzstd (no header in the SDK, none in `/usr/lib`, no zstd in the Compression framework), and Homebrew's copy is absent on a clean Mac. [`Sources/CZstd`](Sources/CZstd/README.md) is an unmodified copy of facebook/zstd 1.5.7 `lib/` (decompress only, BSD); update it from a release tarball and change the version and checksum in its README.
- **B7. `ReinsCore` stays portable** ([spec, Platform](docs/specs/2026-11-02-reins.md)): Foundation only, no AppKit or other Apple-only import, no Darwin-only API outside `#if canImport(Darwin)` (see `modificationTime` in [TailReader.swift](Sources/ReinsCore/TailReader.swift)), vendored zstd. POSIX calls (`open`, `pread`, `realpath`, `getpwuid`) are used directly and exist on Linux but not Windows; a Linux build is unverified until plan task S0.6. Tests may use Apple frameworks (`CryptoKit`).
- **B6. Golden tests read the fixture at a fixed path.** Hook and project ids are hashes of absolute paths, so [`FixtureHome`](Tests/ReinsCoreTests/Support/FixtureHome.swift) materializes the tree at `/private/tmp/reins-fixture-home` (the path [`make-golden.mjs`](scripts/make-golden.mjs) ran the Node core on). That tree is read-only and shared; a test that writes uses `FixtureHome.materialize(into:)` or `TempHome`.
- **B8. The update signing key is load-bearing.** The private half of `SUPublicEDKey` ([Info.plist](Resources/Info.plist)) is in the owner's login Keychain under the Sparkle account `dev.spacevibe.reins`. Never regenerate it once a release has shipped: installed copies would refuse every later update. On another machine move it with `generate_keys -x` and `-f`. `Sparkle` is linked by the `Reins` target only, never `ReinsCore` (B7), and [`build-app.sh`](scripts/build-app.sh) signs its helpers inside out before the app.

Boundary rules for the Swift app (the Electron rules R1 to R6 below keep applying to the Node code until it is deleted):

- **S-R1. Tests and agents never touch the real config.** Tests build a `TempHome` or use `FixtureHome`. [`Roots.resolve`](Sources/ReinsCore/Roots.swift) throws when `REINS_TEST=1` and a root, or the real path behind it (symlinks included), is under the real home from `getpwuid`; [`scripts/test.sh`](scripts/test.sh) sets that flag. `scripts/dev.sh` and the built app read the real `~/.claude` and `~/.codex`: set `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `REINS_HOME` to a temporary folder before testing a write by hand.
- **S-R2. No real data in committed files.** Fixtures and goldens come from `scripts/fixture-home.mjs` (synthetic names only) through [`make-golden.mjs`](scripts/make-golden.mjs), which refuses a tree containing the real home path or user name; [`FixtureHomeTests`](Tests/ReinsCoreTests/FixtureHomeTests.swift) re-checks. Screenshots from a real config stay out of git (R2 above).
- **S-R3. Secrets are never read into the UI or logged.** Errors from `OrderedJSON`, `TOMLReader` and `ZstdStream` carry a position or a fixed reason, never file content; keep it that way in new code.
- **S-R4. The app never executes a hook or a recorded command.** The only processes it will start are the fixed `ps`, `lsof` and `kill` of the Activity engine, with the pid re-validated first, and Sparkle's own installer helpers.
- **S-R5. The app opens no network listener, and its only requests are Sparkle's update check and download**, started by [`UpdateController`](Sources/Reins/App/UpdateController.swift) in a normal launch of a build with `REINS_UPDATE_FEED_URL` set; `scripts/dev.sh`, fixture launches and `REINS_TEST=1` make none. No crash reporter, no analytics, no system profile, no other request.

The Node `core/` is an oracle for parity and is deleted at plan task S8.3. Do not change its behavior to suit Swift; when a golden has to change, run `node scripts/make-golden.mjs`, read the diff and commit it with the test that needs it.

## Electron app (superseded)

Local app to see and control what Claude Code and Codex CLI are equipped with. Stack: Electron (main process in TypeScript) with a React, Tailwind CSS v4 and shadcn/ui (Base UI) renderer, built by electron-vite. The engine in [core/](core) is plain Node ESM (`.mjs`, JSDoc), unbundled.

## Common commands

| Command             | Purpose                                                                 |
| ------------------- | ----------------------------------------------------------------------- |
| `npm run dev`       | App with hot reload. Reads and writes the real `~/.claude` and `~/.codex` |
| `npm run build`     | Builds `out/` (main, preload, renderer)                                 |
| `npm start`         | Runs the built app from `out/` (no dev server)                          |
| `npm run typecheck` | `tsc` for [electron/](electron) and [src/](src)                         |
| `npm test`          | Core and IPC handler tests, against a temporary `HOME`                  |
| `npm run e2e:smoke` | Headless run of the built app against fixture logs ([e2e/smoke.mjs](e2e/smoke.mjs)) |
| `npm run pack`      | Unpacked macOS app in `release/` (`electron-builder --dir`, unsigned)    |

## Layout

- [core/](core): the engine (inventory, usage scan, mutations, journal). Never imports Electron.
- [electron/main.ts](electron/main.ts): app start, window, usage worker. [electron/ipc/](electron/ipc): one file per area, each exports `handlers`; [electron/register-ipc.ts](electron/register-ipc.ts) picks them up by glob.
- [src/lib/ipc-contract.ts](src/lib/ipc-contract.ts): the one list of channels and payload types. A new channel is this file plus one handler file.
- [src/](src): the renderer. It only sees `window.reins.invoke(channel, request)`.
- `web/` is the old prototype. It cannot run any more (its server is gone) and is deleted with the Loadout screen in the [plan](docs/plans/2026-11-02-reins-electron.md) task 4.4.
- `mocks/` holds earlier throwaway mocks kept for reference, outside git. Do not import from them.

## Repo-specific rules

- **R1.** `npm run dev` and `npm start` read and write the real `~/.claude` and `~/.codex`. Agents testing a write must set `HOME` (and `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `REINS_HOME`) to a temporary folder. With `REINS_TEST=1` the app runs headless (no window, counts only on stdout) and `roots()` throws when a root is under the real home.
- **R2.** Screenshots and fixtures from real configs or logs are never committed: they contain real skill names, hook commands and prompts. Keep them in the gitignored `shots/`.
- **R3.** Values in settings files that may be secrets are never read into the UI or logged.
- **R4.** The app never executes a hook or a recorded command.
- **R5.** The built app opens no network listener and loads from `file:`. The renderer reaches `core/` only through the channels in `src/lib/ipc-contract.ts`: the preload refuses any other channel, and main refuses a sender that is not the app's own top frame. The window stays `contextIsolation` + `sandbox`, with navigation and `window.open` denied, no auto-updater and no crash reporter. Do not widen any of these to make a feature easier.
- **R6.** [`stopSession`](core/activity.mjs) is the only code that signals a process, and it sends SIGTERM only to a pid it found itself and matched to the session at that moment (Claude: status file plus process start time; Codex: thread lock). A handler takes a session id, never a pid. With `REINS_TEST=1` it answers from the fake and signals nothing.

## Known traps

- The CSP in [src/index.html](src/index.html) forbids inline `style` attributes and inline scripts (`style-src 'self'`). Setting `element.style` from React is fine; markup strings with `style=` are not. The dev server gets a looser policy from `electron.vite.config.ts`, so a clean dev console proves nothing: run `npm run build && npm run e2e:smoke`, which fails on any CSP violation.
- `core/` is imported as `#core/*.mjs` (`imports` in `package.json`) and left external by the bundler. A relative path gets rewritten wrongly, and a bundled copy would break the usage Worker, which needs a real file. Packaged, `core/` is `asarUnpack`ed and the Worker path swaps `app.asar` for `app.asar.unpacked` ([electron/lib/worker-path.ts](electron/lib/worker-path.ts)).
- The preload must be CommonJS (`out/preload/index.cjs`): a sandboxed preload cannot be ESM, even though the package is `"type": "module"`. The contract file is bundled into it, so it imports nothing from Node or Electron.
- Errors cross IPC as a value, `{ ok: false, error, status }`, never as a thrown error: `ipcMain.handle` rewrites thrown messages and drops `status`. Unexpected errors log only their code or name, never the message (R3).
- Handlers in `electron/ipc/` must not import `electron`, so `npm test` can run them under plain node. Anything that needs Electron goes in `main.ts`, `register-ipc.ts` or `harden.ts`.
- Codex keeps older rollouts as `.jsonl.zst`. Find and open logs through [core/log-files.mjs](core/log-files.mjs), which handles both forms; a reader that only matches `.jsonl` silently misses most of a machine's Codex history.
- A hook's identity is the hash of event plus command. Hashing the command alone inflates run counts.
