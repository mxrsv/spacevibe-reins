package logs

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"path/filepath"
	"testing"
	"time"
)

// Swift: ZstdStreamTests.swift "reads a file written by zlib.zstdCompressSync byte for byte"
func TestZstdSmallFromNode(t *testing.T) {
	got, err := ReadAllZstd(fixturePath("zst/small.jsonl.zst"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, fixture(t, "zst/small.jsonl")) {
		t.Fatal("decoded bytes differ from small.jsonl")
	}
}

// Swift: ZstdStreamTests.swift "reads a file written by the zstd command line tool (level 19)"
func TestZstdSmallFromCLI(t *testing.T) {
	plain := fixture(t, "zst/cli-made.jsonl")
	if len(plain) <= 30_000 {
		t.Fatalf("fixture too small: %d", len(plain))
	}
	got, err := ReadAllZstd(fixturePath("zst/cli-made.jsonl.zst"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, plain) {
		t.Fatal("decoded bytes differ from cli-made.jsonl")
	}
}

// Swift: ZstdStreamTests.swift "concatenated frames read as one stream"
func TestZstdConcatenatedFrames(t *testing.T) {
	small := fixture(t, "zst/small.jsonl")
	got, err := ReadAllZstd(fixturePath("zst/twice.jsonl.zst"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, append(append([]byte(nil), small...), small...)) {
		t.Fatal("twice.jsonl.zst is not small twice")
	}
}

// Swift: ZstdStreamTests.swift "a 5.5 MB stream decodes to identical bytes, in several chunks"
func TestZstdLarge(t *testing.T) {
	meta := largeMeta(t)
	s, err := OpenZstdStream(fixturePath("zst/large.jsonl.zst"), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	hash := sha256.New()
	total, chunks, newlines := 0, 0, 0
	err = s.ForEachChunk(func(chunk []byte) error {
		hash.Write(chunk)
		total += len(chunk)
		chunks++
		newlines += bytes.Count(chunk, []byte{'\n'})
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if total != meta.Bytes || total <= 5_000_000 {
		t.Errorf("bytes = %d, want %d (> 5000000)", total, meta.Bytes)
	}
	if got := hex.EncodeToString(hash.Sum(nil)); got != meta.SHA256 {
		t.Errorf("sha256 = %s, want %s", got, meta.SHA256)
	}
	if chunks <= 10 {
		t.Errorf("chunks = %d, want > 10", chunks)
	}
	if newlines != meta.Lines {
		t.Errorf("lines = %d, want %d", newlines, meta.Lines)
	}
}

// Swift: ZstdStreamTests.swift "a file cut inside a frame is reported as truncated"
func TestZstdTruncated(t *testing.T) {
	full := fixture(t, "zst/cli-made.jsonl.zst")
	cut := writeFile(t, t.TempDir(), "cut.zst", full[:len(full)/2])
	if _, err := ReadAllZstd(cut); !errors.Is(err, ErrTruncated) {
		t.Fatalf("err = %v, want ErrTruncated", err)
	}
}

// Swift: ZstdStreamTests.swift "garbage is reported as corrupt without quoting its content"
func TestZstdCorruptDoesNotQuote(t *testing.T) {
	secret := "do-not-quote-this-text"
	file := writeFile(t, t.TempDir(), "bad.zst", []byte(secret+string(bytes.Repeat([]byte("x"), 64))))
	_, err := ReadAllZstd(file)
	if !errors.Is(err, ErrCorrupt) {
		t.Fatalf("err = %v, want ErrCorrupt", err)
	}
	if bytes.Contains([]byte(err.Error()), []byte(secret)) {
		t.Fatalf("error quotes file content: %q", err)
	}
}

// Swift: ZstdStreamTests.swift "a missing file is cannotOpen"
func TestZstdMissingIsCannotOpen(t *testing.T) {
	if _, err := OpenZstdStream(fixturePath("zst/none.zst"), 0); !errors.Is(err, ErrCannotOpen) {
		t.Fatalf("err = %v, want ErrCannotOpen", err)
	}
}

// H5: klauspost's outcomes on cut and damaged streams map onto the CZstd outcomes the Swift tests expect
// (truncated inside a frame, corrupt for a bad frame), and the empty file is a clean end like Swift. Every row was also
// run through libzstd with the ZstdStream.swift loop (scratch C program): all agree except the stray-byte row below.
func TestZstdH5ErrorOutcomes(t *testing.T) {
	full := fixture(t, "zst/cli-made.jsonl.zst")
	small := fixture(t, "zst/small.jsonl.zst")
	cases := []struct {
		name  string
		input []byte
		want  error // nil: clean end of file
	}{
		{"empty file is a clean end", nil, nil},
		{"one byte of a magic number", full[:1], ErrTruncated},
		{"three bytes of a magic number", full[:3], ErrTruncated},
		{"magic number only", full[:4], ErrTruncated},
		{"magic and part of the header", full[:6], ErrTruncated},
		{"cut after a few bytes of the first block", full[:20], ErrTruncated},
		{"cut at one quarter", full[:len(full)/4], ErrTruncated},
		{"cut at half", full[:len(full)/2], ErrTruncated},
		{"missing the last byte", full[:len(full)-1], ErrTruncated},
		{"missing the last four bytes (the checksum)", full[:len(full)-4], ErrTruncated},
		{"second frame cut after its magic", append(append([]byte(nil), small...), small[:4]...), ErrTruncated},
		{"second frame cut mid-block", append(append([]byte(nil), small...), small[:len(small)/2]...), ErrTruncated},
		{"valid frame then garbage", append(append([]byte(nil), small...), []byte("trailing garbage here")...), ErrCorrupt},
		// Known difference: libzstd answers "Unknown frame descriptor" (corrupt) for 1 to 3 stray bytes that cannot start
		// a magic number; klauspost waits for the rest of a magic number and reports the end as truncated. Both are an
		// unreadable log, and Swift callers tell only ErrTooLarge apart (TailReader.swift:216,232).
		{"valid frame then one stray byte (libzstd: corrupt)", append(append([]byte(nil), small...), 0x00), ErrTruncated},
		{"damaged magic", append([]byte{0x29}, full[1:]...), ErrCorrupt},
		{"all zero bytes", make([]byte, 64), ErrCorrupt},
		{"reserved block type", append(append([]byte(nil), zstdHeader...), 0x07, 0x00, 0x00), ErrCorrupt},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s, err := newZstdStream(bytes.NewReader(c.input), 0)
			if err != nil {
				t.Fatalf("newZstdStream: %v", err)
			}
			defer s.Close()
			err = s.ForEachChunk(func([]byte) error { return nil })
			if c.want == nil {
				if err != nil {
					t.Fatalf("err = %v, want clean end", err)
				}
				return
			}
			if !errors.Is(err, c.want) {
				t.Fatalf("err = %v, want %v", err, c.want)
			}
		})
	}
}

// A flipped byte in the middle of the data: libzstd reports corrupt or a checksum failure; either is ErrCorrupt here.
func TestZstdDamagedBodyIsCorrupt(t *testing.T) {
	full := append([]byte(nil), fixture(t, "zst/cli-made.jsonl.zst")...)
	for i := len(full) / 3; i < len(full)/3+64; i++ {
		full[i] ^= 0xFF
	}
	s, err := newZstdStream(bytes.NewReader(full), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if err := s.ForEachChunk(func([]byte) error { return nil }); !errors.Is(err, ErrCorrupt) {
		t.Fatalf("err = %v, want ErrCorrupt", err)
	}
}

// Swift: ReadHardeningTests.swift "a small file that expands past the output cap throws tooLarge"
func TestZstdDecompressionCap(t *testing.T) {
	bomb := zstdRepeated(0x78, 4*1024*1024)
	if len(bomb) >= 200 {
		t.Fatalf("bomb is %d bytes", len(bomb))
	}
	file := writeFile(t, t.TempDir(), "bomb.jsonl.zst", bomb)
	s, err := OpenZstdStream(file, 1_000_000)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.ForEachChunk(func([]byte) error { return nil }); !errors.Is(err, ErrTooLarge) {
		t.Fatalf("err = %v, want ErrTooLarge", err)
	}
	s.Close()
	// Within the cap the same file reads fine.
	s, err = OpenZstdStream(file, 8*1024*1024)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	total := 0
	if err := s.ForEachChunk(func(c []byte) error { total += len(c); return nil }); err != nil {
		t.Fatal(err)
	}
	if total != 4*1024*1024 {
		t.Fatalf("total = %d", total)
	}
}

type diskError struct{}

func (diskError) Error() string { return "disk" }

// Swift: ReadHardeningTests.swift "an I/O error while reading the input is rethrown, not taken for the end of the file"
func TestZstdIOErrorRethrown(t *testing.T) {
	s, err := newZstdStream(readerFunc(func([]byte) (int, error) { return 0, diskError{} }), 0)
	if err == nil {
		defer s.Close()
		_, err = s.NextChunk()
	}
	if !errors.Is(err, diskError{}) {
		t.Fatalf("first source: err = %v, want the disk error", err)
	}

	good := zstdRaw([]byte("{\"a\":1}\n"))
	served := false
	flaky := readerFunc(func(p []byte) (int, error) {
		if served {
			return 0, diskError{}
		}
		served = true
		return copy(p, good[:len(good)-2]), nil
	})
	s, err = newZstdStream(flaky, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if err := s.ForEachChunk(func([]byte) error { return nil }); !errors.Is(err, diskError{}) {
		t.Fatalf("flaky source: err = %v, want the disk error (not truncated)", err)
	}
}

type readerFunc func([]byte) (int, error)

func (f readerFunc) Read(p []byte) (int, error) { return f(p) }

// Swift: ReadHardeningTests.swift "a stream whose size is an exact multiple of the output buffer is not reported as truncated"
func TestZstdExactBlockMultiple(t *testing.T) {
	file := writeFile(t, t.TempDir(), "aligned.jsonl.zst", zstdRepeated(0x78, 2*zstdBlockMax))
	s, err := OpenZstdStream(file, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	total := 0
	if err := s.ForEachChunk(func(c []byte) error { total += len(c); return nil }); err != nil {
		t.Fatal(err)
	}
	if total != 2*zstdBlockMax {
		t.Fatalf("total = %d", total)
	}
}

// A body error stops the stream and comes back unchanged; after a failure the stream keeps failing the same way.
func TestZstdBodyErrorAndStickyFailure(t *testing.T) {
	stop := errors.New("stop")
	s, err := OpenZstdStream(fixturePath("zst/small.jsonl.zst"), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if err := s.ForEachChunk(func([]byte) error { return stop }); err != stop {
		t.Fatalf("err = %v, want the body error", err)
	}

	cut := writeFile(t, t.TempDir(), "cut.zst", fixture(t, "zst/cli-made.jsonl.zst")[:100])
	s2, err := OpenZstdStream(cut, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer s2.Close()
	_ = s2.ForEachChunk(func([]byte) error { return nil })
	if _, err := s2.NextChunk(); !errors.Is(err, ErrTruncated) {
		t.Fatalf("second call: err = %v, want ErrTruncated", err)
	}
}

func TestZstdEndIsEOF(t *testing.T) {
	s, err := OpenZstdStream(fixturePath("zst/small.jsonl.zst"), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	for {
		if _, err := s.NextChunk(); err != nil {
			if err != io.EOF {
				t.Fatalf("err = %v, want io.EOF", err)
			}
			break
		}
	}
	if _, err := s.NextChunk(); err != io.EOF {
		t.Fatalf("after the end: err = %v, want io.EOF again", err)
	}
}

// Swift: ReadHardeningTests.swift "the default cap stops a 600 MB expansion for the reader, and a second poll of the
// same file fails at once" (the reader half is in compressed-log-reader_test.go).
func TestZstdDefaultCapStopsSixHundredMegabytes(t *testing.T) {
	file := writeFile(t, t.TempDir(), "bomb.jsonl.zst", zstdRepeated(0x78, 600*1024*1024))
	start := time.Now()
	_, err := drainZstd(t, file)
	if !errors.Is(err, ErrTooLarge) {
		t.Fatalf("err = %v, want ErrTooLarge", err)
	}
	t.Logf("600 MB bomb refused in %s", time.Since(start))
}

// drainZstd drains the stream with the default cap without keeping the bytes.
func drainZstd(t *testing.T, path string) (int, error) {
	t.Helper()
	s, err := OpenZstdStream(path, 0)
	if err != nil {
		return 0, err
	}
	defer s.Close()
	total := 0
	err = s.ForEachChunk(func(c []byte) error { total += len(c); return nil })
	return total, err
}

func TestZstdDirectoryIsCannotOpen(t *testing.T) {
	if _, err := OpenZstdStream(filepath.Dir(fixturePath("zst/small.jsonl.zst")), 0); !errors.Is(err, ErrCannotOpen) {
		t.Fatalf("err = %v, want ErrCannotOpen", err)
	}
}
