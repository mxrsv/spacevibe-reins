// Incremental, read-only line reader for JSONL logs. Remembers its byte offset, so a
// second read() only returns lines appended since the first. Ported from agent-world.
import { open } from 'node:fs/promises';
import { StringDecoder } from 'node:string_decoder';

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
