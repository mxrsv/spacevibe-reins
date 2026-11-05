import { Check } from "lucide-react";

import { AppWindow } from "../app-window";
import { BANDS, MANUAL } from "./copy";

/**
 * Direction "Manual": a reference page for a tool you keep open beside the editor. A sticky rail of
 * the four screens on the left; each chapter is the same four beats: the question, the real screen,
 * what Reins does there, and the one thing it cannot see, drawn dashed like an unmeasurable cell in
 * the app. No terminal chrome and no monospace: the reading order is the costume.
 */
export function Manual() {
  return (
    <div className="shell grid gap-x-16 lg:grid-cols-[180px_minmax(0,1fr)]">
      <aside className="hidden lg:block">
        <nav aria-label="Screens" className="sticky top-24 grid gap-1 py-24">
          {BANDS.map((band) => (
            <a
              key={band.id}
              href={`#${band.id}`}
              className="rounded-ctl px-3 py-2 text-sec text-ink-1 no-underline transition-colors duration-150 hover:bg-s2 hover:text-ink-0"
            >
              {band.label}
            </a>
          ))}
        </nav>
      </aside>

      <div className="grid gap-24 py-24 max-md:gap-16 max-md:py-16">
        {BANDS.map((band) => (
          <section key={band.id} id={band.id} className="grid gap-8" data-reveal>
            <header className="grid max-w-[640px] gap-4">
              <h2 className="text-h2 font-medium">{band.question}</h2>
              <p className="text-body text-ink-1">{band.answer}</p>
            </header>

            <AppWindow shot={band.shot} lights caption={band.caption} />

            <div className="grid gap-6 md:grid-cols-2">
              <div className="grid content-start gap-3">
                <h3 className="text-sec font-medium text-ink-0">What Reins does here</h3>
                <ul className="grid gap-2.5">
                  {MANUAL[band.id].does.map((line) => (
                    <li key={line} className="flex items-start gap-2.5 text-sec text-ink-1">
                      <Check size={14} aria-hidden="true" className="mt-[3px] shrink-0 text-ink-2" />
                      {line}
                    </li>
                  ))}
                </ul>
              </div>
              <div className="grid content-start gap-2 rounded-card border border-dashed border-edge-strong p-5">
                <h3 className="text-sec font-medium text-ink-0">What it cannot see</h3>
                <p className="text-sec text-ink-1">{MANUAL[band.id].cannot}</p>
              </div>
            </div>
          </section>
        ))}
      </div>
    </div>
  );
}
