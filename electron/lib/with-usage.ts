import { bare } from '#core/inventory.mjs';
import type { InventoryHook, InventoryItem, InventoryView } from '../../src/lib/ipc-contract.ts';
import type { UsageState } from './usage-store.ts';

export const WEEKS = 26;
const WEEK_MS = 7 * 24 * 3600 * 1000;

function weekIndex(day: string, now: number): number {
  const age = Math.floor((now - Date.parse(`${day}T00:00:00Z`)) / WEEK_MS);
  return age >= 0 && age < WEEKS ? WEEKS - 1 - age : -1;
}

// Merges the usage scan into the inventory. Pure so it can be tested with a fixed clock.
export function withUsage(inv: any, usage: UsageState, now = Date.now()): InventoryView {
  const t = usage.totals;
  const items: InventoryItem[] = inv.items.map((it: any) => {
    const u = t?.[it.cli]?.[it.kind]?.[bare(it.name)];
    const weeks: number[] = Array(WEEKS).fill(0);
    for (const d of u?.days ?? []) { const i = weekIndex(d, now); if (i >= 0) weeks[i]++; }
    return { ...it, descChars: it.description.length, usage: t ? { sessions: u?.sessions ?? 0, last: u?.last ?? null, weeks } : null };
  });
  const hooks: InventoryHook[] = inv.hooks.map((h: any) => {
    const measurable = h.cli === 'claude';
    const u = t?.[h.cli]?.hook?.[h.hash];
    return { ...h, usage: !t || !measurable ? null : { runs: u?.runs ?? 0, avgMs: u?.timed ? Math.round(u.ms / u.timed) : null, totalMs: u?.ms ?? 0, errors: u?.errors ?? 0, last: u?.last ?? null } };
  });
  const { totals: _totals, ...usageStatus } = usage;
  return { ...inv, items, hooks, usageStatus, weeks: WEEKS };
}
