// The only place Activity touches the operating system: ps, lsof and kill -0. Everything it
// returns is read-only information. Tests inject a fake with the same shape instead.
//
//   proc = {
//     alive(pid): boolean | Promise<boolean>,
//     startOf(pid): string | null | Promise<string | null>,   // UTC `ps lstart`, same text as a Claude status file `procStart`
//     codexThreads(): Promise<Array<{ pid: number, threadId: string | null }>>,
//   }
//
// codexThreads lists live `codex` processes with the thread each one holds a writer lock on.
// threadId is null for a live process with no lock open (the "before the first prompt" case).
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);
const LOCK_RE = /[\\/]thread-writer-locks[\\/]([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.lock$/;
// ps compares against Claude's procStart, which is written in UTC.
const PS_ENV = { ...process.env, TZ: 'UTC', LC_ALL: 'C' };

/** `ps -axo pid=,args=` output -> pids of interactive-looking codex processes. */
export function parseCodexPids(stdout) {
  const pids = [];
  for (const line of stdout.split('\n')) {
    const m = /^\s*(\d+)\s+(?:\S*\/)?codex(?:\s+(.*))?$/.exec(line);
    // app-server and mcp-server are helpers, not sessions.
    if (m && !/(^|\s)(app-server|mcp-server)(\s|$)/.test(m[2] ?? '')) pids.push(Number(m[1]));
  }
  return pids;
}

/** `lsof -Fpn` output -> one entry per (pid, thread lock). */
export function parseLockFds(stdout) {
  const out = [];
  let pid = null;
  for (const line of stdout.split('\n')) {
    if (line.startsWith('p')) pid = Number(line.slice(1));
    else if (line.startsWith('n') && pid != null) {
      const m = LOCK_RE.exec(line.slice(1));
      if (m) out.push({ pid, threadId: m[1] });
    }
  }
  return out;
}

export function isAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; } catch (error) { return error.code === 'EPERM'; }
}

export function systemProc() {
  return {
    alive: isAlive,
    async startOf(pid) {
      try {
        const { stdout } = await run('ps', ['-o', 'lstart=', '-p', String(pid)], { env: PS_ENV, timeout: 3000 });
        return stdout.trim() || null;
      } catch { return null; }
    },
    async codexThreads() {
      let pids;
      try {
        const { stdout } = await run('ps', ['-axo', 'pid=,args='], { env: PS_ENV, timeout: 5000, maxBuffer: 8 * 1024 * 1024 });
        pids = parseCodexPids(stdout);
      } catch { return []; }
      if (!pids.length) return [];
      let locks = [];
      try {
        const { stdout } = await run('lsof', ['-nP', '-Fpn', '-p', pids.join(',')], { timeout: 5000, maxBuffer: 16 * 1024 * 1024 });
        locks = parseLockFds(stdout);
      } catch (error) {
        if (typeof error.stdout === 'string') locks = parseLockFds(error.stdout); // lsof exits 1 when some pids are gone
      }
      const held = new Set(locks.map((l) => l.pid));
      return [...locks, ...pids.filter((pid) => !held.has(pid)).map((pid) => ({ pid, threadId: null }))];
    },
  };
}
