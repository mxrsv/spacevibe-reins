import type { ReactNode } from "react";

interface FeatureSectionProps {
  readonly id: string;
  readonly heading: string;
  readonly body: string;
  /** Head on the right, visual on the left. Alternates down the page. */
  readonly reverse?: boolean;
  readonly children: ReactNode;
}

/**
 * One band per tab: a sticky head column (heading + one paragraph) and a visual
 * that takes the form the tab's question needs. The head side alternates so the
 * four bands read as a rhythm, not a list.
 */
export function FeatureSection({ id, heading, body, reverse = false, children }: FeatureSectionProps) {
  return (
    <section id={id} className="border-t border-edge py-[clamp(64px,6.7vw,96px)]">
      <div
        className={`shell grid items-start gap-12 lg:gap-16 ${
          reverse ? "lg:grid-cols-[minmax(0,1fr)_minmax(0,320px)]" : "lg:grid-cols-[minmax(0,320px)_minmax(0,1fr)]"
        }`}
      >
        <div className={`grid gap-4 lg:sticky lg:top-24 ${reverse ? "lg:order-2" : ""}`}>
          <h2 className="text-h2 font-medium" data-reveal>
            {heading}
          </h2>
          <p className="text-body text-ink-1" data-reveal>
            {body}
          </p>
        </div>
        <div className={`min-w-0 ${reverse ? "lg:order-1" : ""}`} data-reveal>
          {children}
        </div>
      </div>
    </section>
  );
}

/** The frame every tab visual sits in: a raised panel with a tools row on top. */
export function Panel({ tools, children }: { readonly tools?: ReactNode; readonly children: ReactNode }) {
  return (
    <div className="overflow-hidden rounded-panel border border-edge bg-s1 shadow-panel">
      {tools ? <div className="flex flex-wrap items-center gap-2 border-b border-edge bg-s2 px-4 py-3">{tools}</div> : null}
      {children}
    </div>
  );
}

/** A filter or scope chip as the app draws it; `active` is the selected one. */
export function Chip({ children, active = false, dismissible = false }: { readonly children: ReactNode; readonly active?: boolean; readonly dismissible?: boolean }) {
  return (
    <span
      className={`inline-flex h-7 items-center gap-1.5 rounded-full border px-3 text-tiny font-medium ${
        active ? "border-transparent bg-ink-0 text-bg" : "border-edge-strong text-ink-1"
      }`}
    >
      {children}
      {dismissible ? <span aria-hidden="true" className="text-ink-2">×</span> : null}
    </span>
  );
}

/** Segmented control, static. */
export function Segmented({ options, active }: { readonly options: readonly string[]; readonly active: string }) {
  return (
    <span className="inline-flex h-7 items-center rounded-ctl border border-edge bg-s1 p-0.5">
      {options.map((option) => (
        <span
          key={option}
          className={`inline-flex h-full items-center rounded-[6px] px-2.5 text-tiny font-medium ${
            option === active ? "bg-s3 text-ink-0" : "text-ink-2"
          }`}
        >
          {option}
        </span>
      ))}
    </span>
  );
}
