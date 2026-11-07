# Standalone Go core and SpaceVibe identity, decision ledger

Source: grilling session 2026-11-07. Owner's words are quoted (Vietnamese originals kept where the wording matters; "approve đủ" means the owner accepted every recommended answer in the round).
Every later artifact (spec, plan, build prompt, subagent brief) cites these IDs (W20). Status: all rounds settled 2026-11-07 except the items under "Open", which are not assumed.

## Problem

Owner: "gần đây chúng ta gần như chỉ tập trung về build UI, tính năng core chưa có nhiều, tôi cần review nhiều thứ, và có cần thiết làm một CLI core hay engine core không ?"
The 2026-11-02 spec made the engine a Swift library (`ReinsCore`). Owner on that choice: "tôi chọn SwiftUI nó chỉ dành cho UI thôi hiểu không ? có lẽ do hôm đó tôi không nói rõ ràng".

## Decisions

| ID | Decision | Owner's words |
| --- | --- | --- |
| SV1 | The core is a standalone engine in Go. SwiftUI is the macOS UI layer only. Supersedes the spec line "the engine is rewritten in Swift as a library". | "yes chuyển sang Go đi" |
| SV2 | Windows and Linux shells are committed within about 3-6 months, which is the reason for SV1. | "yes chuyển sang Go đi" (answer to the commitment question) |
| SV3 | Shell-to-core protocol: JSON-RPC over stdio, a child process owned by the GUI. The protocol version is sent in `initialize` and a mismatch is refused. Stdout carries protocol only, logs go to stderr, the core exits on stdin EOF, spawn uses an argv array (no shell). No network listener (S-R5). A one-shot `<cli> <command> --json` stays for debugging. | "approve đủ" |
| SV4 | The macOS app calls the core only through the child process, via one `CoreClient` in Swift. `ReinsCore` is no longer linked by the UI. Migration is one screen at a time. | "approve đủ" |
| SV5 | Parity oracle: the existing `Tests/ReinsCoreTests/Fixtures/golden/*.json` are frozen as committed files. The Node generator and Node `core/` are deleted as plan S8.3 intended. The Go core must match the goldens byte for byte. A wrong golden is fixed together with its Swift test in one commit. | "approve đủ" |
| SV6 | The Go core lives in this repository, in a new directory whose name is chosen after reading `~/.claude/templates/project-structure.md`. | "approve đủ" |
| SV7 | Order: the Go port comes before the first macOS publish, so S0.5, S0.4 and S0.3 are verified once, on the Go core. | "approve đủ" |
| SV8 | Pre-publish core review order: real-CLI acceptance (S0.5), then write safety and Stop (S0.4), then TCC (S0.3), then S8.1 and S8.2, then feature gaps against the spec. Output is a severity-ranked read-only report on the core whose findings become tasks in an existing plan. The goal is trust for a macOS release, not cross-platform preparation. | "approve đủ" |
| SV9 | The product is renamed from Reins to SpaceVibe. No visible or identifying reference to Reins remains. | "không còn reins name nữa, spacevibe là một domain xuất sắc dành cho dự án này" and "tôi sẽ chuyển hết sang thành spacevibe.dev không còn liên quan nào đến reins nữa" |
| SV10 | `spacevibe.dev` becomes this product's landing page. `spacevibe-hub` is retired and its content moves to `kyant.dev`. | "lấy luôn domain spacevibe.dev làm landing cho repo này", "không còn dùng hub nữa", "hub đổi sang thành kyant.dev" |
| SV11 | All identifiers are renamed too, including the bundle id, the repo name and the appcast URL. Installed `v0.1.0` copies are not kept updating. | "chọn (b) đổi hết" |
| SV12 | New names: bundle id `dev.spacevibe.app`, CLI `spacevibe`, env prefix `SPACEVIBE_*`, data folder `~/.spacevibe`. The binary name, env prefix and data folder are one constant each. `initialize` returns the core's name and version so a shell never depends on the binary name. | "approve đủ" |
| SV13 | Sparkle gets a new key pair and a new Keychain account for the new bundle id, with a new `SUPublicEDKey`. B8 is rewritten for the new key. | "approve đủ" |
| SV14 | The `v0.1.0` release stays, marked deprecated in its description with a pointer to the new download page. No bridge release (3 downloads at 2026-11-07). Deleting it is not part of this decision. | "approve đủ" |
| SV15 | No data migration from `~/.reins` to `~/.spacevibe`. The owner copies the folder by hand; the release notes say so. | "approve đủ" |
| SV16 | Deploy host is Vercel. Old Hub routes redirect to the same path on `kyant.dev`. The `/live` family (`/live`, `/en/live`, `/vi/live`, `/live/<slug>`) keeps its 308 to `https://active.spacevibe.dev` (U4). Order: build Hub on `kyant.dev`, verify, then repoint `spacevibe.dev`. `reins.spacevibe.dev` did not answer HTTP on 2026-11-07, so it needs no redirect unless DNS for it exists. Every DNS and deploy step needs the owner's approval when it runs. | "approve đủ" |
| SV17 | The other products (Deck, Bench, Academy, Active) keep their own names. "SpaceVibe" names this app. Workspace-level records move to a separate workspace session (X1). | "approve đủ" |

## Open (not assumed)

- Repo name. The recommendation was `mxrsv/spacevibe`, with `spacevibe-app` named as safer because the workspace uses `spacevibe-<product>` and `spacevibe-workspace` exists. The owner has not picked between them.
- Spike (fact, not a decision): Go reads a `.jsonl.zst` rollout, parses TOML and cross-compiles to Windows before any port starts.
- Windows and Linux UI technology (native per OS or a shared web UI). Needed only when the second shell starts.
- Module order of the Go port.
- `ReinsStatusline` becomes a subcommand of the Go core (it uses `posix_spawn` of `/bin/sh`, unavailable on Windows). Not asked yet.
- Whether the core may run `claude --version` and `codex --version` (S-R4 would list them as fixed commands). Not asked since the Go decision.
- Whether new UI work pauses until the core review and the first CLI exist.
- Windows tests run on a real Windows machine, not only compiled in CI (lesson from the magpie repo).
- Fate of the Hub `/vote` route (Postgres and Neon Auth), the marketing strategy and the workspace `AGENTS.md` map. These belong to a workspace session.

## Owner answers at plan execution (2026-11-07)

Owner, after seeing the W20 table and the open decisions with recommendations: "tiếp tục hết tất các phase". Read as: take the plan's recommendation for every open item below. Each is reversible until the gate that publishes it.

| Item | Taken | Note |
| --- | --- | --- |
| D-2 port order | the plan's order | |
| D-7 directory and module | `core/`, `spacevibe.dev/core` | |
| C1/Q1 "byte for byte" | canonical bytes of the named projections, case counts asserted | narrows SV5 as the plan proposes |
| C3/Q2 fixtures | kept as named skipped sites in the rename report | |
| C2/Q8 | after the Swift tests are deleted, "with its Go test" | |
| D-3 statusline | `spacevibe statusline install\|undo\|capture` in the Go core | |
| D-4 `--version` of the CLIs | the core does not run them | |
| D-5 new UI work | UI-only work continues; engine tasks of the Agents and Tokens plans move to Go after G1 | |
| D-6 Windows hardware | yes, X2 needs real hardware | |
| D-1 repo name | working value `mxrsv/spacevibe`, kept in one constant | NOT decided by the owner; GH1 still needs explicit approval and the owner may pick `spacevibe-app` |

Still the owner's alone: every outward-facing gate (GH1, REL1, GH2, WEB1 to WEB3), the Sparkle key creation in R2, the runtime checks A1 to A5, X2, F1.

### Status 2026-11-08

Settled or taken, no further owner input needed (all still reversible until the gate that publishes them):

- D-2 port order: followed; the Go port is built and every golden passes.
- D-7 `core/`, `spacevibe.dev/core`: in use.
- C1/Q1, C2/Q8: in use (canonical bytes with asserted case counts; the Go test owns the golden after the Swift tests were deleted).
- C3/Q2: the frozen fixtures are named skipped sites in the rename report (plan, Verification evidence).
- D-3: `spacevibe statusline install|undo|capture` is built; `ReinsStatusline` is deleted.
- D-4: the core does not run `claude --version` or `codex --version`.
- D-5: UI-only work continued (UI v5 track); re-targeting the engine tasks of the Agents and Tokens plans is for those plans' owners (not checked here).
- Spike item: no longer open; the Go port reads `.jsonl.zst` fixtures, parses TOML and cross-builds (plan, Verification evidence).

Still open:

- D-1 repo name: `mxrsv/spacevibe` is only a working value in one constant (`scripts/release.sh`, `site/components/landing/content.ts`); GH1 needs explicit approval.
- D-6 and X2: Windows hardware run, not done.
- New Sparkle key pair and the account flip (R2), then AC7 and the H7 check.
- Runtime checks A1 to A5, F1 eye approval, and every outward gate (GH1, REL1, GH2, WEB1 to WEB3).
- Windows and Linux UI technology; Hub `/vote`, marketing and the workspace map (workspace session).

## Out of scope for this ledger

Building the Windows or Linux shell, the visual design of the `spacevibe.dev` landing, and any edit outside this repository.

## Traceability still owed (W20)

The spec must map SV1-SV17 to a requirement ID and an acceptance check before it is committed. "Match the goldens byte for byte" (SV5) is the acceptance for the port; "no reference to Reins remains" (SV9, SV11) is a repo-wide search ending in "changed N of M, each skipped site named" (W21), with the fixtures and the `v0.1.0` release text reported separately.
