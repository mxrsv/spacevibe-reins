import Image from "next/image";

import { SHOTS, type Shot, type ShotKey } from "./shots";

/** macOS window buttons at the app's own place, as fractions of the window width (a 1440 pt window). */
const LIGHTS = [
  "left-[1.67cqw] bg-light-close",
  "left-[3.06cqw] bg-light-min",
  "left-[4.44cqw] bg-light-zoom",
] as const;

interface AppWindowProps {
  readonly shot: ShotKey;
  /** Draw the window buttons the headless capture leaves out. Off for previews: their mocks draw their own. */
  readonly lights?: boolean;
  /** A page that is not in the download: dashed outline, and the caption says so. */
  readonly preview?: boolean;
  readonly caption?: string;
  readonly priority?: boolean;
  /** The section cuts the window's bottom edge: no bottom corners and no bottom border. */
  readonly bleed?: boolean;
  readonly className?: string;
}

/**
 * One app screen in a window frame. The frame is only an edge and a shadow: the pixels are the app's.
 * The caption sits under the frame so it never covers the screen.
 */
export function AppWindow({ shot, lights = false, preview = false, caption, priority = false, bleed = false, className = "" }: AppWindowProps) {
  const spec: Shot = SHOTS[shot];
  const cropped = spec.crop === "wide";
  return (
    <figure className={`grid gap-3 ${className}`}>
      <div
        className={`@container relative overflow-hidden rounded-panel bg-s2 ${
          preview ? "border border-dashed border-edge-hover" : "border border-edge-strong shadow-panel"
        } ${bleed || cropped ? "rounded-b-none border-b-0" : ""} ${cropped ? "aspect-[2.6]" : ""}`}
      >
        <Image
          src={spec.src}
          alt={spec.alt}
          width={spec.width}
          height={spec.height}
          priority={priority}
          sizes="(min-width: 1280px) 1120px, 100vw"
          className={cropped ? "block size-full object-cover object-top" : "block h-auto w-full"}
        />
        {lights
          ? LIGHTS.map((place) => (
              <span key={place} aria-hidden="true" className={`absolute top-[1.04cqw] size-[0.84cqw] rounded-full ${place}`} />
            ))
          : null}
      </div>
      {caption ? <figcaption className="text-tiny text-ink-2">{caption}</figcaption> : null}
    </figure>
  );
}
