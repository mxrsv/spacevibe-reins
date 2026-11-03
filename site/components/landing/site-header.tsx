import { ButtonLink } from "./button-link";
import { HEADER, NAV, SITE } from "./content";
import { ReinsMark } from "./reins-mark";

/**
 * A thin 60px band across the full width, split from the page by a hairline.
 * Sticky, does not grow or recolour on scroll. The four anchors are the four tabs.
 */
export function SiteHeader() {
  return (
    <header className="sticky top-0 z-20 border-b border-edge bg-[rgb(13_15_18/78%)] backdrop-blur-[16px]">
      <div className="shell grid h-[60px] grid-cols-[auto_auto] items-center justify-between gap-8 md:grid-cols-[auto_1fr_auto]">
        <a href="#top" className="inline-flex items-center gap-2.5 text-sec font-medium tracking-[-0.01em] text-ink-0 no-underline" aria-label={SITE.brand}>
          <ReinsMark className="size-[22px] shrink-0" />
          <span aria-hidden="true">{SITE.brand}</span>
        </a>

        <nav className="hidden md:flex justify-center gap-8" aria-label="Sections">
          {NAV.map((link) => (
            <a key={link.href} href={link.href} className="text-sec text-ink-1 no-underline transition-colors duration-150 hover:text-ink-0">
              {link.label}
            </a>
          ))}
        </nav>

        <div className="flex items-center gap-2">
          <span className="hidden sm:contents">
            <ButtonLink href={HEADER.github.href} variant="ghost" external>
              {HEADER.github.label}
            </ButtonLink>
          </span>
          <ButtonLink href={HEADER.cta.href} external>
            {HEADER.cta.label}
          </ButtonLink>
        </div>
      </div>
    </header>
  );
}
