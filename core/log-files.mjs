// Finding and opening session logs. Older Codex rollouts sit on disk as `.jsonl.zst`, so a reader that
// only knows `.jsonl` silently loses most of a machine's Codex history.
import { createReadStream, readdirSync } from 'node:fs';
import { basename, join } from 'node:path';
import { pipeline } from 'node:stream';
import { createZstdDecompress } from 'node:zlib';

const LOG_FILE = /\.jsonl(\.zstd?)?$/;
const READ_CHUNK = 1 << 20;

export const isCompressedLog = (path) => /\.zstd?$/.test(path);

/** File name without `.jsonl` or `.jsonl.zst`, so both forms of one session share a name. */
export const logBaseName = (path) => basename(path).replace(LOG_FILE, '');

/** Every log under dir. When a log exists in both forms, only the plain one is listed: it is the one still written. */
export function walkLogs(dir, out = []) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  const names = new Set(entries.map((e) => e.name));
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walkLogs(p, out);
    else if (e.isFile() && LOG_FILE.test(e.name) && !(isCompressedLog(e.name) && names.has(`${logBaseName(e.name)}.jsonl`))) out.push(p);
  }
  return out;
}

/** The log's text as a stream of utf8 chunks. A read or decompression failure surfaces on the stream. */
export function openLogText(path) {
  if (!isCompressedLog(path)) return createReadStream(path, { encoding: 'utf8', highWaterMark: READ_CHUNK });
  const text = createZstdDecompress();
  pipeline(createReadStream(path, { highWaterMark: READ_CHUNK }), text, () => {}); // the error reaches whoever reads `text`
  text.setEncoding('utf8');
  return text;
}
