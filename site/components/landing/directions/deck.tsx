import { AppWindow } from "../app-window";
import { SHOTS } from "../shots";
import { BANDS } from "./copy";

/**
 * Direction "Deck": each category is one band the height of the viewport, with the question over the
 * region of the app that is only that category. On wide screens the bands are sticky and opaque, so
 * the next one slides up over the one before it like a stack of windows; on phones they are an
 * ordinary column. The figure is as wide as the viewport height allows for its own shape, so the
 * question and the whole figure are in view together.
 */
export function Deck() {
  return (
    <div>
      {BANDS.map((band) => {
        const { width, height } = SHOTS[band.shot];
        return (
          <section
            key={band.id}
            id={band.id}
            className="border-t border-edge bg-bg shadow-lift md:sticky md:top-[60px] md:grid md:min-h-[calc(100dvh-60px)] md:items-center"
          >
            <div className="shell grid content-start gap-8 py-10 md:py-8">
              <header className="grid items-end gap-x-16 gap-y-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,440px)]">
                <h2 className="text-h2 font-medium">{band.question}</h2>
                <p className="text-body text-ink-1">{band.answer}</p>
              </header>
              <AppWindow
                shot={band.shot}
                tab={band.tab}
                caption={band.caption}
                className="mx-auto w-full"
                style={{ maxWidth: `calc((100dvh - 330px) * ${width / height})` }}
              />
            </div>
          </section>
        );
      })}
    </div>
  );
}
