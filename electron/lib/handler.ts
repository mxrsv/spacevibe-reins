import type { Channel, Req, Res } from '../../src/lib/ipc-contract.ts';
import type { Ctx } from './context.ts';

export type Handler<C extends Channel> = (ctx: Ctx, request: Req<C>) => Res<C> | Promise<Res<C>>;

// Each file under electron/ipc/ exports `handlers` of this type for the channels it owns.
export type Handlers = { [C in Channel]?: Handler<C> };
