import { join, sep } from 'node:path';

// A Worker needs a real file on disk. In a packaged app core/ is unpacked next to app.asar
// (electron-builder.yml asarUnpack), so the archive path is swapped for the unpacked one.
export function usageWorkerPath(appPath: string): string {
  return join(appPath, 'core', 'usage.mjs').replace(`app.asar${sep}`, `app.asar.unpacked${sep}`);
}
