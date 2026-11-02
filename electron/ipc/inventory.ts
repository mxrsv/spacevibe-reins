import { readInventory, readItemFile } from '#core/inventory.mjs';
import { UserError } from '#core/mutate.mjs';
import type { Handlers } from '../lib/handler.ts';
import { idOf } from '../lib/validate.ts';
import { withUsage } from '../lib/with-usage.ts';

export const handlers: Handlers = {
  'inventory:read': (ctx) => withUsage(readInventory(ctx.roots), ctx.usage.get()),
  // Takes an id, never a path: the file comes from the inventory itself.
  'item:read': (ctx, request) => {
    const item = readInventory(ctx.roots).items.find((x: { id: string }) => x.id === idOf(request));
    if (!item) throw new UserError('This item no longer exists.', 404);
    return readItemFile(item.file);
  },
};
