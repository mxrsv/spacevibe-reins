package goldentest

import (
	"bytes"
	"errors"
	"io/fs"
	"os"
	"os/user"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/klauspost/compress/zstd"

	"spacevibe.dev/core/internal/roots"
)

// leakNeedleMinLength drops needles too short to mean anything ("/", a one-letter account).
const leakNeedleMinLength = 4

// maxLeakFileBytes bounds how much of one file (or one decompressed .zst) the scan reads.
const maxLeakFileBytes = 256 << 20

// LeakNeedles are the strings that must not appear under core/testdata (S-R2): the account's real home from the
// password database (not $HOME, which a test may have changed), its user name, the macOS per-user temp
// root and the /Users/ prefix. It fails when the real home cannot be read, because a scan without it would
// pass silently.
func LeakNeedles() ([]string, error) {
	home, err := roots.RealHome()
	if err != nil {
		return nil, err
	}
	needles := []string{home, "/var/folders", "/Users/"}
	if uid := os.Getuid(); uid >= 0 {
		if u, err := user.LookupId(strconv.Itoa(uid)); err == nil {
			needles = append(needles, u.Username)
		}
	}
	if u, err := user.Current(); err == nil {
		needles = append(needles, u.Username)
	}
	var out []string
	seen := map[string]bool{}
	for _, n := range needles {
		if len(n) >= leakNeedleMinLength && !seen[n] {
			seen[n] = true
			out = append(out, n)
		}
	}
	return out, nil
}

// FindLeaks scans every file under root, and the decompressed bytes of every .zst, for each needle, and also
// scans the file names. It returns one line per hit, naming the file (relative to root) and the needle's
// index, never the surrounding content. An unreadable file is itself reported, so it cannot hide a leak.
func FindLeaks(root string, needles []string) ([]string, error) {
	var hits []string
	scan := func(rel, what string, data []byte) {
		for i, n := range needles {
			if bytes.Contains(data, []byte(n)) {
				hits = append(hits, rel+" ("+what+" contains needle #"+strconv.Itoa(i)+")")
			}
		}
	}
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		rel, _ := filepath.Rel(root, path)
		if err != nil {
			hits = append(hits, rel+" (unreadable)")
			return nil
		}
		scan(rel, "name", []byte(rel))
		if d.IsDir() {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			hits = append(hits, rel+" (unreadable)")
			return nil
		}
		scan(rel, "bytes", data)
		if strings.HasSuffix(rel, ".zst") {
			plain, err := decompress(data)
			if err != nil {
				hits = append(hits, rel+" (cannot decompress)")
				return nil
			}
			scan(rel, "decompressed bytes", plain)
		}
		return nil
	})
	if err != nil {
		return nil, errors.New("goldentest: cannot walk the folder to scan")
	}
	sort.Strings(hits)
	return hits, nil
}

func decompress(data []byte) ([]byte, error) {
	dec, err := zstd.NewReader(nil, zstd.WithDecoderMaxMemory(maxLeakFileBytes))
	if err != nil {
		return nil, err
	}
	defer dec.Close()
	return dec.DecodeAll(data, nil)
}
