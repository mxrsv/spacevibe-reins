import { AppWindow } from "../app-window";
import { CLI_LABEL, type CLI } from "../content";
import { CliDot } from "../usage-cell";
import { BANDS, DIFFS } from "./copy";

const CLIS: readonly CLI[] = ["claude", "codex"];

/**
 * Direction "Two CLIs": the app's one idea is that Claude Code and Codex measure the same thing
 * differently, so every screen carries the real screen and, under it, one line per CLI on what
 * differs. The honesty about what a CLI does not log is the proof, not a footnote.
 */
export function TwoClis() {
  return (
    <div>
      {BANDS.map((band) => (
        <section key={band.id} id={band.id} className="border-t border-edge py-[clamp(64px,6.7vw,96px)]">
          <div className="shell grid gap-10">
            <header className="grid max-w-[680px] gap-4" data-reveal>
              <h2 className="text-h2 font-medium">{band.question}</h2>
              <p className="text-body text-ink-1">{band.answer}</p>
            </header>

            <div className="mx-auto grid w-full max-w-[1120px] gap-5" data-reveal>
              <AppWindow shot={band.shot} tab={band.tab} caption={band.caption} />
              <div className="grid gap-3 md:grid-cols-2">
                {CLIS.map((cli) => (
                  <div key={cli} className="grid content-start gap-2 rounded-card bg-s2 p-5">
                    <h3 translate="no" className="inline-flex items-center gap-2 text-sec font-medium text-ink-0">
                      <CliDot cli={cli} />
                      {CLI_LABEL[cli]}
                    </h3>
                    <p className="text-body text-ink-1">{DIFFS[band.id][cli]}</p>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </section>
      ))}
    </div>
  );
}
