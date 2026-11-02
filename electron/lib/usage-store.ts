import { Worker } from 'node:worker_threads';
import type { UsageStatus } from '../../src/lib/ipc-contract.ts';

// Shape of core/usage.mjs scan() totals: totals[cli][kind][name or hook hash].
export type UsageTotals = Record<string, Record<string, Record<string, any>>>;

export interface UsageState {
  state: UsageStatus['state'];
  done: number;
  total: number;
  totals: UsageTotals | null;
  sessions: UsageStatus['sessions'];
}

export interface UsageStore {
  get(): UsageState;
  set(next: UsageState): void;
}

export const createUsageStore = (): UsageStore => {
  let state: UsageState = { state: 'scanning', done: 0, total: 0, totals: null, sessions: null };
  return { get: () => state, set: (next) => { state = next; } };
};

// Pure reducer for the messages core/usage.mjs posts from its worker.
export function reduceUsage(state: UsageState, m: any): UsageState {
  if (m.type === 'progress') return { ...state, done: m.done, total: m.total };
  if (m.type === 'done') return { state: 'ready', done: m.result.files, total: m.result.files, totals: m.result.totals, sessions: m.result.sessions };
  if (m.type === 'error') return { ...state, state: 'failed' };
  return state;
}

// workerPath must be a real file on disk (not inside an asar archive). Returns the worker so a
// caller can wait for it or stop it.
export function startUsageScan(store: UsageStore, workerPath: string, env: NodeJS.ProcessEnv): Worker {
  const worker = new Worker(workerPath, { workerData: { usageScan: true, env: { ...env } } });
  worker.on('message', (m) => store.set(reduceUsage(store.get(), m)));
  worker.on('error', () => store.set({ ...store.get(), state: 'failed' }));
  return worker;
}
