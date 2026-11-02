import { app, BrowserWindow } from 'electron';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { roots } from '#core/inventory.mjs';
import { clearOldDownloads } from '#core/mutate.mjs';
import { hardenSession, hardenWebContents, type Refusals } from './harden.ts';
import { usageWorkerPath } from './lib/worker-path.ts';
import { createUsageStore, startUsageScan } from './lib/usage-store.ts';
import { registerIpc } from './register-ipc.ts';
import { attachProbes, runHeadlessCheck } from './test-mode.ts';

const TEST = process.env.REINS_TEST === '1';
const devUrl = process.env.ELECTRON_RENDERER_URL;
const pages = { appUrl: pathToFileURL(join(import.meta.dirname, '../renderer/index.html')).href, devUrl };
const refusals: Refusals = { navigation: 0, windowOpen: 0 };

const r = roots(process.env);

if (TEST) {
  // Headless: no dock icon and no window is ever shown. core/roots() already throws when
  // REINS_TEST=1 and a root is under the real home, so a run cannot touch real configs.
  app.setActivationPolicy?.('accessory');
  app.dock?.hide();
  // Keep Electron's own caches out of the real ~/Library too.
  app.setPath('userData', join(r.data, 'electron'));
}

app.on('web-contents-created', (_event, contents) => hardenWebContents(contents, pages, refusals));

const load = (win: BrowserWindow) => (devUrl ? win.loadURL(devUrl) : win.loadFile(join(import.meta.dirname, '../renderer/index.html')));

function createWindow(): BrowserWindow {
  const win = new BrowserWindow({
    width: 1100,
    height: 720,
    show: false,
    webPreferences: {
      preload: join(import.meta.dirname, '../preload/index.cjs'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webSecurity: true,
      allowRunningInsecureContent: false,
      spellcheck: false,
    },
  });
  if (!TEST) win.once('ready-to-show', () => win.show());
  return win;
}

app.whenReady().then(async () => {
  hardenSession(!app.isPackaged && Boolean(devUrl));
  const usage = createUsageStore();
  registerIpc({ roots: r, usage }, pages);
  clearOldDownloads(r);
  startUsageScan(usage, usageWorkerPath(app.getAppPath()), process.env);

  const win = createWindow();
  const consoleErrors = TEST ? attachProbes(win) : null;
  await load(win);
  if (TEST && consoleErrors) await runHeadlessCheck(win, refusals, consoleErrors);
});

app.on('window-all-closed', () => app.quit());
app.on('activate', () => {
  if (!TEST && BrowserWindow.getAllWindows().length === 0) load(createWindow());
});
