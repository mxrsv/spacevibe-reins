import { CLI_LABEL, TOKENS } from "./content";
import { Chip, Panel, Segmented } from "./feature-section";
import { CliDot, DemoTag } from "./usage-cell";

const USD = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" });

function sum(values: readonly number[]): number {
  return values.reduce((total, value) => total + value, 0);
}

/** Thousands of tokens → "1.2M" / "640K". */
function tokens(k: number): string {
  return k >= 1000 ? `${(k / 1000).toFixed(1)}M` : `${Math.round(k)}K`;
}

const CLAUDE_TOTAL = sum(TOKENS.byDay.claude);
const CODEX_TOTAL = sum(TOKENS.byDay.codex);
const PEAK = Math.max(...TOKENS.byDay.claude, ...TOKENS.byDay.codex);

/** Lead total, paired columns by day on one axis, then the estimated-cost accounting. */
export function TokensVisual() {
  const costRows = TOKENS.cost.map((row) => {
    const base = row.cli === "claude" ? CLAUDE_TOTAL : CODEX_TOTAL;
    const k = base * row.share;
    return { ...row, k, usd: row.usdPerM === null ? null : (k / 1000) * row.usdPerM };
  });
  const priced = costRows.reduce((total, row) => total + (row.usd ?? 0), 0);

  return (
    <Panel
      tools={
        <>
          <Segmented options={TOKENS.periods} active="Day" />
          {TOKENS.measures.map((measure, index) => (
            <Chip key={measure} active={index === 0}>
              {measure}
            </Chip>
          ))}
          <DemoTag className="ml-auto" />
        </>
      }
    >
      <div className="grid gap-6 px-4 pt-5 pb-4">
        <div className="flex flex-wrap items-end gap-x-8 gap-y-3">
          <div>
            <p className="text-tiny text-ink-2">Last 14 days</p>
            <p className="tnum text-[40px] font-medium leading-none tracking-[-0.03em] text-ink-0">{tokens(CLAUDE_TOTAL + CODEX_TOTAL)}</p>
          </div>
          <div className="flex items-baseline gap-2">
            <CliDot cli="claude" />
            <span className="tnum text-stat font-medium text-ink-0">{tokens(CLAUDE_TOTAL)}</span>
            <span className="text-tiny text-ink-2">{CLI_LABEL.claude}</span>
          </div>
          <div className="flex items-baseline gap-2">
            <CliDot cli="codex" />
            <span className="tnum text-stat font-medium text-ink-0">{tokens(CODEX_TOTAL)}</span>
            <span className="text-tiny text-ink-2">{CLI_LABEL.codex}</span>
          </div>
        </div>

        <div className="grid h-36 grid-cols-14 items-end gap-1.5 border-b border-edge" aria-label="Tokens per day, both CLIs">
          {TOKENS.byDay.claude.map((claude, index) => {
            const codex = TOKENS.byDay.codex[index] ?? 0;
            return (
              <div key={index} className="flex h-full items-end justify-center gap-0.5">
                <span className="w-full max-w-2.5 rounded-t-[3px] bg-claude" style={{ height: `${(claude / PEAK) * 100}%` }} />
                <span className="w-full max-w-2.5 rounded-t-[3px] bg-codex" style={{ height: `${(codex / PEAK) * 100}%` }} />
              </div>
            );
          })}
        </div>
      </div>

      <div className="border-t border-edge">
        <div className="flex items-center gap-2 bg-s2 px-4 py-2 text-tiny text-ink-2">
          <span className="font-medium text-ink-1">Estimated cost</span>
          <span className="ml-auto">priced models only</span>
        </div>
        <ul>
          {costRows.map((row) => (
            <li key={`${row.cli}-${row.model}`} className="grid grid-cols-[minmax(0,1fr)_80px_96px] items-center gap-x-4 px-4 py-2 text-sec not-last:border-b not-last:border-edge">
              <span className="flex min-w-0 items-center gap-2">
                <CliDot cli={row.cli} />
                <span className="truncate text-ink-0">{row.model}</span>
              </span>
              <span className="tnum text-right text-ink-1">{tokens(row.k)}</span>
              {row.usd === null ? (
                <span className="text-right text-tiny text-ink-2">not priced</span>
              ) : (
                <span className="tnum text-right text-ink-0">{USD.format(row.usd)}</span>
              )}
            </li>
          ))}
          <li className="grid grid-cols-[minmax(0,1fr)_80px_96px] items-center gap-x-4 border-t border-edge-strong bg-s2 px-4 py-2.5 text-sec">
            <span className="text-ink-1">Sum of priced models</span>
            <span />
            <span className="tnum text-right font-medium text-ink-0">{USD.format(priced)} est.</span>
          </li>
        </ul>
      </div>
    </Panel>
  );
}
