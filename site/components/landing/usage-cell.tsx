import { EyeOff, Lock, Plus } from "lucide-react";

import { CLI_LABEL, type CLI, type UsageCellState } from "./content";

const NUMBER = new Intl.NumberFormat("en-US");

interface UsageCellProps {
  readonly cli: CLI;
  readonly cell: UsageCellState;
  /** The larger of the two counts on the row; bars are compared across the row. */
  readonly rowMax: number;
  readonly plugin?: boolean;
}

/**
 * The five usage states, each with its own form so they never read alike:
 * counted = bar and number · never ran = red 0 · not counted yet = dashed track ·
 * not measurable = icon and label · not installed = "Add to <CLI>" in place.
 * Static: these are examples, not controls.
 */
export function UsageCell({ cli, cell, rowMax, plugin = false }: UsageCellProps) {
  const fill = cli === "claude" ? "bg-claude" : "bg-codex";

  switch (cell.state) {
    case "counted": {
      const width = rowMax > 0 ? Math.max(6, Math.round((cell.runs / rowMax) * 100)) : 0;
      return (
        <span className="flex items-center gap-3 min-w-0">
          <span className="relative h-1.5 flex-1 min-w-0 rounded-full bg-s3 overflow-hidden">
            <span className={`absolute inset-y-0 left-0 rounded-full ${fill}`} style={{ width: `${width}%` }} />
          </span>
          <span className="flex items-baseline gap-1.5 shrink-0">
            <span className="tnum text-sec font-medium text-ink-0">{NUMBER.format(cell.runs)}</span>
            {cell.errors ? <span className="tnum text-tiny text-danger">{cell.errors} err</span> : null}
          </span>
        </span>
      );
    }
    case "never":
      return (
        <span className="flex items-center gap-2">
          <span className="tnum text-sec font-medium text-danger">0</span>
          <span className="whitespace-nowrap text-tiny text-ink-2">never ran</span>
        </span>
      );
    case "pending":
      return (
        <span className="flex items-center gap-3">
          <span className="h-1.5 flex-1 rounded-full border border-dashed border-edge-hover" />
          <span className="text-tiny text-ink-2 shrink-0">counting…</span>
        </span>
      );
    case "unmeasurable":
      return (
        <span className="flex items-center gap-2 text-ink-2" title={cell.reason}>
          <EyeOff size={13} strokeWidth={1.6} aria-hidden="true" />
          <span className="whitespace-nowrap text-tiny">not measurable</span>
        </span>
      );
    case "missing":
      return plugin ? (
        <span className="flex items-center gap-2 text-ink-2">
          <Lock size={12} strokeWidth={1.6} aria-hidden="true" />
          <span className="text-tiny">plugin-owned</span>
        </span>
      ) : (
        <span className="inline-flex h-6 items-center gap-1 whitespace-nowrap rounded-ctl border border-edge-strong px-1.5 text-tiny text-ink-1">
          <Plus size={11} strokeWidth={2} aria-hidden="true" />
          Add to {CLI_LABEL[cli]}
        </span>
      );
  }
}

export function rowMaxOf(a: UsageCellState, b: UsageCellState): number {
  const runs = (c: UsageCellState) => (c.state === "counted" ? c.runs : 0);
  return Math.max(runs(a), runs(b));
}

/** Small coloured dot that names a CLI wherever the two are side by side. */
export function CliDot({ cli, className = "" }: { readonly cli: CLI; readonly className?: string }) {
  return (
    <span
      className={`inline-block size-2 shrink-0 rounded-full ${cli === "claude" ? "bg-claude" : "bg-codex"} ${className}`}
      aria-hidden="true"
    />
  );
}

/** Every panel built on synthetic fixture data carries this, top right. */
export function DemoTag({ className = "" }: { readonly className?: string }) {
  return (
    <span
      className={`inline-flex h-5 items-center rounded-ctl border border-edge px-1.5 font-mono text-[10px] uppercase tracking-[0.08em] text-ink-2 ${className}`}
    >
      demo data
    </span>
  );
}
