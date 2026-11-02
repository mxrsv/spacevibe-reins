import { UserError } from '#core/mutate.mjs';
import type { Cli } from '../../src/lib/ipc-contract.ts';

const CLIS: readonly Cli[] = ['claude', 'codex'];

export function asObject(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new UserError('Bad request.');
  return value as Record<string, unknown>;
}

export function str(value: unknown, optional = false): string {
  if (typeof value === 'string') return value;
  if (optional && value === undefined) return '';
  throw new UserError('Bad request.');
}

export function optionalStr(value: unknown): string | undefined {
  return value === undefined ? undefined : str(value);
}

export function optionalNumber(value: unknown): number | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new UserError('Bad request.');
  return value;
}

export function cli(value: unknown): Cli {
  if (!CLIS.includes(value as Cli)) throw new UserError('Unknown CLI.');
  return value as Cli;
}

export function clis(value: unknown): Cli[] {
  if (!Array.isArray(value) || value.length === 0) throw new UserError('Pick at least one CLI.');
  return value.map(cli);
}

export function strings(value: unknown): string[] {
  if (!Array.isArray(value)) throw new UserError('Bad request.');
  return value.map((v) => str(v));
}

export const idOf = (request: unknown): string => str(asObject(request).id);
