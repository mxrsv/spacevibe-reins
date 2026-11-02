// Session titles and project names. Pure helpers plus a read-only `.git` lookup.
import { readFileSync, statSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, resolve } from 'node:path';

const TITLE_MAX = 80;
const WORKTREE_CLAUDE = /^(.*)[\\/]\.claude[\\/]worktrees[\\/][^\\/]+(?:[\\/].*)?$/;
const WORKTREE_CODEX = /[\\/]\.codex[\\/]worktrees[\\/][^\\/]+[\\/]([^\\/]+)(?:[\\/].*)?$/;
const GITDIR_WORKTREE = /^(.*)[\\/]\.git[\\/]worktrees[\\/][^\\/]+$/;

const squash = (s) => String(s ?? '').replace(/\s+/g, ' ').trim();

/** True for text that is not a title: empty, slash command, lifecycle or caveat text. */
export function isJunkTitle(text) {
  const t = squash(text);
  if (t.length < 2 || !/[\p{L}\p{N}]/u.test(t)) return true;
  if (/^\/[\w:-]+(\s|$)/.test(t)) return true; // "/clear", "/model opus"
  if (t.startsWith('<') || /<command-name>|<local-command|<system-reminder|<task-notification/.test(t)) return true;
  if (/^caveat:/i.test(t) || /^\[request interrupted/i.test(t)) return true;
  if (/^# AGENTS\.md instructions/i.test(t)) return true;
  return /^(warmup|untitled|new session|no title|claude session|codex session)$/i.test(t);
}

export const cleanTitle = (text) => {
  const t = squash(text);
  return t.length > TITLE_MAX ? `${t.slice(0, TITLE_MAX - 1)}…` : t;
};

/** First candidate that is not junk, else "YYYY-MM-DD · short id". Candidates are tried in order. */
export function pickTitle(candidates, { startedAt, id }) {
  for (const c of candidates) if (typeof c === 'string' && !isJunkTitle(c)) return cleanTitle(c);
  const day = Number.isFinite(startedAt) ? new Date(startedAt).toISOString().slice(0, 10) : 'unknown date';
  return `${day} · ${String(id ?? '').slice(0, 8)}`;
}

// Main repo name when cwd (or a parent) is a linked worktree, whose `.git` is a pointer file.
// A `.git` directory means a normal checkout: null, so the caller keeps basename(cwd).
function worktreeRepo(cwd, depth = 12) {
  let dir = cwd;
  for (let i = 0; i < depth; i++) {
    let st;
    try { st = statSync(join(dir, '.git')); } catch { st = null; }
    if (st?.isDirectory()) return null;
    if (st?.isFile()) {
      let text = '';
      try { text = readFileSync(join(dir, '.git'), 'utf8'); } catch { /* unreadable pointer: treat dir as the repo */ }
      const gitdir = /^gitdir:\s*(.+)$/m.exec(text)?.[1]?.trim();
      const main = gitdir && GITDIR_WORKTREE.exec(isAbsolute(gitdir) ? gitdir : resolve(dir, gitdir))?.[1];
      return basename(main || dir);
    }
    const up = dirname(dir);
    if (up === dir) return null;
    dir = up;
  }
  return null;
}

/**
 * Repo name for a working directory; a git worktree slug is never returned.
 * Order: hint (the original cwd Claude records for a worktree) -> `.claude/worktrees/<slug>` and
 * `.codex/worktrees/<id>/<repo>` path layouts -> `.git` pointer file on disk -> basename.
 */
export function projectName(cwd, { hint = null } = {}, memo = new Map()) {
  if (typeof cwd !== 'string' || !cwd) return null;
  const key = `${cwd}\0${hint ?? ''}`;
  if (memo.has(key)) return memo.get(key);
  let name = hint ? projectName(hint, {}, memo) : null;
  if (!name) {
    const claude = WORKTREE_CLAUDE.exec(cwd)?.[1];
    name = claude ? basename(claude) : WORKTREE_CODEX.exec(cwd)?.[1] ?? null;
  }
  name ??= worktreeRepo(cwd);
  name ??= basename(cwd) || cwd;
  memo.set(key, name);
  return name;
}
