package logs

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// fixture reads a frozen golden under core/testdata/fixtures (never edited).
func fixture(t *testing.T, relative string) []byte {
	t.Helper()
	data, err := os.ReadFile(fixturePath(relative))
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func fixturePath(relative string) string {
	return filepath.Join("..", "..", "testdata", "fixtures", filepath.FromSlash(relative))
}

// writeFile writes content under dir, creating parents, and returns the path.
func writeFile(t *testing.T, dir, relative string, content []byte) string {
	t.Helper()
	path := filepath.Join(dir, filepath.FromSlash(relative))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, content, 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

// resolvedTempDir is t.TempDir() with symlinks resolved, like Swift's TempHome root.
func resolvedTempDir(t *testing.T) string {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return dir
}

type zstdMeta struct {
	Bytes  int    `json:"bytes"`
	Lines  int    `json:"lines"`
	SHA256 string `json:"sha256"`
}

func largeMeta(t *testing.T) zstdMeta {
	t.Helper()
	var meta zstdMeta
	if err := json.Unmarshal(fixture(t, "zst/large.meta.json"), &meta); err != nil {
		t.Fatal(err)
	}
	return meta
}

// zstdFrame builds a zstd frame by hand from raw and RLE blocks, so a test can make a tiny file that expands to
// hundreds of MB, or a stream of many short lines, without a compressor. Block layout: RFC 8878 section 3.1.1.2.
const zstdBlockMax = 128 * 1024

// Magic, then a descriptor with no checksum, dictionary or content size, then a 512 KB window.
var zstdHeader = []byte{0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x48}

func zstdBlockHeader(blockType uint32, size int, last bool) []byte {
	value := blockType<<1 | uint32(size)<<3
	if last {
		value |= 1
	}
	return []byte{byte(value), byte(value >> 8), byte(value >> 16)}
}

// zstdRepeated is total bytes of b, as RLE blocks of 1 byte each.
func zstdRepeated(b byte, total int) []byte {
	out := append([]byte(nil), zstdHeader...)
	for left := total; left > 0; {
		size := min(left, zstdBlockMax)
		left -= size
		out = append(out, zstdBlockHeader(1, size, left == 0)...)
		out = append(out, b)
	}
	return out
}

// zstdRaw is content stored as raw blocks.
func zstdRaw(content []byte) []byte {
	out := append([]byte(nil), zstdHeader...)
	offset := 0
	for {
		size := min(len(content)-offset, zstdBlockMax)
		end := offset + size
		out = append(out, zstdBlockHeader(0, size, end == len(content))...)
		out = append(out, content[offset:end]...)
		offset = end
		if offset >= len(content) {
			return out
		}
	}
}
