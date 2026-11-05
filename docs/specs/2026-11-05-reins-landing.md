# Reins: landing page standardisation

Date: 2026-11-05
Status: draft. Decision ledger only, from the owner's grilling on 2026-11-05; the owner confirmed it the same day ("ok") and asked for the mock directions to be built directly in the `site/` dev server. Requirements, acceptance criteria and the traceability table (W20) are added once the owner has picked a direction.
Parent: [Reins](2026-11-02-reins.md). Earlier record of the first build: [site landing plan](../plans/2026-11-03-reins-site-landing.md).

## Scope

The page in [`site/`](../../site/README.md) was generated once on 2026-11-03 and never polished or reviewed ("chỉ generate 1 lần từ agent chưa polish hay qua các vòng review"). This work makes it fit Reins: its claims match what the download does, and the parts that present the app match the app.

Out of scope: the app itself, DNS and production hosting for `reins.spacevibe.dev`, the hub card, a `LICENSE` and root `README.md` (launch plan L8), building Agents or Tokens.

## Decision ledger

Quotes are the owner's words. "No objection" means the owner was told a recommendation stands unless a question number is named, and named none.

| ID | Decision | Owner's words |
| --- | --- | --- |
| L1 | Goal: standardise the landing page for Reins; the current page is a temporary frame. | "với landing page tôi muốn chuẩn hoá phù hợp dành cho reins" |
| L2 | Look is option C: the planet scene and stars stay behind the hero and the download band; the bands between follow the app's design language (real app screenshots in a window frame, Inter, tonal layers, CTA in the app's accent token). | "giữ hành tinh" then "ok ânậnận" (accepts C) |
| L3 | The page is dark only. | "ok ânậnận" (accepts Q11) |
| L4 | Stack (Next.js static export + Tailwind in `site/`), English only, CTA to GitHub Releases stay. | No objection |
| L5 | The hero leads with evidence (which skills, agents and hooks actually ran); Limits is the secondary beat. | No objection |
| L6 | The page may describe the next version, with "coming soon" marks. | "q4-b" |
| L7 | Shipped features are shown with real screenshots from the fixture home. Features in development are shown with a mock render in a different frame, labelled "Design preview, not in the current download". | "nhận cả 3" |
| L8 | "Coming soon" covers Agents and Tokens only, labelled "In development", no date and no version. Settings is not on the page. | "nhận cả 3" |
| L9 | Interested visitors get a "Watch releases on GitHub" link; no form and no email capture. | "nhận cả 3" |
| L10 | The owner's gates: at least three mock directions, the owner picks one before code; then the owner's eye approval at 1440 and 390 in their own dev server. | "q6-1 và 5" |
| L11 | `impeccable` (build, `distill`, `clarify`) runs unattended. The `frontend-design-bar` screenshot gate and `review-experience` at 375/768/1440 are skipped. | "cổng ảnh frontend-design-bar và review-experience ở 375/768/1440 thì bỏ qua" |
| L12 | Reviews happen on a Vercel preview that is not public; no DNS for `reins.spacevibe.dev` until the owner approves it separately. | No objection |
| L13 | Section order: hero, Loadout, Limits, Activity, Rules, In development (Agents, Tokens), Private by construction, Download. When Agents ships, that release's PR replaces the Rules band. | "ok ânậnận" (accepts Q12) |
| L14 | The download band says "Free"; no licence is named until the owner picks one. The "Source on GitHub" label becomes "GitHub" until a `LICENSE` exists (the label change is derived: "open source" is claimed only with a licence). | "ok ânậnận" (accepts Q13 b) |
| L15 | The page says "macOS 15 or later, Apple silicon". The local build is `arm64`; the published DMG is checked at build time. | Derived from a verified fact, not an owner quote |

Conflict kept visible: L6 lets the page show screens the app does not have yet. The app's own rule is to say plainly what it cannot measure, and the Limits page once drifted from its mock. L7 and L8 are the guard: a visibly different frame and label for anything unshipped, replaced by a real screenshot in the release that ships it.

## Mock round (ledger L10, first gate)

Built 2026-11-05 in `site/`, viewed with `cd site && npx next dev -p 3100` at `http://localhost:3100/directions` (port 3000 is the hub's dev server). The surface structures were dealt by `impeccable concept-seed` (key `4b19c235`, candidates 4, 6, 5 of a seven-item list); the visual world is fixed by L2 and L13, so the directions differ in composition only. The hero is shared by all three; hero variants wait for the owner's pick.

| Route | Direction | Composition |
| --- | --- | --- |
| `/directions/deck` | Deck | Each screen is a viewport-tall sticky band; the next screen slides over it. |
| `/directions/two-clis` | Two CLIs | The real screen, then one block per CLI on what differs between Claude Code and Codex. |
| `/directions/manual` | Manual | Sticky rail of the four screens; each chapter is question, screen, what Reins does, what it cannot see. |

Owner feedback on the first round: the four categories looked alike and the options did not differ. The bands now show one signature crop per category instead of the whole window (Loadout's paired bars, Limits' figure and ruler, Activity's two lanes, Rules' Allow/Ask/Deny pickers) with the sidebar tab the category lives behind beside the caption; only the hero keeps a whole window. Real screens are dark captures of the SwiftUI app on the synthetic fixture home (`site/public/landing/app/`); Agents and Tokens are renders of the tracked mocks and are captioned as design previews (L7). On pick: delete the other two directions, `/directions` and `DirectionSwitcher`, move the copy from `site/components/landing/directions/copy.ts` into `content.ts`, and replace `/`.
