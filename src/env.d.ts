/// <reference types="vite/client" />
import type { ReinsApi } from './lib/ipc-contract.ts';

declare global {
  interface Window {
    reins: ReinsApi;
  }
}
