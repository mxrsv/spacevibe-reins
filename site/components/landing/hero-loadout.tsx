import type { CSSProperties } from "react";

import { CLI_LABEL, HERO_LOADOUT } from "./content";
import { CliDot, DemoTag, UsageCell, rowMaxOf } from "./usage-cell";

/**
 * The hero's second focal, after the heading: a slice of the Loadout table on
 * glass, standing where the planet's limb is brightest. Four rows, one usage state
 * each, two CLI columns, so the product's one idea (compare the two CLIs by eye)
 * is visible before any section is read.
 */
export function HeroLoadout() {
  return (
    <div
      className="glass w-full max-w-[384px] shrink-0 rounded-card p-1 lg:w-[384px]"
      data-rise
      style={{ "--rise": "380ms" } as CSSProperties}
      aria-label="Example Loadout rows"
    >
      <div className="flex items-center justify-between px-3 pt-2.5 pb-2">
        <span className="text-sec font-medium text-ink-0">Loadout</span>
        <DemoTag />
      </div>

      <div className="grid grid-cols-[minmax(0,1fr)_108px_108px] items-center gap-x-3 px-3 pb-1.5 text-tiny text-ink-2">
        <span>Item</span>
        <span className="inline-flex items-center gap-1.5">
          <CliDot cli="claude" />
          {CLI_LABEL.claude}
        </span>
        <span className="inline-flex items-center gap-1.5">
          <CliDot cli="codex" />
          {CLI_LABEL.codex}
        </span>
      </div>

      <ul className="rounded-[9px] border border-edge bg-[rgb(8_9_11/55%)]">
        {HERO_LOADOUT.map((row) => {
          const max = rowMaxOf(row.claude, row.codex);
          return (
            <li
              key={row.name}
              className="grid grid-cols-[minmax(0,1fr)_108px_108px] items-center gap-x-3 px-3 py-2.5 not-last:border-b not-last:border-edge"
            >
              <span className="flex min-w-0 flex-col">
                <span className="truncate text-sec text-ink-0">{row.name}</span>
                <span className="text-tiny text-ink-2">{row.kind}</span>
              </span>
              <UsageCell cli="claude" cell={row.claude} rowMax={max} />
              <UsageCell cli="codex" cell={row.codex} rowMax={max} plugin={row.plugin} />
            </li>
          );
        })}
      </ul>

      <p className="px-3 pt-2 pb-1.5 text-tiny text-ink-2">Counted from local session logs.</p>
    </div>
  );
}
