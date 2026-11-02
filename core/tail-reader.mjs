// Incremental, read-only line reader for JSONL logs. Remembers its byte offset, so a
// second read() only returns lines appended since the first. Ported from agent-world.
import { open, stat as statFile } from 'node:fs/promises';
import { StringDecoder } from 'node:string_decoder';
import { openLogText } from './log-files.mjs';

const CHUNK_BYTES = 256 * 1024;
const MAX_LINE_CHARS = 16 * 1024 * 1024;

export class TailReader {
  /** @param {string} path @param {{ maxBytes?: number }} [opts] maxBytes: on the first read of a larger file, start that many bytes before the end. */
  constructor(path, { maxBytes = Infinity } = {}) {
    this.path = path;
    this.maxBytes = maxBytes;
    this.reset();
  }

  reset() {
    this.offset = 0;
    this.identity = null;
    this.partial = '';
    this.decoder = new StringDecoder('utf8');
    this.skipping = false;
    this.truncated = false;
  }

  /**
   * Calls onLine(line) for each complete non-empty line not yet seen.
   * onReset() fires when the file was replaced or shrank and reading restarts at 0.
   * @returns {Promise<{ missing?: true, size?: number, mtimeMs?: number, truncated?: boolean }>}
   */
  async read(onLine, onReset = () => {}) {
    let handle;
    try {
      handle = await open(this.path, 'r');
      const stat = await handle.stat();
      const identity = `${stat.dev}:${stat.ino}`;
      if ((this.identity && identity !== this.identity) || stat.size < this.offset) {
        this.reset();
        onReset();
      }
      this.identity = identity;
      if (this.offset === 0 && stat.size > this.maxBytes) {
        // Start inside the file: the first partial line is dropped.
        this.offset = stat.size - this.maxBytes;
        this.skipping = true;
        this.truncated = true;
      }
      const buffer = Buffer.allocUnsafe(CHUNK_BYTES);
      while (this.offset < stat.size) {
        const { bytesRead } = await handle.read(buffer, 0, Math.min(CHUNK_BYTES, stat.size - this.offset), this.offset);
        if (!bytesRead) break;
        this.offset += bytesRead;
        const lines = (this.partial + this.decoder.write(buffer.subarray(0, bytesRead))).split('\n');
        this.partial = lines.pop();
        for (const line of lines) {
          if (this.skipping) { this.skipping = false; continue; }
          if (line.trim()) onLine(line);
        }
        if (this.partial.length > MAX_LINE_CHARS) { this.partial = ''; this.skipping = true; }
      }
      return { size: stat.size, mtimeMs: stat.mtimeMs, truncated: this.truncated };
    } catch (error) {
      if (error.code === 'ENOENT') return { missing: true };
      throw error;
    } finally {
      await handle?.close();
    }
  }
}

/**
 * Same read() as TailReader for a compressed log. It cannot seek or be appended to, so it reads the file once, and
 * again only if the file changes. maxBytes keeps the last lines of that size, as TailReader does by starting late.
 */
export class CompressedLogReader {
  /** @param {string} path @param {{ maxBytes?: number }} [opts] */
  constructor(path, { maxBytes = Infinity } = {}) {
    this.path = path;
    this.maxBytes = maxBytes;
    this.stamp = null;
    this.truncated = false;
  }

  async read(onLine, onReset = () => {}) {
    let st;
    try { st = await statFile(this.path); } catch (error) {
      if (error.code === 'ENOENT') return { missing: true };
      throw error;
    }
    const result = (truncated) => ({ size: st.size, mtimeMs: st.mtimeMs, truncated });
    const stamp = `${st.dev}:${st.ino}:${st.size}:${st.mtimeMs}`;
    if (stamp === this.stamp) return result(this.truncated);
    if (this.stamp) onReset();

    const kept = [];
    let keptChars = 0;
    let truncated = false;
    const keep = (line) => {
      if (!line.trim()) return;
      kept.push(line);
      keptChars += line.length;
      while (keptChars > this.maxBytes && kept.length > 1) { keptChars -= kept.shift().length; truncated = true; }
    };
    let partial = '';
    for await (const chunk of openLogText(this.path)) {
      const lines = (partial + chunk).split('\n');
      partial = lines.pop();
      lines.forEach(keep);
      if (partial.length > MAX_LINE_CHARS) { partial = ''; truncated = true; }
    }
    keep(partial);
    kept.forEach(onLine);
    this.stamp = stamp;
    this.truncated = truncated;
    return result(truncated);
  }
}
