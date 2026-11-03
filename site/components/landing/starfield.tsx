import type { CSSProperties } from "react";

/**
 * Layer 1.5 of the scene: three seamless star tiles drifting at three speeds, so
 * depth comes from parallax, not blur. Zero JS: three repeating backgrounds and a
 * linear `transform` on the compositor.
 *
 * The star system and the named glints exist only in the hero; the download band
 * repeats the scene at lower intensity and keeps just the three layers.
 */
const GLINTS = [
  { x: "46%", y: "12%", size: 3, delay: "0s", duration: "7s" },
  { x: "73%", y: "15%", size: 2.2, delay: "2.4s", duration: "9s" },
  { x: "52%", y: "46%", size: 2.6, delay: "4.1s", duration: "8s" },
  { x: "39%", y: "72%", size: 2, delay: "1.3s", duration: "11s" },
] as const;

export type SceneVariant = "hero" | "download";

interface GlintStyle extends CSSProperties {
  readonly "--glint-x": string;
  readonly "--glint-y": string;
  readonly "--glint-size": string;
  readonly "--glint-delay": string;
  readonly "--glint-duration": string;
}

function glintStyle(glint: (typeof GLINTS)[number]): GlintStyle {
  return {
    "--glint-x": glint.x,
    "--glint-y": glint.y,
    "--glint-size": `${glint.size}px`,
    "--glint-delay": glint.delay,
    "--glint-duration": glint.duration,
  };
}

export function Starfield({ variant }: { readonly variant: SceneVariant }) {
  return (
    <div className="scene__stars">
      <span className="scene__layer scene__layer--far" />
      <span className="scene__layer scene__layer--mid" />
      <span className="scene__layer scene__layer--near" />

      {variant === "hero" ? (
        <>
          <span className="scene__system">
            <span className="scene__system-wash" />
            <span className="scene__orbit">
              <span className="scene__orbit-spin">
                <span className="scene__orbit-body" />
              </span>
            </span>
            <span className="scene__glint scene__glint--anchor" />
          </span>

          {GLINTS.map((glint) => (
            <span className="scene__glint" key={`${glint.x}-${glint.y}`} style={glintStyle(glint)} />
          ))}
        </>
      ) : null}
    </div>
  );
}
