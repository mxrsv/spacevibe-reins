import type { CSSProperties } from "react";

import { ArrowRight } from "lucide-react";

import { HERO } from "./content";
import { HeroLoadout } from "./hero-loadout";
import { Scene } from "./scene";

/**
 * Text column left, Loadout slice right, the planet limb rising between and
 * behind them. No eyebrow: the heading leads. The CTA is a link with an
 * information segment stuck to its button; there is no input in the hero.
 */
export function Hero() {
  return (
    <section id="top" className="relative isolate flex min-h-[640px] items-center overflow-clip bg-void pt-28 pb-24 max-md:min-h-0 max-md:pt-20">
      <Scene variant="hero" />

      <div className="shell flex items-center justify-between gap-16 max-md:flex-col max-md:items-stretch max-md:gap-10">
        <div className="flex min-w-0 flex-col items-start">
          <h1
            className="grid max-w-[640px] text-h1 font-semibold text-ink-0"
            aria-label={HERO.headingLines.join(" ")}
            data-rise
            style={{ "--rise": "80ms" } as CSSProperties}
          >
            {HERO.headingLines.map((line) => (
              <span key={line} aria-hidden="true">
                {line}
              </span>
            ))}
          </h1>

          <p className="mt-6 max-w-[440px] text-body text-ink-1 max-md:max-w-none" data-rise style={{ "--rise": "180ms" } as CSSProperties}>
            {HERO.lede}
          </p>

          <a
            href={HERO.cta.href}
            target="_blank"
            rel="noopener noreferrer"
            className="group mt-7 inline-flex items-stretch overflow-hidden rounded-ctl border border-edge-strong bg-s1 no-underline transition-colors duration-150 hover:border-edge-hover max-md:w-full max-md:justify-between"
            data-rise
            style={{ "--rise": "280ms" } as CSSProperties}
          >
            <span className="flex items-center whitespace-nowrap px-4 text-sec text-ink-1">{HERO.cta.note}</span>
            <span className="flex items-center gap-2 whitespace-nowrap bg-accent px-5 py-3 text-sec font-medium text-white transition-colors duration-150 group-hover:bg-accent-hover">
              {HERO.cta.label}
              <ArrowRight size={14} aria-hidden="true" className="transition-transform duration-150 group-hover:translate-x-0.5" />
            </span>
          </a>
        </div>

        <HeroLoadout />
      </div>
    </section>
  );
}
