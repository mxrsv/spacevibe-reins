import { ipcMain, type IpcMainInvokeEvent } from 'electron';
import { CHANNELS } from '../src/lib/ipc-contract.ts';
import type { Ctx } from './lib/context.ts';
import type { Handlers } from './lib/handler.ts';
import { buildHandlerTable, dispatch, missingChannels } from './lib/handler-table.ts';
import { refuse } from './lib/reply.ts';
import { isTrustedPage, type TrustedPages } from './lib/window-policy.ts';

// Every electron/ipc/*.ts file is picked up here, so a new area needs no edit to this file.
const modules = import.meta.glob<{ handlers: Handlers }>(['./ipc/*.ts', '!./ipc/*.test.ts'], { eager: true });

export function registerIpc(ctx: Ctx, pages: TrustedPages): void {
  const table = buildHandlerTable(modules);
  const missing = missingChannels(table);
  if (missing.length) throw new Error(`No handler for: ${missing.join(', ')}`);
  for (const channel of CHANNELS) {
    ipcMain.handle(channel, (event: IpcMainInvokeEvent, request: unknown) => {
      // Only the app's own top frame may call in; any other page or frame is refused.
      const frame = event.senderFrame;
      if (!frame || frame !== event.sender.mainFrame || !isTrustedPage(frame.url, pages)) return refuse('Not allowed.', 403);
      return dispatch(table, ctx, channel, request);
    });
  }
}
