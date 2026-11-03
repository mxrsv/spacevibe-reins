import type { NextConfig } from "next";

/**
 * Static site: `next build` writes `out/`, which any static host can serve at
 * `reins.spacevibe.dev`. No server, no image optimizer, no data fetching — the page
 * is product copy plus a CSS/SVG scene, and `public/landing/*` is served as-is.
 */
const nextConfig: NextConfig = {
  output: "export",
  images: { unoptimized: true },
  turbopack: {
    // The repo sits under a home folder that has a stray pnpm-workspace.yaml; pin the root here.
    root: process.cwd(),
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
