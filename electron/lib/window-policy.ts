// Decides which pages may talk to the main process and where the window may navigate.
// No Electron imports, so plain node tests can cover it.
export const stripHash = (url: string): string => {
  try {
    const u = new URL(url);
    u.hash = '';
    u.search = '';
    return u.href;
  } catch {
    return '';
  }
};

// appUrl: the file URL of the built renderer. devUrl: the Vite dev server, development only.
export interface TrustedPages { appUrl: string; devUrl?: string }

export function isTrustedPage(url: string, pages: TrustedPages): boolean {
  const clean = stripHash(url);
  if (!clean) return false;
  if (clean === stripHash(pages.appUrl)) return true;
  if (pages.devUrl) {
    const dev = new URL(pages.devUrl);
    const u = new URL(clean);
    return u.origin === dev.origin;
  }
  return false;
}

// The app has a single page, so any navigation away from a trusted page is refused.
export const allowNavigation = isTrustedPage;
export const allowWindowOpen = (): false => false;

export const RENDERER_CSP_BUILT = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'";
