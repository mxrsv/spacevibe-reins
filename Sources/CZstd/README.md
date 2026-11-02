# CZstd

Decompress-only copy of zstd, used by `ReinsCore` to read Codex `.jsonl.zst` rollouts. macOS 15 ships no usable zstd
(no `libzstd` in `/usr/lib`, no zstd header in the SDK, no zstd algorithm in the Compression framework), and the Mac
Homebrew copy is not guaranteed on a clean machine, so it is vendored.

- Version: zstd 1.5.7
- Source: https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz
- SHA-256 of that tarball: `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3` (matches the release's `.sha256` asset)
- License: BSD-3-Clause (the `LICENSE` file; `COPYING` is the GPLv2 alternative offered by upstream and is not used, zstd is
  dual-licensed and Reins takes the BSD option). Both files are kept as shipped.

Files are unmodified copies of upstream `lib/`:

- `zstd.h`, `zstd_errors.h`
- `common/`: all except `pool.*` and `threading.*` (multithreaded compression only)
- `decompress/`: all except `huf_decompress_amd64.S` (assembly fast path, disabled with `ZSTD_DISABLE_ASM=1` in `Package.swift`)

`include/CZstd.h` is the only file written here: the umbrella header SwiftPM needs. To update, replace the files from a new
release tarball and change the version and checksum above.
