// Writes the test fixtures of the Swift core from the Node core (the oracle until plan S8.3).
//
//   node scripts/make-golden.mjs              every section
//   node scripts/make-golden.mjs inventory    only the named sections
//
// Output, all under Tests/ReinsCoreTests/Fixtures/ (synthetic only, AGENTS.md R2):
//   home/              the synthetic HOME from scripts/fixture-home.mjs; absolute paths are written as $HOME
//   manifest.json      fixed "now", every file's mtime and a content digest (git does not keep mtimes)
//   golden/<name>.json what the Node core returns for that tree, absolute paths as $HOME
//   zst/               .jsonl.zst files for the zstd reader tests
//
// How the Swift tests use it: Tests/ReinsCoreTests/Support/FixtureHome.swift copies home/ to CANONICAL_ROOT, replaces
// $HOME with that path and applies the manifest mtimes. This script materializes the same way and runs the Node core on
// it, so both sides read identical bytes at an identical path. The path is fixed because ids are hashes of paths
// (hook ids, project ids): a golden made at a random temp path could never match.
//
// Adding a section (usage, rules, activity, ...): write `async function name(ctx)` that reads `await ctx.home()`
// (the materialized HOME with its roots) and calls `ctx.writeGolden('name', value)`, then add it to SECTIONS.
// Golden values must be plain JSON; order-insensitive lists should be sorted here so reruns give no diff.
import { createHash } from 'node:crypto';
import {
  existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, statSync, utimesSync, writeFileSync,
} from 'node:fs';
import { tmpdir, userInfo } from 'node:os';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { zstdCompressSync } from 'node:zlib';
import { attachUsage, filterCounts, readInventory, roots } from '../core/inventory.mjs';
import { scan } from '../core/usage.mjs';
import { writeFixtureHome } from './fixture-home.mjs';

const REPO = resolve(import.meta.dirname, '..');
const FIXTURES = join(REPO, 'Tests/ReinsCoreTests/Fixtures');
const TOKEN = '$HOME';
const NOW = Date.parse('2026-11-02T12:00:00Z');
// Keep in step with FixtureHome.root in the Swift tests. /private/tmp is what /tmp resolves to on macOS.
export const CANONICAL_ROOT = '/private/tmp/reins-fixture-home';
const ZST_SEED = 20261102;

const walk = (dir, out = []) => {
  for (const e of readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.isFile() && e.name !== '.DS_Store') out.push(p);
  }
  return out;
};
const put = (path, data) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, data); };
const json = (v) => `${JSON.stringify(v, null, 2)}\n`;

// ---- tree: build the synthetic HOME, store it with $HOME placeholders and a manifest ----------------------------

async function tree() {
  const build = mkdtempSync(join(tmpdir(), 'reins-golden-build-'));
  for (const key of Object.keys(process.env)) if (key.startsWith('REINS_FIXTURE_')) delete process.env[key];
  const started = Date.now();
  let source;
  try {
    source = writeFixtureHome(join(build, 'home'), { now: NOW }).dir;
    const home = resolve(FIXTURES, 'home');
    if (!home.startsWith(`${FIXTURES}${sep}`)) throw new Error('refusing to replace a folder outside the fixtures');
    rmSync(home, { recursive: true, force: true });

    const mtimes = {};
    const digest = createHash('sha256');
    const leaks = [userInfo().homedir, userInfo().username].filter((s) => s && s.length > 3);
    for (const file of walk(source)) {
      const rel = relative(source, file);
      const text = readFileSync(file, 'utf8');
      if (text.includes(TOKEN)) throw new Error(`${rel} already contains ${TOKEN}`);
      const out = text.replaceAll(source, TOKEN);
      if (leaks.some((s) => out.includes(s))) throw new Error(`${rel} contains the real home or user name`);
      put(join(home, rel), out);
      // Files written during this run and not backdated by fixture-home get "now - 1 hour": recent, and stable.
      const mtime = statSync(file).mtimeMs;
      mtimes[rel] = mtime >= started - 1000 ? NOW - 3_600_000 : mtime;
      digest.update(`${rel}\0${out}\0${mtimes[rel]}\0`);
    }
    writeFileSync(join(FIXTURES, 'manifest.json'), json({ now: NOW, token: TOKEN, digest: digest.digest('hex'), mtimes }));
    console.log(`tree: ${Object.keys(mtimes).length} files`);
  } finally {
    rmSync(build, { recursive: true, force: true });
  }
}

// ---- materialize: the same steps as FixtureHome.materialize in Swift -------------------------------------------

let materialized;
async function home() {
  materialized ??= (() => {
    if (CANONICAL_ROOT !== '/private/tmp/reins-fixture-home') throw new Error('unexpected canonical root');
    const manifest = JSON.parse(readFileSync(join(FIXTURES, 'manifest.json'), 'utf8'));
    const stampOf = (dir) => { try { return readFileSync(join(dir, '.fixture-stamp'), 'utf8'); } catch { return null; } };
    // Reuse a tree that is already current: the Swift tests read the same folder, so it is replaced only when the
    // fixtures changed, and then by a rename of a finished sibling folder, never by building in place.
    if (stampOf(CANONICAL_ROOT) !== manifest.digest) {
      const staging = mkdtempSync('/private/tmp/reins-fixture-home-');
      for (const [rel, mtime] of Object.entries(manifest.mtimes)) {
        const target = join(staging, rel);
        put(target, readFileSync(join(FIXTURES, 'home', rel), 'utf8').replaceAll(TOKEN, CANONICAL_ROOT));
        utimesSync(target, new Date(mtime), new Date(mtime));
      }
      mkdirSync(join(staging, '.reins'), { recursive: true });
      writeFileSync(join(staging, '.fixture-stamp'), manifest.digest);
      if (existsSync(CANONICAL_ROOT)) {
        if (lstatSync(CANONICAL_ROOT).isSymbolicLink()) throw new Error(`${CANONICAL_ROOT} is a symlink`);
        rmSync(CANONICAL_ROOT, { recursive: true, force: true });
      }
      renameSync(staging, CANONICAL_ROOT);
    }
    // The data folder is separate on purpose: the Node scan writes usage-cache.json there.
    const data = mkdtempSync(join(tmpdir(), 'reins-golden-data-'));
    const r = roots({ HOME: CANONICAL_ROOT, CLAUDE_CONFIG_DIR: join(CANONICAL_ROOT, '.claude'), CODEX_HOME: join(CANONICAL_ROOT, '.codex'), REINS_HOME: data, REINS_TEST: '1' });
    return { root: CANONICAL_ROOT, data, r, now: manifest.now };
  })();
  return materialized;
}

const normalize = (value) => JSON.parse(JSON.stringify(value).replaceAll(CANONICAL_ROOT, TOKEN));
const byId = (a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

function writeGolden(name, value) {
  put(join(FIXTURES, 'golden', `${name}.json`), json(normalize(value)));
  console.log(`golden: ${name}.json`);
}

// ---- sections ---------------------------------------------------------------------------------------------------

// readInventory + attachUsage, with the usage input and the filter counts. items and hooks are sorted by id:
// the directory order of readdir is not part of the contract.
async function inventory(ctx) {
  const h = await ctx.home();
  const inv = readInventory(h.r);
  const scanned = await scan(h.r);
  const usageInput = { state: 'ready', totals: scanned.totals, windows: scanned.windows };
  const attached = attachUsage(inv, usageInput, { now: h.now });
  attached.items.sort(byId);
  attached.hooks.sort(byId);
  ctx.writeGolden('inventory', {
    now: h.now,
    usageInput,
    inventory: attached,
    filterCounts: filterCounts([...attached.items, ...attached.hooks]),
  });
}

// .jsonl.zst files for the zstd reader. Written by zlib.zstdCompressSync, so a Swift read proves a second implementation
// agrees with libzstd. cli-made.jsonl.zst is the one file made by the `zstd` command line tool (v1.5.7, level 19) and
// committed as is; this script does not regenerate it.
async function zstd() {
  const dir = join(FIXTURES, 'zst');
  mkdirSync(dir, { recursive: true });
  const small = `${[
    JSON.stringify({ timestamp: '2026-11-02T08:00:00.000Z', type: 'session_meta', payload: { id: 'fixture-zst', cwd: '/work/demo' } }),
    JSON.stringify({ type: 'event_msg', payload: { message: 'Xin chào, “quotes”, tab\there, emoji 🙂, backslash \\' } }),
    JSON.stringify({ type: 'event_msg', payload: { message: 'last line without a second newline' } }),
  ].join('\n')}\n`;
  put(join(dir, 'small.jsonl'), small);
  put(join(dir, 'small.jsonl.zst'), zstdCompressSync(small));
  put(join(dir, 'twice.jsonl.zst'), Buffer.concat([zstdCompressSync(small), zstdCompressSync(small)]));

  // 5.5 MB of lines with a fixed phrase and three words from a small vocabulary: it compresses to a few hundred KB
  // but spans many 128 KB blocks, so lines cross chunk boundaries.
  const words = ['alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel'];
  const phrase = 'a synthetic rollout record that only exists to make the stream long enough to need many decoder blocks '.repeat(2);
  let state = ZST_SEED;
  const next = () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state; };
  const lines = [];
  let bytes = 0;
  for (let i = 0; bytes < 5.5 * 1024 * 1024; i++) {
    const line = JSON.stringify({ i, note: phrase, w: Array.from({ length: 3 }, () => words[next() >>> 29]).join(' ') });
    lines.push(line);
    bytes += line.length + 1;
  }
  const large = Buffer.from(`${lines.join('\n')}\n`);
  put(join(dir, 'large.jsonl.zst'), zstdCompressSync(large));
  put(join(dir, 'large.meta.json'), json({ bytes: large.length, lines: lines.length, sha256: createHash('sha256').update(large).digest('hex') }));
  console.log(`zst: large ${large.length} bytes`);
}

const SECTIONS = { tree, zstd, inventory };

const requested = process.argv.slice(2);
const unknown = requested.filter((n) => !(n in SECTIONS));
if (unknown.length) { console.error(`Unknown section: ${unknown.join(', ')}. Sections: ${Object.keys(SECTIONS).join(', ')}`); process.exit(2); }
const ctx = { home, writeGolden, now: NOW };
for (const name of requested.length ? requested : Object.keys(SECTIONS)) await SECTIONS[name](ctx);
