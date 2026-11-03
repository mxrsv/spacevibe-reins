import { ButtonLink } from "./button-link";
import { DOWNLOAD } from "./content";
import { Scene } from "./scene";

/** The scene returns once, dimmer, cropped to its lower-right corner, behind the one download panel. */
export function DownloadBand() {
  return (
    <section id={DOWNLOAD.id} className="border-t border-edge py-[clamp(64px,6.7vw,96px)]">
      <div className="shell">
        <div className="relative isolate overflow-clip rounded-panel border border-edge bg-s1 px-8 py-16 text-center max-md:px-5 max-md:py-10">
          <Scene variant="download" />
          <span
            aria-hidden="true"
            className="absolute inset-y-0 left-0 right-[58%] -z-10 bg-[radial-gradient(rgb(255_255_255/13%)_1px,transparent_1px)] bg-[size:24px_24px] [mask-image:linear-gradient(90deg,#000,transparent)]"
          />
          <div className="mx-auto grid max-w-[520px] justify-items-center gap-4">
            <h2 className="text-h2 font-medium" data-reveal>
              {DOWNLOAD.heading}
            </h2>
            <p className="max-w-[430px] text-body text-ink-1" data-reveal>
              {DOWNLOAD.body}
            </p>
            <div className="mt-2 flex flex-wrap items-center justify-center gap-2" data-reveal>
              <ButtonLink href={DOWNLOAD.cta.href} size="md" external>
                {DOWNLOAD.cta.label}
              </ButtonLink>
              <ButtonLink href={DOWNLOAD.secondary.href} variant="ghost" size="md" external>
                {DOWNLOAD.secondary.label}
              </ButtonLink>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
