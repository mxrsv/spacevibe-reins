import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'electron-vite';
import { resolve } from 'node:path';

// core/ is plain .mjs that must stay on disk: its worker is started from a real file path and the
// packaged app unpacks it from the asar. It is imported as #core/*.mjs (package.json "imports") and
// left external, so Node resolves it at run time from the app folder. A relative path would be
// rewritten wrongly by the bundler.
const externalCore = /^#core\//;

// Vite's dev client needs inline script and a websocket, so the dev server gets a looser policy.
// The built app keeps the strict one in src/index.html.
const devCsp = {
  name: 'reins-dev-csp',
  apply: 'serve' as const,
  transformIndexHtml: (html: string) =>
    html.replace(
      /(http-equiv="Content-Security-Policy" content=")[^"]*"/,
      `$1default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' ws://localhost:* http://localhost:*; base-uri 'none'; form-action 'none'"`,
    ),
};

export default defineConfig({
  main: {
    build: {
      lib: { entry: resolve('electron/main.ts'), formats: ['es'] },
      rollupOptions: { external: externalCore, output: { entryFileNames: 'index.js' } },
    },
  },
  preload: {
    build: {
      // A sandboxed preload must be CommonJS.
      lib: { entry: resolve('electron/preload.ts'), formats: ['cjs'] },
      rollupOptions: { output: { entryFileNames: 'index.cjs' } },
    },
  },
  renderer: {
    // Root is src/, not the repo: the dev server must not be able to serve mocks/ or core/.
    root: resolve('src'),
    resolve: { alias: { '@': resolve('src') } },
    plugins: [react(), tailwindcss(), devCsp],
    build: { rollupOptions: { input: resolve('src/index.html') } },
  },
});
