import { contextBridge, ipcRenderer } from 'electron';
import { isChannel, type ReinsApi } from '../src/lib/ipc-contract.ts';

// The only thing the renderer gets: one invoke that refuses channels outside the contract.
const api: ReinsApi = {
  invoke: (channel, request) => {
    if (!isChannel(channel)) return Promise.resolve({ ok: false, error: 'Not allowed.', status: 403 });
    return ipcRenderer.invoke(channel, request);
  },
};

contextBridge.exposeInMainWorld('reins', api);
