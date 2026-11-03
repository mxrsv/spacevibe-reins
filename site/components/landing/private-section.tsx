import { PRIVATE } from "./content";

/**
 * Four guarantees in one panel divided by hairlines, not four cards with gaps.
 * Each cell is a lead sentence and one line of how; no icons, no numbers.
 */
export function PrivateSection() {
  return (
    <section id={PRIVATE.id} className="border-t border-edge py-[clamp(64px,6.7vw,96px)]">
      <div className="shell grid gap-10">
        <h2 className="max-w-[520px] text-h2 font-medium" data-reveal>
          {PRIVATE.heading}
        </h2>
        <ul className="grid overflow-hidden rounded-panel border border-edge bg-s1 md:grid-cols-2" data-reveal>
          {PRIVATE.items.map((item, index) => (
            <li
              key={item.lead}
              className={`grid content-start gap-2 p-7 ${index % 2 === 0 ? "md:border-r md:border-edge" : ""} ${index < 2 ? "border-b border-edge" : "max-md:not-last:border-b max-md:not-last:border-edge"}`}
            >
              <h3 className="text-[17px] font-medium leading-6 tracking-[-0.01em]">{item.lead}</h3>
              <p className="text-sec text-ink-1">{item.body}</p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
