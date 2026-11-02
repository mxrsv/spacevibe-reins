import { app, type BrowserWindow } from 'electron';
import type { Refusals } from './harden.ts';

// REINS_TEST=1: no visible window. Loads the real renderer in a hidden window, drives
// window.reins, and prints counts only (never names, paths or values) on one line.
export function attachProbes(win: BrowserWindow) {
  const consoleErrors = { csp: 0, other: 0 };
  win.webContents.on('console-message', (event: any) => {
    const message = String(event?.message ?? '');
    if (/content security policy/i.test(message)) consoleErrors.csp++;
    else if ((event?.level === 'error' || event?.level === 3)) consoleErrors.other++;
  });
  return consoleErrors;
}

const PAGE_CHECK = `(async () => {
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  let inv = await window.reins.invoke('inventory:read');
  for (let i = 0; i < 300 && inv.ok && inv.data.usageStatus.state === 'scanning'; i++) { await wait(100); inv = await window.reins.invoke('inventory:read'); }
  const refused = await window.reins.invoke('fs:read-file', { path: '/etc/hosts' });
  const opened = window.open('https://example.invalid/');
  return {
    inventoryOk: inv.ok,
    items: inv.ok ? inv.data.items.length : -1,
    hooks: inv.ok ? inv.data.hooks.length : -1,
    usageState: inv.ok ? inv.data.usageStatus.state : 'none',
    usageFiles: inv.ok ? inv.data.usageStatus.done : -1,
    sessions: inv.ok ? inv.data.usageStatus.sessions : null,
    badChannelRefused: refused.ok === false && refused.status === 403,
    apiKeys: Object.keys(window.reins),
    nodeLeaked: typeof require !== 'undefined' || typeof process !== 'undefined',
    windowOpenBlocked: opened === null,
  };
})()`;

export async function runHeadlessCheck(win: BrowserWindow, refusals: Refusals, consoleErrors: { csp: number; other: number }): Promise<never> {
  const watchdog = setTimeout(() => { console.log('REINS_TEST {"ok":false,"reason":"timeout"}'); app.exit(1); }, 90_000);
  try {
    const wc = win.webContents;
    const page = await wc.executeJavaScript(PAGE_CHECK);
    const before = wc.getURL();
    await wc.executeJavaScript("location.href = 'https://example.invalid/'; 0").catch(() => 0);
    await new Promise((r) => setTimeout(r, 500));
    const result = {
      ...page,
      navigationBlocked: wc.getURL() === before && refusals.navigation >= 1,
      refusals,
      consoleErrors,
      versions: { node: process.versions.node, electron: process.versions.electron, chrome: process.versions.chrome },
      packaged: app.isPackaged,
    };
    const ok = result.inventoryOk && result.usageState === 'ready' && result.badChannelRefused && !result.nodeLeaked
      && result.windowOpenBlocked && result.navigationBlocked && consoleErrors.csp === 0;
    clearTimeout(watchdog);
    console.log(`REINS_TEST ${JSON.stringify({ ok, ...result })}`);
    app.exit(ok ? 0 : 1);
  } catch (err) {
    clearTimeout(watchdog);
    console.log(`REINS_TEST ${JSON.stringify({ ok: false, reason: (err as Error).name })}`);
    app.exit(1);
  }
  return undefined as never;
}
