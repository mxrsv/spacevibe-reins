import { session, type WebContents } from 'electron';
import { allowNavigation, allowWindowOpen, type TrustedPages } from './lib/window-policy.ts';

export interface Refusals { navigation: number; windowOpen: number }

// Applied to every WebContents, so a window created later is covered too. The app is one page:
// it never navigates, opens windows, attaches webviews or asks for device permissions.
export function hardenWebContents(contents: WebContents, pages: TrustedPages, refusals: Refusals): void {
  const guard = (event: { preventDefault(): void }, url: string) => {
    if (allowNavigation(url, pages)) return;
    refusals.navigation++;
    event.preventDefault();
  };
  contents.on('will-navigate', (event, url) => guard(event, url));
  contents.on('will-redirect', (event, url) => guard(event, url));
  contents.on('will-attach-webview', (event) => event.preventDefault());
  contents.setWindowOpenHandler(() => {
    refusals.windowOpen++;
    return { action: allowWindowOpen() ? 'allow' : 'deny' } as { action: 'deny' };
  });
}

// Built app: nothing leaves the machine and no permission is ever granted. Dev builds still
// reach the local Vite server and its websocket.
export function hardenSession(dev: boolean): void {
  const ses = session.defaultSession;
  ses.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
  ses.setPermissionCheckHandler(() => false);
  ses.webRequest.onBeforeRequest((details, callback) => {
    const url = details.url;
    const local = url.startsWith('file:') || url.startsWith('devtools:') || url.startsWith('data:');
    const devServer = dev && /^(https?|wss?):\/\/(localhost|127\.0\.0\.1)(:|\/)/.test(url);
    callback({ cancel: !local && !devServer });
  });
}
