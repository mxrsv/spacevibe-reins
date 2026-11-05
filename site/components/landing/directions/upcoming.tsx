import { AppWindow } from "../app-window";
import { ButtonLink } from "../button-link";
import { UPCOMING } from "./copy";

/**
 * The two pages that are not in the download. Their frames are dashed and captioned as design
 * previews, so a visitor cannot take a mock for a shipped screen (ledger L7, L8). No date, no version.
 */
export function Upcoming() {
  return (
    <section id={UPCOMING.id} className="relative border-t border-edge bg-bg py-[clamp(64px,6.7vw,96px)]">
      <div className="shell grid gap-12">
        <div className="flex flex-wrap items-end justify-between gap-x-10 gap-y-5">
          <h2 className="max-w-[560px] text-h2 font-medium" data-reveal>
            {UPCOMING.heading}
          </h2>
          <div data-reveal>
            <ButtonLink href={UPCOMING.watch.href} variant="ghost" external>
              {UPCOMING.watch.label}
            </ButtonLink>
          </div>
        </div>

        <div className="grid gap-12 md:grid-cols-2 md:gap-8">
          {UPCOMING.items.map((item) => (
            <div key={item.name} className="grid content-start gap-5" data-reveal>
              <AppWindow shot={item.shot} preview caption={UPCOMING.previewCaption} />
              <div className="grid gap-2">
                <h3 className="flex items-center gap-3 text-[17px] font-medium leading-6 tracking-[-0.01em]">
                  {item.name}
                  <span className="rounded-full border border-dashed border-edge-strong px-2.5 py-0.5 text-tiny font-normal text-ink-2">
                    {UPCOMING.label}
                  </span>
                </h3>
                <p className="max-w-[520px] text-sec text-ink-1">{item.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
