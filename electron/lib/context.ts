import { roots } from '#core/inventory.mjs';
import type { UsageStore } from './usage-store.ts';

export type Roots = ReturnType<typeof roots>;

// Everything a handler may touch. Tests pass roots built from a temporary HOME.
export interface Ctx {
  roots: Roots;
  usage: UsageStore;
}
