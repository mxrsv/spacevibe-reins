import { UserError } from '#core/mutate.mjs';
import type { Reply } from '../../src/lib/ipc-contract.ts';

export const REQUEST_LIMIT_BYTES = 256 * 1024;

const fail = (error: string, status: number): Reply<never> => ({ ok: false, error, status });

// ipcMain.handle rewrites thrown errors and drops custom fields, so errors travel as a value.
// The shape and messages match what server.mjs sent over HTTP.
export async function toReply<T>(work: () => T | Promise<T>): Promise<Reply<T>> {
  try {
    return { ok: true, data: await work() };
  } catch (err) {
    if (err instanceof UserError) return fail(err.message, err.status);
    const code = (err as NodeJS.ErrnoException | undefined)?.code;
    if (code === 'ENOENT') return fail('Not found.', 404);
    // Log the code or name only: messages can carry paths and values (AGENTS.md R3).
    console.error(code ?? (err as Error | undefined)?.name);
    return fail('Something went wrong. Nothing else was changed.', 500);
  }
}

export const tooLarge = (request: unknown): boolean => {
  try {
    return Buffer.byteLength(JSON.stringify(request) ?? '') > REQUEST_LIMIT_BYTES;
  } catch {
    return true;
  }
};

export const refuse = fail;
