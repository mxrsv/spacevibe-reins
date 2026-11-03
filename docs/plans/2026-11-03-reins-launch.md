# Reins launch: release configuration

Date: 2026-11-03
Status: in progress. The tooling tasks (L1 to L4) are built and verified; the owner-only steps and the first release are open.
Requirements: the Distribution and Constraints sections of the [Reins spec](../specs/2026-11-02-reins.md) and the Distribution section of [PRODUCT.md](../../PRODUCT.md). Owner's ask on 2026-11-03: launch early, then optimize a little every day. No separate spec; this plan records the release decisions and their evidence.
Scope: everything a public build needs that the [SwiftUI plan](2026-11-02-reins-swiftui.md) leaves to "release work": icon, bundle metadata, timestamped signing, notarization, DMG, update feed, version discipline, hosting, the public repository. The product gates (eye approvals, AC2, offline) stay in that plan and are listed here only as launch blockers.

## Decisions

Proposed 2026-11-03; each one is reversible until the first release ships. Items marked "owner" wait for the owner's word.

- **Feed and downloads on GitHub Releases.** The app's `SUFeedURL` is `https://github.com/mxrsv/spacevibe-reins/releases/latest/download/appcast.xml`; each release uploads the DMG and an asset named `appcast.xml`. Reason: the landing page already sends "Download for macOS" to `releases/latest` (owner, 2026-11-03), one `gh release create` publishes both, no DNS and no site deploy per release. Cost: the repository must be public under this name while any installed copy is alive. Moving the feed later is one release away (a newer build carries the new URL). Owner: confirm, or choose `https://reins.spacevibe.dev/appcast.xml`, which needs the DNS record and a site deploy on every release.
- **Releases are built on the owner's Mac**, not in CI. Reason: notarization and Developer ID signing in GitHub Actions need the certificate and an App Store Connect key as repository secrets; one Mac and one releaser do not justify that yet. The `swift` workflow keeps testing and building ad-hoc on PRs. Revisit when a second releaser or a second machine exists.
- **The app icon is the existing Reins mark** (`site/public/icon.svg`, the hub's `public/reins/icon.svg` without the fuchsia), rendered by `scripts/build-icon.swift` into the standard 824-of-1024 macOS squircle. A designed icon can replace the SVG later without touching the build. Owner: eye approval of the rendered icon (`~/scratch/spacevibe-reins/shots/app-icon-512.png`, in the Dock after `scripts/dev.sh`).
- **Version discipline:** `CFBundleShortVersionString` is the public version (semver), `CFBundleVersion` a whole number raised by at least one per release; both live only in `Resources/Info.plist`. The tag is `v<short version>`.
- **No DNS and no site deploy for the first release** (owner decision pending, spec Identity: the domain waits for 500 to 1,000 users). The site builds statically and can go live as a Vercel project rooted at `site/` the day the owner approves the record.

## Tasks

### Tooling (this repository)

- [x] L1 App icon: `Resources/AppIcon.svg`, `scripts/build-icon.swift`, `CFBundleIconFile` in `Resources/Info.plist`, rendered by `scripts/build-app.sh` on every build. Done 2026-11-03; 512 px preview at `~/scratch/spacevibe-reins/shots/app-icon-512.png`.
- [x] L2 Bundle metadata: `LSApplicationCategoryType` developer-tools, `NSHumanReadableCopyright`, and the Desktop, Documents and Downloads usage descriptions that the macOS consent prompt shows (spec Platform: a denied folder reads as not readable). Done 2026-11-03.
- [x] L3 `scripts/build-app.sh --distribution`: Developer ID required (no ad-hoc fallback), `--timestamp` (notarization refuses a signature without a secure timestamp), HTTPS `REINS_UPDATE_FEED_URL` required. Development builds are unchanged. Done 2026-11-03.
- [x] L4 `scripts/release.sh --prepare | --notarize`: refuses a dirty tree, an existing `v<version>` tag and a `CFBundleVersion` not above the last tag; builds from `git archive HEAD`; notarizes and staples app and DMG through `REINS_NOTARY_PROFILE`; `spctl` assessments; `SHA256SUMS`; `appcast.xml` through `scripts/generate-update-feed.sh`; prints the tag, push and `gh release create` commands instead of running them. Done 2026-11-03 (`--prepare` verified; `--notarize` waits for L5).
- [x] L5 `AGENTS.md`: command rows and rule B9. Done 2026-11-03.

### Owner-only steps

- [ ] L6 Notarization credentials, once: `xcrun notarytool store-credentials reins --apple-id <Apple ID> --team-id DJDD3T8LH7 --password <app-specific password>`, then `export REINS_NOTARY_PROFILE=reins` in the shell that releases. An App Store Connect API key works too (`--key`, `--key-id`, `--issuer`).
- [ ] L7 Sparkle private key backup: `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.spacevibe.reins -x <file outside any repo>`, store the file in the password manager, delete it from disk. Losing the Keychain copy means no installed copy can ever update again (AGENTS.md B8).
- [ ] L8 Repository public, with a root `README.md` (what it is, download link, how to build) and a `LICENSE`. The licence and the README language are the owner's choice; the site and the Swift code are English.
- [ ] L9 Launch blockers from the SwiftUI plan, in that plan: S0.5 (AC2, a real `claude` and `codex` honor what the app writes), S8.1 (AC5, offline), the eye approvals S3.3 to S7.3, and a decision on the Tokens tab, which the landing page describes but the app does not have yet ([Tokens plan](2026-11-03-reins-tokens.md) T1 to T8 are open). Ship 0.1.0 without Tokens and drop the section from `site/components/landing/content.ts`, or finish T1 to T8 first.

### First release

- [ ] L10 Dry run on this Mac: `scripts/release.sh --notarize`, mount the DMG, drag to Applications, launch (Gatekeeper opens it with no override), open all tabs, Reins > Check for Updates… says it is up to date against the not-yet-existing feed (an error is expected until L11; record the exact message).
- [ ] L11 Publish `v0.1.0` with the printed commands; download from the release page on a second Mac or a fresh user account, open, confirm the consent prompt text from L2 appears for a project under Documents.
- [ ] L12 Second release `0.1.1` (build 2) the next day: the installed 0.1.0 must show the update toast within a day or on Check for Updates…, install after the click and relaunch. This is AC7 on the public feed; `scripts/test-update.sh` proves it only on 127.0.0.1.
- [ ] L13 When the owner approves the domain: Vercel project on `site/`, CNAME `reins.spacevibe.dev`, the hub's Reins card switched from "coming soon" (that is a `spacevibe-hub` session).

## Verification observed (2026-11-03)

- `scripts/build-app.sh` (development): builds, `minos 15.0`, Developer ID without timestamp, `AppIcon.icns` (123 KB) in `Contents/Resources`, bundle verifies.
- `scripts/build-app.sh --distribution` with the GitHub feed URL: `SUFeedURL` present, `codesign -dvv` shows the Developer ID authority chain and `Timestamp=3 Nov 2026 at 16:38:39`, bundle verifies.
- `scripts/test.sh --filter UpdateController`: 9 tests in 2 suites passed (the committed-plist test still holds: no feed, no automatic install).
- `scripts/release.sh --prepare` from a clean clone of this revision: fresh build from `git archive`, `Reins-0.1.0.dmg` 3.2 MB UDZO, signed and verified, `SHA256SUMS`, `revision.txt`, status "NOT NOTARIZED". With tag `v0.1.0` present the script stopped before building ("Tag v0.1.0 already exists"); with 0.1.1 at build 1 it stopped with "CFBundleVersion 1 is not above 1 (v0.1.0)".
- `--notarize`, stapling, `spctl` and the appcast are not verified: no notarytool profile exists on this Mac (L6).
- The icon was rendered and looked at by the agent only; owner eye approval is open.

## Handoff

- Checkout: `main`, shared with another session whose Swift refactors are uncommitted; only the launch files are committed by this plan. The Electron files stay until SwiftUI plan S8.3.
- Nothing has been pushed, tagged or published. No notarization has run (L6 is open).
- Next: the owner's answers on the decisions above, then L6 to L9, then L10 to L12 in order.

`/goal` Reins 0.1.0 is downloadable from the public GitHub release, notarized and stapled, opens on a second Mac without a Gatekeeper override, shows the Reins icon, and an installed copy updates to 0.1.1 from the published appcast after one click; every step is recorded in docs/plans/2026-11-03-reins-launch.md with its evidence.
