import Image from "next/image";
import type { CSSProperties } from "react";

import { SHOTS, type ShotKey } from "./shots";

/** macOS window buttons at the app's own place, as fractions of the window width (a 1440 pt window). */
const LIGHTS = [
  "left-[1.67cqw] bg-light-close",
  "left-[3.06cqw] bg-light-min",
  "left-[4.44cqw] bg-light-zoom",
] as const;

interface AppWindowProps {
  readonly shot: ShotKey;
  /** Draw the window buttons the headless capture leaves out. Only for a whole window. */
  readonly lights?: boolean;
  /** A page that is not in the download: dashed outline, and the caption says so. */
  readonly preview?: boolean;
  /** The sidebar tab the screen lives behind, shown beside the caption so the category is recognised in the app. */
  readonly tab?: ShotKey;
  readonly caption?: string;
  readonly priority?: boolean;
  /** The section cuts the window's bottom edge: no bottom corners and no bottom border. */
  readonly bleed?: boolean;
  readonly className?: string;
  /** Only for a value that depends on data, such as a max width derived from the image's shape. */
  readonly style?: CSSProperties;
}

/**
 * One app screen, or one region of it, in a frame. The frame is only an edge and a shadow: the pixels
 * are the app's. The caption sits under the frame so it never covers the screen.
 */
export function AppWindow({ shot, lights = false, preview = false, tab, caption, priority = false, bleed = false, className = "", style }: AppWindowProps) {
  const { src, width, height, alt } = SHOTS[shot];
  const tabShot = tab ? SHOTS[tab] : null;
  return (
    <figure className={`grid gap-3 ${className}`} style={style}>
      <div
        className={`@container relative overflow-hidden rounded-panel bg-s2 ${
          preview ? "border border-dashed border-edge-hover" : "border border-edge-strong shadow-panel"
        } ${bleed ? "rounded-b-none border-b-0" : ""}`}
      >
        <Image
          src={src}
          alt={alt}
          width={width}
          height={height}
          priority={priority}
          sizes="(min-width: 1280px) 1120px, 100vw"
          className="block h-auto w-full"
        />
        {lights
          ? LIGHTS.map((place) => (
              <span key={place} aria-hidden="true" className={`absolute top-[1.04cqw] size-[0.84cqw] rounded-full ${place}`} />
            ))
          : null}
      </div>
      {caption || tabShot ? (
        <figcaption className="flex items-center gap-3 text-tiny text-ink-2">
          {tabShot ? (
            <Image src={tabShot.src} alt={tabShot.alt} width={tabShot.width} height={tabShot.height} className="h-7 w-auto shrink-0" />
          ) : null}
          {caption}
        </figcaption>
      ) : null}
    </figure>
  );
}
