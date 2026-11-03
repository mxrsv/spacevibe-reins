import { Starfield, type SceneVariant } from "./starfield";

/**
 * Planet limb, ported from the Academy landing. One circle with a very large
 * radius and its centre off-frame to the lower right, so the visible part is the
 * upper-left flank of a sphere: the arc enters from the top right and meets the
 * hero's bottom edge near the middle. Numbers were fitted by eye on 1440×900 in
 * the Academy rounds (2026-08-27) and are kept as-is.
 *
 * All gradients are `userSpaceOnUse`: `objectBoundingBox` would take the circle's
 * box, which is twice the frame and mostly off-screen, and the visible arc would
 * land on the gradient's edge and vanish.
 *
 * Decoration only: `aria-hidden`.
 */
const PLANET = { cx: 1008, cy: 545, r: 380 } as const;
const AMBIENT_SPREAD = 130;
const AMBIENT_LIMB = PLANET.r / (PLANET.r + AMBIENT_SPREAD);
const ARC_HEAD = { x: 1008, y: 165 } as const;
const ARC_FOOT = { x: 647, y: 665 } as const;

export function Scene({ variant }: { readonly variant: SceneVariant }) {
  const id = (name: string) => `${name}-${variant}`;
  const axis = { x1: ARC_FOOT.x, y1: ARC_FOOT.y, x2: ARC_HEAD.x, y2: ARC_HEAD.y };

  return (
    <div className="scene" data-variant={variant} aria-hidden="true">
      <picture className="scene__sky">
        <source media="(max-width: 720px)" type="image/avif" srcSet="/landing/scene-deep-space-mobile.avif" />
        <source media="(max-width: 720px)" type="image/webp" srcSet="/landing/scene-deep-space-mobile.webp" />
        <source type="image/avif" srcSet="/landing/scene-deep-space.avif" />
        <img
          src="/landing/scene-deep-space.webp"
          alt=""
          width={2560}
          height={1440}
          decoding="async"
          fetchPriority={variant === "hero" ? "high" : "low"}
          loading={variant === "hero" ? "eager" : "lazy"}
        />
      </picture>

      <Starfield variant={variant} />

      <svg className="scene__rim" viewBox="0 0 1200 700" preserveAspectRatio="xMidYMax slice">
        <defs>
          {/* Mask: the glow dies at both ends of the arc, peaks mid-axis. */}
          <linearGradient id={id("arc-fade")} gradientUnits="userSpaceOnUse" {...axis}>
            <stop offset="0" stopColor="var(--scene-arc-fade-0)" />
            <stop offset="0.1" stopColor="var(--scene-arc-fade-10)" />
            <stop offset="0.24" stopColor="var(--scene-arc-fade-24)" />
            <stop offset="0.4" stopColor="var(--scene-arc-fade-40)" />
            <stop offset="0.5" stopColor="var(--scene-arc-fade-50)" />
            <stop offset="0.62" stopColor="var(--scene-arc-fade-62)" />
            <stop offset="0.74" stopColor="var(--scene-arc-fade-74)" />
            <stop offset="0.86" stopColor="var(--scene-arc-fade-86)" />
            <stop offset="1" stopColor="var(--scene-arc-fade-0)" />
          </linearGradient>
          <mask id={id("arc-mask")} maskUnits="userSpaceOnUse">
            <rect x="-2000" y="-2000" width="6000" height="6000" fill={`url(#${id("arc-fade")})`} />
          </mask>

          {/* Atmosphere: saturated blue only right at the limb, cold grey a few
              tens of pixels out, gone after that. Steep on purpose. */}
          <radialGradient
            id={id("rim-ambient")}
            gradientUnits="userSpaceOnUse"
            cx={PLANET.cx}
            cy={PLANET.cy}
            r={PLANET.r + AMBIENT_SPREAD}
          >
            <stop offset={AMBIENT_LIMB - 0.13} stopColor="var(--scene-rim-accent)" stopOpacity="0" />
            <stop offset={AMBIENT_LIMB} stopColor="var(--scene-rim-bright)" stopOpacity="0.95" />
            <stop offset={AMBIENT_LIMB + 0.013} stopColor="var(--scene-rim-bright)" stopOpacity="0.82" />
            <stop offset={AMBIENT_LIMB + 0.026} stopColor="var(--scene-rim-bright)" stopOpacity="0.62" />
            <stop offset={AMBIENT_LIMB + 0.052} stopColor="var(--scene-rim-bright)" stopOpacity="0.42" />
            <stop offset={AMBIENT_LIMB + 0.105} stopColor="var(--scene-rim-haze)" stopOpacity="0.27" />
            <stop offset={AMBIENT_LIMB + 0.196} stopColor="var(--scene-rim-haze)" stopOpacity="0.14" />
            <stop offset="1" stopColor="var(--scene-rim-haze)" stopOpacity="0" />
          </radialGradient>

          {/* Brightest mid-arc, fading toward both ends. */}
          <linearGradient id={id("rim-core")} gradientUnits="userSpaceOnUse" {...axis}>
            <stop offset="0" stopColor="var(--scene-rim-accent)" stopOpacity="0.03" />
            <stop offset="0.12" stopColor="var(--scene-rim-core)" stopOpacity="0.14" />
            <stop offset="0.24" stopColor="var(--scene-rim-core)" stopOpacity="0.36" />
            <stop offset="0.35" stopColor="var(--scene-rim-core)" stopOpacity="0.72" />
            <stop offset="0.46" stopColor="var(--scene-rim-core)" stopOpacity="1" />
            <stop offset="0.55" stopColor="var(--scene-rim-core)" stopOpacity="0.95" />
            <stop offset="0.64" stopColor="var(--scene-rim-core)" stopOpacity="0.7" />
            <stop offset="0.72" stopColor="var(--scene-rim-core)" stopOpacity="0.34" />
            <stop offset="0.82" stopColor="var(--scene-rim-core)" stopOpacity="0.12" />
            <stop offset="1" stopColor="var(--scene-rim-core)" stopOpacity="0.02" />
          </linearGradient>
          <linearGradient id={id("rim-halo")} gradientUnits="userSpaceOnUse" {...axis}>
            <stop offset="0" stopColor="var(--scene-rim-bright)" stopOpacity="0.04" />
            <stop offset="0.24" stopColor="var(--scene-rim-bright)" stopOpacity="0.16" />
            <stop offset="0.46" stopColor="var(--scene-rim-bright)" stopOpacity="0.85" />
            <stop offset="0.58" stopColor="var(--scene-rim-bright)" stopOpacity="0.74" />
            <stop offset="0.72" stopColor="var(--scene-rim-bright)" stopOpacity="0.14" />
            <stop offset="1" stopColor="var(--scene-rim-bright)" stopOpacity="0.05" />
          </linearGradient>
          {/* The stroke swells where the light pools: a wider stroke that is only
              lit mid-axis, since SVG cannot vary stroke width along a gradient. */}
          <linearGradient id={id("rim-bloom")} gradientUnits="userSpaceOnUse" {...axis}>
            <stop offset="0.08" stopColor="var(--scene-rim-core)" stopOpacity="0" />
            <stop offset="0.2" stopColor="var(--scene-rim-core)" stopOpacity="0.34" />
            <stop offset="0.32" stopColor="var(--scene-rim-core)" stopOpacity="0.54" />
            <stop offset="0.44" stopColor="var(--scene-rim-core)" stopOpacity="0.62" />
            <stop offset="0.56" stopColor="var(--scene-rim-core)" stopOpacity="0.52" />
            <stop offset="0.68" stopColor="var(--scene-rim-core)" stopOpacity="0.22" />
            <stop offset="0.78" stopColor="var(--scene-rim-core)" stopOpacity="0" />
          </linearGradient>
          {/* Light scattered on the surface, inside the limb, so it reads as a lit
              sphere rather than a bright line on black. */}
          <radialGradient id={id("rim-surface")} gradientUnits="userSpaceOnUse" cx={PLANET.cx} cy={PLANET.cy} r={PLANET.r}>
            <stop offset="0.42" stopColor="var(--scene-rim-bright)" stopOpacity="0" />
            <stop offset="0.68" stopColor="var(--scene-rim-bright)" stopOpacity="0.06" />
            <stop offset="0.86" stopColor="var(--scene-rim-bright)" stopOpacity="0.17" />
            <stop offset="0.96" stopColor="var(--scene-rim-bright)" stopOpacity="0.3" />
            <stop offset="1" stopColor="var(--scene-rim-core)" stopOpacity="0.4" />
          </radialGradient>
          <radialGradient id={id("rim-body")} gradientUnits="userSpaceOnUse" cx={PLANET.cx} cy={PLANET.cy} r={PLANET.r}>
            <stop offset="0" stopColor="var(--scene-planet)" />
            <stop offset="0.84" stopColor="var(--scene-planet)" />
            <stop offset="1" stopColor="var(--scene-planet-limb)" />
          </radialGradient>
        </defs>

        <circle
          className="scene__ambient"
          cx={PLANET.cx}
          cy={PLANET.cy}
          r={PLANET.r + AMBIENT_SPREAD}
          fill={`url(#${id("rim-ambient")})`}
          mask={`url(#${id("arc-mask")})`}
        />
        <circle
          className="scene__halo"
          cx={PLANET.cx}
          cy={PLANET.cy}
          r={PLANET.r}
          fill="none"
          stroke={`url(#${id("rim-halo")})`}
          strokeWidth="5"
          mask={`url(#${id("arc-mask")})`}
        />
        {/* The dark body hides the inner half of the halo: the arc is an EDGE. */}
        <circle className="scene__body" cx={PLANET.cx} cy={PLANET.cy} r={PLANET.r - 2} fill={`url(#${id("rim-body")})`} />
        <circle
          className="scene__surface"
          cx={PLANET.cx}
          cy={PLANET.cy}
          r={PLANET.r - 1}
          fill={`url(#${id("rim-surface")})`}
          mask={`url(#${id("arc-mask")})`}
        />
        <circle
          className="scene__spill"
          cx={PLANET.cx}
          cy={PLANET.cy}
          r={PLANET.r - 9}
          fill="none"
          stroke={`url(#${id("rim-core")})`}
          strokeWidth="7"
        />
        <circle
          className="scene__bloom"
          cx={PLANET.cx}
          cy={PLANET.cy}
          r={PLANET.r}
          fill="none"
          stroke={`url(#${id("rim-bloom")})`}
          strokeWidth="8"
        />
        {/* Sharp core, drawn last so the blurred spill cannot wash over it. */}
        <circle
          className="scene__core"
          cx={PLANET.cx}
          cy={PLANET.cy}
          r={PLANET.r}
          fill="none"
          stroke={`url(#${id("rim-core")})`}
          strokeWidth="1.2"
        />
      </svg>

      <span className="scene__atmosphere" />
      <span className="scene__veil" />
    </div>
  );
}
