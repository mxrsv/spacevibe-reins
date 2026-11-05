import { AppWindow } from "../app-window";
import { SHOTS } from "../shots";
import { BANDS } from "./copy";

/** Width that makes a full 16:10 window and the question fit one viewport; a cropped window is wider and shorter. */
const FULL_WIDTH = "w-[min(100%,calc((100dvh_-_330px)_*_1.6))] min-w-[min(100%,640px)]";
const CROPPED_WIDTH = "w-full";

/**
 * Direction "Deck": each screen is one band the height of the viewport, with the question over the
 * window. On wide screens the bands are sticky and opaque, so the next screen slides up over the one
 * before it like a stack of windows; on phones they are an ordinary column. The window is sized by
 * the viewport height so the question and the whole screen are in view together.
 */
export function Deck() {
  return (
    <div>
      {BANDS.map((band) => (
        <section
          key={band.id}
          id={band.id}
          className="border-t border-edge bg-bg shadow-lift md:sticky md:top-[60px] md:min-h-[calc(100dvh-60px)]"
        >
          <div className="shell grid content-start gap-8 py-10 md:py-8">
            <header className="grid items-end gap-x-16 gap-y-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,440px)]">
              <h2 className="text-h2 font-medium">{band.question}</h2>
              <p className="text-body text-ink-1">{band.answer}</p>
            </header>
            <AppWindow
              shot={band.shot}
              lights
              caption={band.caption}
              className={`mx-auto ${"crop" in SHOTS[band.shot] ? CROPPED_WIDTH : FULL_WIDTH}`}
            />
          </div>
        </section>
      ))}
    </div>
  );
}
