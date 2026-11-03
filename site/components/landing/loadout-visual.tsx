import { Lock } from "lucide-react";

import { CLI_LABEL, LOADOUT, USAGE_LEGEND } from "./content";
import { Chip, Panel } from "./feature-section";
import { CliDot, DemoTag, UsageCell, rowMaxOf } from "./usage-cell";

const KIND_LABEL = { skill: "Skill", agent: "Agent", hook: "Hook" } as const;

/** The Loadout table: filter chips, two CLI columns, nine rows across all five states, then the legend. */
export function LoadoutVisual() {
  return (
    <Panel
      tools={
        <>
          {LOADOUT.filters.map((filter, index) => (
            <Chip key={filter} active={index === 0}>
              {filter}
            </Chip>
          ))}
          <DemoTag className="ml-auto" />
        </>
      }
    >
      <div className="grid grid-cols-2 items-center gap-x-3 border-b border-edge px-4 py-2 text-tiny text-ink-2 sm:grid-cols-[minmax(0,1fr)_minmax(120px,0.6fr)_minmax(120px,0.6fr)] sm:gap-x-4">
        <span className="hidden sm:block">Item</span>
        <span className="inline-flex items-center gap-1.5">
          <CliDot cli="claude" />
          {CLI_LABEL.claude}
        </span>
        <span className="inline-flex items-center gap-1.5">
          <CliDot cli="codex" />
          {CLI_LABEL.codex}
        </span>
      </div>

      <ul>
        {LOADOUT.rows.map((row) => {
          const max = rowMaxOf(row.claude, row.codex);
          return (
            <li
              key={row.name}
              className="grid grid-cols-2 items-center gap-x-3 gap-y-2 px-4 py-2.5 transition-colors duration-150 not-last:border-b not-last:border-edge hover:bg-s2 sm:grid-cols-[minmax(0,1fr)_minmax(120px,0.6fr)_minmax(120px,0.6fr)] sm:gap-x-4 sm:gap-y-0"
            >
              <span className="col-span-2 flex min-w-0 items-center gap-2.5 sm:col-span-1">
                <span className="inline-flex h-5 shrink-0 items-center rounded-[5px] bg-s3 px-1.5 font-mono text-[10px] uppercase tracking-[0.06em] text-ink-2">
                  {KIND_LABEL[row.kind]}
                </span>
                <span className="truncate text-sec text-ink-0">{row.name}</span>
                {row.plugin ? <Lock size={12} strokeWidth={1.6} aria-label="plugin-owned, read-only" className="shrink-0 text-ink-2" /> : null}
              </span>
              <UsageCell cli="claude" cell={row.claude} rowMax={max} plugin={row.plugin} />
              <UsageCell cli="codex" cell={row.codex} rowMax={max} plugin={row.plugin} />
            </li>
          );
        })}
      </ul>

      <ul className="flex flex-wrap gap-x-5 gap-y-2 border-t border-edge bg-s2 px-4 py-3">
        {USAGE_LEGEND.map((item) => (
          <li key={item.state} className="flex items-baseline gap-1.5 text-tiny">
            <span className="font-medium text-ink-1">{item.label}</span>
            <span className="text-ink-2">{item.detail}</span>
          </li>
        ))}
      </ul>
    </Panel>
  );
}
