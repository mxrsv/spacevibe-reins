import { ChevronDown, ChevronRight } from "lucide-react";

import { CLI_LABEL, RULES, type Verdict } from "./content";
import { Chip, Panel } from "./feature-section";
import { CliDot, DemoTag } from "./usage-cell";

const VERDICT_CLASS: Record<Verdict, string> = {
  allow: "bg-[rgb(98_194_144/14%)] text-ok",
  ask: "bg-[rgb(232_180_87/14%)] text-warn",
  deny: "bg-[rgb(240_112_112/14%)] text-danger",
  mixed: "bg-s3 text-ink-1",
};

const VERDICT_LABEL: Record<Verdict, string> = { allow: "Allow", ask: "Ask", deny: "Deny", mixed: "Mixed" };

function VerdictPill({ verdict }: { readonly verdict: Verdict }) {
  return (
    <span className={`inline-flex h-6 items-center rounded-[6px] px-2 text-tiny font-medium ${VERDICT_CLASS[verdict]}`}>
      {VERDICT_LABEL[verdict]}
    </span>
  );
}

/** The capability grid at one scope, one row expanded to the rules behind its cell. */
export function RulesVisual() {
  return (
    <Panel
      tools={
        <>
          <span className="text-tiny text-ink-2">Scope</span>
          {RULES.scopes.map((scope, index) => (
            <Chip key={scope} active={index === 0} dismissible={index > 0}>
              {scope}
            </Chip>
          ))}
          <DemoTag className="ml-auto" />
        </>
      }
    >
      <div className="grid grid-cols-[minmax(0,1fr)_112px_112px] items-center gap-x-4 border-b border-edge px-4 py-2 text-tiny text-ink-2 max-sm:grid-cols-[minmax(0,1fr)_84px_84px]">
        <span>Capability</span>
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
        {RULES.rows.map((row) => {
          const expanded = row.capability === RULES.expanded;
          const Caret = expanded ? ChevronDown : ChevronRight;
          return (
            <li key={row.capability} className="not-last:border-b not-last:border-edge">
              <div className="grid grid-cols-[minmax(0,1fr)_112px_112px] items-center gap-x-4 px-4 py-2.5 max-sm:grid-cols-[minmax(0,1fr)_84px_84px]">
                <span className="flex items-center gap-2 text-sec text-ink-0">
                  <Caret size={14} strokeWidth={1.6} aria-hidden="true" className="text-ink-2" />
                  {row.capability}
                </span>
                <VerdictPill verdict={row.claude} />
                <VerdictPill verdict={row.codex} />
              </div>

              {expanded && row.rules ? (
                <ul className="grid gap-1 border-t border-edge bg-s2 px-4 py-3 pl-10">
                  {row.rules.map((rule) => (
                    <li key={rule.rule} className="flex items-center gap-3">
                      <span className={`w-10 text-tiny font-medium ${rule.verdict === "deny" ? "text-danger" : "text-ok"}`}>
                        {VERDICT_LABEL[rule.verdict]}
                      </span>
                      <code className="font-mono text-[12px] text-ink-1">{rule.rule}</code>
                      <span className="ml-auto text-tiny text-ink-2 max-sm:hidden">~/.claude/settings.json</span>
                    </li>
                  ))}
                </ul>
              ) : null}
            </li>
          );
        })}
      </ul>
    </Panel>
  );
}
