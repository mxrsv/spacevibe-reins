import { CHANNELS, isChannel, type Channel, type Reply } from '../../src/lib/ipc-contract.ts';
import type { Ctx } from './context.ts';
import type { Handler, Handlers } from './handler.ts';
import { refuse, toReply, tooLarge } from './reply.ts';

export type HandlerTable = Partial<Record<Channel, Handler<Channel>>>;

// Merges the `handlers` exported by every electron/ipc/*.ts file. A channel claimed twice, or a
// handler without a contract entry, is a programming error and fails at startup.
export function buildHandlerTable(modules: Record<string, { handlers: Handlers }>): HandlerTable {
  const table: Record<string, Handler<Channel>> = {};
  for (const [file, mod] of Object.entries(modules)) {
    for (const [channel, handler] of Object.entries(mod.handlers)) {
      if (!isChannel(channel)) throw new Error(`${file} handles "${channel}", which is not in the IPC contract.`);
      if (table[channel]) throw new Error(`"${channel}" has more than one handler.`);
      table[channel] = handler as Handler<Channel>;
    }
  }
  return table;
}

export function missingChannels(table: HandlerTable): Channel[] {
  return CHANNELS.filter((c) => !table[c]);
}

// The whole request path after the sender check: allow-list, size limit, handler, error shape.
export async function dispatch(table: HandlerTable, ctx: Ctx, channel: unknown, request: unknown): Promise<Reply<unknown>> {
  if (!isChannel(channel)) return refuse('Not allowed.', 403);
  const handler = table[channel];
  if (!handler) return refuse('Not found.', 404);
  if (tooLarge(request)) return refuse('That is too large.', 413);
  return toReply(() => handler(ctx, request as never));
}
