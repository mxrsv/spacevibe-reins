# SpaceVibe site

The public page for `spacevibe.dev`: Next.js 16 (App Router, static export) and Tailwind CSS 4. It has no server, no data fetching and no form; `next build` writes `out/`, which any static host serves as-is.

| Command         | Purpose                                                   |
| --------------- | --------------------------------------------------------- |
| `npm run dev`   | Dev server on `http://localhost:3000`                     |
| `npm run build` | Static export into `out/` (also the typecheck)            |
| `npm run lint`  | ESLint                                                    |
| `node --test tests/redirects.test.mjs` | `vercel.json` redirects: live family, old Hub routes, no shadowing |

Layout: `app/` (layout, page, `globals.css` tokens, `scene.css` planet scene), `components/landing/` (one file per section; `content.ts` holds every word and number), `public/landing/` (the deep-space raster and three star tiles, shared with the Academy landing).

The example rows mirror the app's synthetic fixture home (`../core/testdata/fixtures`), never a real `~/.claude`; every panel that shows them says "demo data".

`vercel.json` holds the redirects (`output: "export"` rules out `next.config` ones): the `/live` family goes to `https://active.spacevibe.dev`, every other old Hub route goes to the same path on `https://kyant.dev`. Hub's own `/` is not redirected; this site serves it.
