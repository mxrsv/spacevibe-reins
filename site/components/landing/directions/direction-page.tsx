import Link from "next/link";
import type { ReactNode } from "react";

import { DownloadBand } from "../download-band";
import { PrivateSection } from "../private-section";
import { LANDING_ROOT_ID, ScrollReveal } from "../scroll-reveal";
import { SiteFooter } from "../site-footer";
import { SiteHeader } from "../site-header";
import { DIRECTIONS, DIRECTION_NAV, type DirectionKey } from "./copy";
import { HeroRise } from "./hero-rise";
import { Upcoming } from "./upcoming";

/** Everything the three directions share, in the order of ledger L13; the middle bands are the direction's own. */
export function DirectionPage({ current, children }: { readonly current: DirectionKey; readonly children: ReactNode }) {
  return (
    <div id={LANDING_ROOT_ID} className="min-h-dvh bg-bg">
      <SiteHeader nav={DIRECTION_NAV} />
      <main id="main">
        <HeroRise />
        {children}
        <Upcoming />
        <PrivateSection />
        <DownloadBand />
      </main>
      <SiteFooter nav={DIRECTION_NAV} />
      <DirectionSwitcher current={current} />
      <ScrollReveal />
    </div>
  );
}

/** Review scaffolding for the mock round: jump between the directions and the current page. Deleted when one is picked. */
function DirectionSwitcher({ current }: { readonly current: DirectionKey }) {
  return (
    <nav
      aria-label="Landing directions"
      className="fixed right-[max(1rem,env(safe-area-inset-right))] bottom-[max(1rem,env(safe-area-inset-bottom))] z-30 flex items-center gap-1 rounded-full border border-edge-strong bg-glass p-1 shadow-glass backdrop-blur-[14px]"
    >
      {DIRECTIONS.map((direction) => (
        <Link
          key={direction.key}
          href={direction.href}
          aria-current={direction.key === current ? "page" : undefined}
          className={`rounded-full px-3 py-1.5 text-tiny font-medium no-underline transition-colors duration-150 ${
            direction.key === current ? "bg-ink-0 text-bg" : "text-ink-1 hover:text-ink-0"
          }`}
        >
          {direction.label}
        </Link>
      ))}
      <Link href="/" className="rounded-full px-3 py-1.5 text-tiny font-medium text-ink-2 no-underline transition-colors duration-150 hover:text-ink-0">
        Current page
      </Link>
    </nav>
  );
}
