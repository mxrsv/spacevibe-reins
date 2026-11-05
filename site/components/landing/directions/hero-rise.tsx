import type { CSSProperties } from "react";

import { AppWindow } from "../app-window";
import { ButtonLink } from "../button-link";
import { Scene } from "../scene";
import { HERO_NEXT } from "./copy";

/**
 * The first viewport the three directions share: the question as the heading, one line on how it is
 * answered, the download, and the real Loadout rising from the section's bottom edge over the planet
 * limb. The window is cut by the section, so the rows with the bars and the zeros are what shows first.
 */
export function HeroRise() {
  return (
    <section id="top" className="relative isolate overflow-clip bg-void pt-28 max-md:pt-20">
      <Scene variant="hero" />

      <div className="shell grid gap-12 max-md:gap-8">
        <div className="flex max-w-[860px] flex-col items-start">
          <h1
            className="grid text-h1 font-semibold text-ink-0"
            aria-label={HERO_NEXT.headingLines.join(" ")}
            data-rise
            style={{ "--rise": "80ms" } as CSSProperties}
          >
            {HERO_NEXT.headingLines.map((line) => (
              <span key={line} aria-hidden="true">
                {line}
              </span>
            ))}
          </h1>

          <p className="mt-6 max-w-[520px] text-body text-ink-1" data-rise style={{ "--rise": "180ms" } as CSSProperties}>
            {HERO_NEXT.lede}
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-x-5 gap-y-3" data-rise style={{ "--rise": "280ms" } as CSSProperties}>
            <ButtonLink href={HERO_NEXT.cta.href} size="md" external>
              {HERO_NEXT.cta.label}
            </ButtonLink>
            <span className="text-sec text-ink-2">{HERO_NEXT.cta.note}</span>
          </div>
        </div>

        <div
          className="mx-auto max-h-[430px] w-full max-w-[1120px] overflow-hidden max-md:max-h-[250px]"
          data-rise
          style={{ "--rise": "380ms" } as CSSProperties}
        >
          <AppWindow shot="loadout" lights priority bleed />
        </div>
      </div>
    </section>
  );
}
