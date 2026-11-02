// Golden section "usage": what core/usage.mjs scan() returns for the synthetic HOME (totals, sessions, windows, files).
// Object keys are sorted so a rerun gives no diff: the order logs were read in is not part of the contract.
import { scan } from '../../core/usage.mjs';

export const name = 'usage';

const sorted = (value) => {
  if (Array.isArray(value)) return value.map(sorted);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map((k) => [k, sorted(value[k])]));
  return value;
};

export default async function usage(ctx) {
  const h = await ctx.home();
  const result = await scan(h.r);
  ctx.writeGolden('usage', sorted(result));
}
