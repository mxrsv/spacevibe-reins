import { EyeOff, Square } from "lucide-react";

import { ACTIVITY, CLI_LABEL, type CLI, type SessionRow, type SessionState } from "./content";
import { Panel } from "./feature-section";
import { CliDot, DemoTag } from "./usage-cell";

const USD = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" });

const STATE: Record<SessionState, { label: string; dot: string }> = {
  running: { label: "Running", dot: "bg-ok" },
  waiting: { label: "Waiting for you", dot: "bg-warn" },
  idle: { label: "Idle", dot: "bg-ink-2" },
  unmeasurable: { label: "Not measurable", dot: "border border-edge-hover" },
};

function Session({ row }: { readonly row: SessionRow }) {
  const state = STATE[row.state];
  return (
    <li className="grid gap-1 px-4 py-3 not-last:border-b not-last:border-edge">
      <div className="flex items-start justify-between gap-3">
        <span className="min-w-0 truncate text-sec text-ink-0">{row.title}</span>
        {row.state === "unmeasurable" ? (
          <EyeOff size={13} strokeWidth={1.6} aria-label="not measurable" className="mt-1 shrink-0 text-ink-2" />
        ) : (
          <span
            className="inline-flex size-6 shrink-0 items-center justify-center rounded-[6px] border border-edge-strong text-ink-2"
            aria-label="Stop"
          >
            <Square size={9} strokeWidth={2.4} fill="currentColor" aria-hidden="true" />
          </span>
        )}
      </div>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-tiny text-ink-2">
        <span className="inline-flex items-center gap-1.5">
          <span className={`inline-block size-1.5 rounded-full ${state.dot}`} aria-hidden="true" />
          {state.label}
        </span>
        {row.project ? <span>{row.project}</span> : null}
        {row.tool ? <code className="font-mono text-[11px] text-ink-1">{row.tool}</code> : null}
        <span className="tnum ml-auto">{row.usd === null ? "cost not measured" : `${USD.format(row.usd)} est.`}</span>
      </div>
      {row.note ? <p className="text-tiny text-ink-2">{row.note}</p> : null}
    </li>
  );
}

function Lane({ cli }: { readonly cli: CLI }) {
  const rows = ACTIVITY.sessions.filter((row) => row.cli === cli);
  return (
    <div className="min-w-0">
      <div className="flex items-center gap-2 border-b border-edge bg-s2 px-4 py-2 text-tiny text-ink-2">
        <CliDot cli={cli} />
        <span className="font-medium text-ink-1">{CLI_LABEL[cli]}</span>
        <span className="tnum ml-auto">{rows.length} sessions</span>
      </div>
      <ul>
        {rows.map((row) => (
          <Session key={row.title} row={row} />
        ))}
      </ul>
    </div>
  );
}

/** Two session lanes, then failed commands (grouped, counted) and the file history. */
export function ActivityVisual() {
  return (
    <Panel
      tools={
        <>
          <span className="text-sec font-medium text-ink-0">Live</span>
          <span className="text-tiny text-ink-2">refreshes while a session writes</span>
          <DemoTag className="ml-auto" />
        </>
      }
    >
      <div className="grid md:grid-cols-2 md:divide-x md:divide-edge max-md:divide-y max-md:divide-edge">
        <Lane cli="claude" />
        <Lane cli="codex" />
      </div>

      <div className="grid border-t border-edge md:grid-cols-2 md:divide-x md:divide-edge max-md:divide-y max-md:divide-edge">
        <div className="min-w-0">
          <div className="flex items-center gap-2 border-b border-edge bg-s2 px-4 py-2 text-tiny text-ink-2">
            <span className="font-medium text-ink-1">Failed commands</span>
            <span className="ml-auto">repeats grouped</span>
          </div>
          <ul>
            {ACTIVITY.failures.map((failure) => (
              <li key={failure.title} className="grid gap-1 px-4 py-3 not-last:border-b not-last:border-edge">
                <div className="flex items-center gap-3">
                  <CliDot cli={failure.cli} />
                  <code className="min-w-0 truncate font-mono text-[12px] text-ink-0">{failure.title}</code>
                  <span className="tnum ml-auto shrink-0 rounded-[6px] bg-s3 px-1.5 text-tiny font-medium text-ink-1">×{failure.count}</span>
                </div>
                <div className="flex flex-wrap gap-x-3 text-tiny text-ink-2">
                  <span className="tnum">exit {failure.exit}</span>
                  <span className="min-w-0 truncate">{failure.reason}</span>
                  {failure.laterPass ? <span className="text-ok">passed later</span> : null}
                </div>
              </li>
            ))}
          </ul>
        </div>

        <div className="min-w-0">
          <div className="flex items-center gap-2 border-b border-edge bg-s2 px-4 py-2 text-tiny text-ink-2">
            <span className="font-medium text-ink-1">Files</span>
            <span className="ml-auto">edits · which CLI</span>
          </div>
          <ul>
            {ACTIVITY.files.map((file) => (
              <li key={file.label} className="flex items-center gap-3 px-4 py-3 not-last:border-b not-last:border-edge">
                <code className="min-w-0 truncate font-mono text-[12px] text-ink-0">{file.label}</code>
                <span className="ml-auto flex shrink-0 items-center gap-2">
                  <span className="tnum text-tiny text-ink-1">{file.edits}</span>
                  <span className="flex gap-1">
                    {file.clis.map((cli) => (
                      <CliDot key={cli} cli={cli} />
                    ))}
                  </span>
                </span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </Panel>
  );
}
