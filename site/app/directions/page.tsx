import type { Metadata } from "next";
import Link from "next/link";

import { DIRECTIONS } from "@/components/landing/directions/copy";

export const metadata: Metadata = { title: "Landing directions · Reins", robots: { index: false } };

/** Review scaffolding for the mock round (ledger L10): pick one. Deleted with the two that lose. */
export default function DirectionsIndexPage() {
  return (
    <main id="main" className="shell grid min-h-dvh content-center gap-10 py-20">
      <h1 className="max-w-[640px] text-h2 font-medium text-ink-0">Three directions for the Reins landing page</h1>
      <ul className="grid gap-3 md:grid-cols-3">
        {DIRECTIONS.map((direction) => (
          <li key={direction.key}>
            <Link
              href={direction.href}
              className="grid h-full content-start gap-2 rounded-card bg-s2 p-6 no-underline transition-colors duration-150 hover:bg-s3"
            >
              <span className="text-[17px] font-medium text-ink-0">{direction.label}</span>
              <span className="text-sec text-ink-1">{direction.line}</span>
            </Link>
          </li>
        ))}
      </ul>
      <Link href="/" className="w-fit text-sec text-ink-2 no-underline hover:text-ink-0">
        Current page
      </Link>
    </main>
  );
}
