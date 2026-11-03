# Reins landing page (`site/`)

Date: 2026-11-03
Status: **checkpoint** — built, verified mechanically, committed; waiting for the owner's eye approval. Not pushed, not deployed.
Requirements: no separate spec. Product truth is [PRODUCT.md](../../PRODUCT.md) and the Identity and Distribution sections of the [Reins spec](../specs/2026-11-02-reins.md); the page claims nothing those two do not say. Scope agreed in conversation on 2026-11-03: one public page for `reins.spacevibe.dev` in the visual world of the SpaceVibe Academy landing (planet limb, star field), with the four tabs as its sections and a download CTA.

## Decisions (owner, 2026-11-03)

- Stack: Next.js static export + Tailwind CSS under `spacevibe-reins/site/`, not a route in `spacevibe-hub`.
- Language: English.
- Primary CTA: "Download for macOS" → `https://github.com/mxrsv/spacevibe-reins/releases/latest`. It turns live with the first published DMG; the page needs no change then.
- Accent: the Academy blue `#3953d2` kept for the planet and CTA; the Reins fuchsia from the hub brand table was offered and declined.
- Not run: the greybox composition round. The owner pointed at a concrete reference (the Academy landing, already eye-approved there), so its composition was carried over. No eyebrow labels and no section numbers (craft floor).

## What exists

| Path | Role |
| --- | --- |
| `site/app/globals.css` | Tailwind `@theme` tokens (graphite ground, one accent, Claude clay / Codex teal), base, reveal and entrance motion |
| `site/app/scene.css` | The planet scene, ported from Academy `home-hero.css` + `home-tokens.css`; hero and download variants; phone crop |
| `site/components/landing/scene.tsx`, `starfield.tsx` | SVG limb (geometry from the Academy 2026-08-27 rounds, unchanged) and three parallax star tiles |
| `site/components/landing/content.ts` | Every word and number; example rows mirror `Tests/ReinsCoreTests/Fixtures/golden` |
| `site/components/landing/hero.tsx`, `hero-loadout.tsx` | Heading column + a Loadout slice on glass (second focal) |
| `site/components/landing/*-visual.tsx` | One panel per tab, each in the form its question needs |
| `site/components/landing/private-section.tsx`, `download-band.tsx` | Four guarantees in one hairline panel; the scene returns once, dimmer |
| `site/public/landing/` | Deep-space raster and three star tiles, copied from the Academy repo |

Commit: `4281317` on `main` (`feat(site): landing page for reins.spacevibe.dev with the planet scene`), together with the `site/` paragraph in the root `AGENTS.md`.

## Verification observed (2026-11-03)

- `cd site && npm run build` → static export, `/` prerendered; `npm run lint` clean; `impeccable detect --json` over the site files → `[]`.
- Screenshots at 1440×900 and 390×844, full page after an instant scroll-through: 17/17 reveal blocks shown, `scrollWidth` equals the viewport at both sizes, zero console errors. Captures live in the gitignored `.playwright-mcp/site/` (synthetic data only).
- Trap for the next reviewer: the page sets `scroll-behavior: smooth`, so a test that scrolls with the default behaviour leaves the last band unrevealed in a full-page capture. Scroll with `behavior: 'instant'` and wait ~800 ms before capturing. A served `python3 -m http.server` dropped parallel requests (chunks and star tiles 404/reset); use `npx serve out -l <port>`.

## Remaining

1. Owner eye approval of the rendered page (desktop and phone). Open with `cd site && npm run dev`, or `npm run build && npx serve out -l 3999`.
2. Push after approval (owner's call).
3. Hosting and DNS for `reins.spacevibe.dev`: per the spec, the domain waits for about 500–1,000 users and needs the owner's approval; nothing is configured.
4. Optional: real app screenshots from the synthetic home (`scripts/dev-fixture.sh --shots <dir>`) as product proof once the Swift app's screens are stable.

/goal The owner has eye-approved the Reins landing page at 1440 and 390 and it is pushed; the page builds statically, lints clean, shows all 17 reveal blocks after an instant scroll-through, and claims only what PRODUCT.md and the spec state.
