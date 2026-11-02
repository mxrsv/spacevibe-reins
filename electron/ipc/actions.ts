import { addAgent, addHook, addSkill, copyToOther, installSource, previewSource, removeDeadHooks, removeItem, undo } from '#core/mutate.mjs';
import type { Handlers } from '../lib/handler.ts';
import { asObject, cli, clis, idOf, optionalNumber, optionalStr, str, strings } from '../lib/validate.ts';

// Every write goes through core/mutate.mjs, which journals it so it can be undone.
export const handlers: Handlers = {
  'skill:add': (ctx, request) => {
    const b = asObject(request);
    return addSkill(ctx.roots, { clis: clis(b.clis), name: str(b.name), description: str(b.description), body: optionalStr(b.body) });
  },
  'agent:add': (ctx, request) => {
    const b = asObject(request);
    return addAgent(ctx.roots, { clis: clis(b.clis), name: str(b.name), description: str(b.description), instructions: optionalStr(b.instructions) });
  },
  'hook:add': (ctx, request) => {
    const b = asObject(request);
    return addHook(ctx.roots, { clis: clis(b.clis), event: str(b.event), matcher: optionalStr(b.matcher), command: str(b.command), timeout: optionalNumber(b.timeout) });
  },
  'source:preview': (ctx, request) => previewSource(ctx.roots, { source: str(asObject(request).source) }),
  'source:install': (ctx, request) => {
    const b = asObject(request);
    return installSource(ctx.roots, { sourceId: str(b.sourceId), names: strings(b.names), clis: clis(b.clis) });
  },
  'item:remove': (ctx, request) => removeItem(ctx.roots, { id: idOf(request) }),
  'hook:remove-dead': (ctx, request) => removeDeadHooks(ctx.roots, { cli: cli(asObject(request).cli) }),
  'item:copy': (ctx, request) => copyToOther(ctx.roots, { id: idOf(request) }),
  'journal:undo': (ctx, request) => undo(ctx.roots, { id: idOf(request) }),
};
