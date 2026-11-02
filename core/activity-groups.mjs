// Turns per-log states into the two cross-session lists of the Activity tab: failures and files.
import { editsOf, hookHash } from './activity-fold.mjs';

const iso = (ms) => (Number.isFinite(ms) && ms > 0 ? new Date(ms).toISOString() : null);
const TITLE_MAX = 120;
const title = (cmd) => (cmd.length > TITLE_MAX ? `${cmd.slice(0, TITLE_MAX - 1)}…` : cmd);

/**
 * @param {Array<{ st: object, session: string, project: string|null }>} logs
 * Failures group by CLI plus command (hooks by CLI plus hook hash). `laterPass` is the first
 * passing run of the same command after the group's last failure, or null. It is a timestamp
 * only: a later pass does not say the failure was fixed.
 */
export function groupFailures(logs, { limit = 200 } = {}) {
  const groups = new Map();
  const seen = new Set();
  const add = (cli, gkey, base, ev, session, project) => {
    const dedupe = `${cli}|${ev.id}`;
    if (seen.has(dedupe)) return; // forked or resumed logs repeat earlier events
    seen.add(dedupe);
    let g = groups.get(gkey);
    if (!g) { g = { ...base, cli, count: 0, exit: null, reason: '', projects: new Set(), sessions: new Set(), firstAt: Infinity, lastAt: 0 }; groups.set(gkey, g); }
    g.count++;
    g.sessions.add(session);
    if (project) g.projects.add(project);
    g.firstAt = Math.min(g.firstAt, ev.at);
    if (ev.at >= g.lastAt) { g.lastAt = ev.at; g.exit = ev.exit; g.reason = ev.reason; }
  };
  for (const { st, session, project } of logs) {
    for (const f of st.failures) add(st.cli, `${st.cli}|cmd|${f.key}`, { kind: 'command', key: f.key, title: title(f.cmd), hook: null }, f, session, project);
    for (const h of st.hookFailures) {
      const hash = hookHash(h.event, h.command);
      add(st.cli, `${st.cli}|hook|${hash}`, { kind: 'hook', key: hash, title: title(h.command), hook: { hash, event: h.event } }, h, session, project);
    }
  }
  const passes = new Map(); // `${cli}|${key}` -> pass times
  for (const { st } of logs) {
    for (const [key, list] of st.passes) {
      const k = `${st.cli}|cmd|${key}`;
      if (groups.has(k)) passes.set(k, [...(passes.get(k) ?? []), ...list]);
    }
  }
  return [...groups.entries()]
    .map(([gkey, g]) => ({
      kind: g.kind, cli: g.cli, key: g.key, title: g.title, count: g.count, exit: g.exit, reason: g.reason,
      projects: [...g.projects].sort(), sessions: g.sessions.size, first: iso(g.firstAt), last: iso(g.lastAt),
      laterPass: iso(Math.min(...(passes.get(gkey) ?? []).filter((t) => t > g.lastAt), Infinity)),
      hook: g.hook,
    }))
    .sort((a, b) => (b.last ?? '').localeCompare(a.last ?? '') || b.count - a.count)
    .slice(0, limit);
}

/** Shortest path suffix that no other path in the list shares. */
export function shortestLabels(paths) {
  const segs = paths.map((p) => p.split(/[\\/]/).filter(Boolean));
  const counts = [];
  const suffix = (parts, k) => parts.slice(-k).join('/');
  const countsFor = (k) => {
    if (!counts[k]) {
      const m = new Map();
      for (const parts of segs) if (parts.length >= k) m.set(suffix(parts, k), (m.get(suffix(parts, k)) ?? 0) + 1);
      counts[k] = m;
    }
    return counts[k];
  };
  return segs.map((parts, i) => {
    for (let k = 1; k <= parts.length; k++) if (countsFor(k).get(suffix(parts, k)) === 1) return suffix(parts, k);
    return paths[i];
  });
}

/** File history across logs; `label` is the shortest suffix that still tells two files apart. */
export function groupFiles(logs, { limit = 300 } = {}) {
  const files = new Map();
  const seen = new Set();
  for (const { st, session, project } of logs) {
    for (const e of editsOf(st)) {
      if (seen.has(e.id)) continue;
      seen.add(e.id);
      let f = files.get(e.path);
      if (!f) { f = { path: e.path, edits: 0, sessions: new Set(), clis: new Set(), projects: new Set(), lastAt: 0 }; files.set(e.path, f); }
      f.edits++;
      f.sessions.add(session);
      f.clis.add(st.cli);
      if (project) f.projects.add(project);
      f.lastAt = Math.max(f.lastAt, e.at);
    }
  }
  const rows = [...files.values()].sort((a, b) => b.lastAt - a.lastAt).slice(0, limit);
  const labels = shortestLabels(rows.map((f) => f.path));
  return rows.map((f, i) => ({
    path: f.path, label: labels[i], edits: f.edits, sessions: f.sessions.size, last: iso(f.lastAt),
    clis: [...f.clis].sort(), projects: [...f.projects].sort(),
  }));
}
