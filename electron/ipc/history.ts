import { history } from '#core/mutate.mjs';
import type { Handlers } from '../lib/handler.ts';

export const handlers: Handlers = {
  'history:list': (ctx) => history(ctx.roots),
};
