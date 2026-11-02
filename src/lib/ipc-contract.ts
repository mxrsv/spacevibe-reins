// The one place IPC channels and their payloads are defined. Bundled into both the preload and the
// renderer, so it must not import Node or Electron. To add a channel: add it to IpcContract and to
// CHANNELS here, then export a handler for it from a new file under electron/ipc/.

export type Cli = 'claude' | 'codex';
export type ItemKind = 'skill' | 'agent';

export interface ItemUsage { sessions: number; last: string | null; weeks: number[] }
export interface HookUsage { runs: number; avgMs: number | null; totalMs: number; errors: number; last: string | null }

export interface InventoryItem {
  id: string;
  cli: Cli;
  kind: ItemKind;
  name: string;
  entry: string;
  description: string;
  descChars: number;
  owner: string;
  path: string;
  file: string;
  removable: boolean;
  override?: string | null;
  inOther: boolean;
  usage: ItemUsage | null;
}

export interface InventoryHook {
  id: string;
  cli: Cli;
  kind: 'hook';
  event: string;
  matcher: string | null;
  command: string;
  timeout: number | null;
  async: boolean;
  owner: string;
  removable: boolean;
  dead: boolean;
  paths: string[];
  hash: string;
  file: string;
  usage: HookUsage | null;
}

export interface UsageStatus {
  state: 'scanning' | 'ready' | 'failed';
  done: number;
  total: number;
  sessions: Record<Cli, number> | null;
}

export interface InventoryView {
  items: InventoryItem[];
  hooks: InventoryHook[];
  problems: string[];
  events: Record<Cli, string[]>;
  roots: Record<Cli, string>;
  usageStatus: UsageStatus;
  weeks: number;
}

export interface JournalEntry { id: string; at: string; label: string; ops: unknown[] }
export interface HistoryEntry { id: string; at: string; label: string; undone: boolean; count: number }
export interface ItemFile { size: number; text: string; truncated: boolean }
export interface SourcePreview { sourceId: string; skills: { name: string; description?: string }[] }

export interface AddSkillRequest { clis: Cli[]; name: string; description: string; body?: string }
export interface AddAgentRequest { clis: Cli[]; name: string; description: string; instructions?: string }
export interface AddHookRequest { clis: Cli[]; event: string; matcher?: string; command: string; timeout?: number }
export interface IdRequest { id: string }

export interface IpcContract {
  'inventory:read': { req: void; res: InventoryView };
  'history:list': { req: void; res: HistoryEntry[] };
  'item:read': { req: IdRequest; res: ItemFile };
  'skill:add': { req: AddSkillRequest; res: JournalEntry };
  'agent:add': { req: AddAgentRequest; res: JournalEntry };
  'hook:add': { req: AddHookRequest; res: JournalEntry };
  'source:preview': { req: { source: string }; res: SourcePreview };
  'source:install': { req: { sourceId: string; names: string[]; clis: Cli[] }; res: JournalEntry };
  'item:remove': { req: IdRequest; res: JournalEntry };
  'hook:remove-dead': { req: { cli: Cli }; res: JournalEntry };
  'item:copy': { req: IdRequest; res: JournalEntry };
  'journal:undo': { req: IdRequest; res: { label: string } };
}

export type Channel = keyof IpcContract;
export type Req<C extends Channel> = IpcContract[C]['req'];
export type Res<C extends Channel> = IpcContract[C]['res'];

// A Record forces this list and IpcContract to stay identical: a missing or extra key fails typecheck.
const CHANNEL_SET: Record<Channel, true> = {
  'inventory:read': true,
  'history:list': true,
  'item:read': true,
  'skill:add': true,
  'agent:add': true,
  'hook:add': true,
  'source:preview': true,
  'source:install': true,
  'item:remove': true,
  'hook:remove-dead': true,
  'item:copy': true,
  'journal:undo': true,
};
export const CHANNELS = Object.keys(CHANNEL_SET) as Channel[];
export const isChannel = (value: unknown): value is Channel => typeof value === 'string' && Object.hasOwn(CHANNEL_SET, value);

export type Reply<T> = { ok: true; data: T } | { ok: false; error: string; status: number };

// What the preload exposes as window.reins.
export interface ReinsApi {
  invoke<C extends Channel>(channel: C, request?: Req<C>): Promise<Reply<Res<C>>>;
}
