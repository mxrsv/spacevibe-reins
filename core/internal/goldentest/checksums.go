package goldentest

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// VerifyChecksums does what `shasum -a 256 -c SHA256SUMS` does in dir, and a little more. It reads the file
// sumsName ("<hex>  <path>" per line, a "*" before the path allowed), recomputes each file's SHA-256 and
// returns one line per problem: a mismatch, a missing or unreadable file, a malformed line, or a path outside
// dir. Beyond shasum it also reports every file under a folder named in coverDirs that the sums file does
// not list, so a new file cannot be added to a frozen folder unnoticed. An empty result means the freeze holds.
// It errors only when the sums file cannot be read.
func VerifyChecksums(dir, sumsName string, coverDirs ...string) ([]string, error) {
	text, err := os.ReadFile(filepath.Join(dir, sumsName))
	if err != nil {
		return nil, errors.New("goldentest: cannot read the checksums file")
	}
	var problems []string
	listed := map[string]bool{}
	for i, line := range strings.Split(string(text), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		sum, name, ok := strings.Cut(line, " ")
		name = strings.TrimPrefix(strings.TrimPrefix(name, " "), "*")
		if !ok || len(sum) != 64 || name == "" || !filepath.IsLocal(name) {
			problems = append(problems, "line "+strconv.Itoa(i+1)+": malformed")
			continue
		}
		listed[filepath.ToSlash(name)] = true
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			problems = append(problems, name+": missing or unreadable")
			continue
		}
		got := sha256.Sum256(data)
		if hex.EncodeToString(got[:]) != strings.ToLower(sum) {
			problems = append(problems, name+": checksum differs")
		}
	}
	for _, sub := range coverDirs {
		_ = filepath.WalkDir(filepath.Join(dir, sub), func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return nil
			}
			if rel, _ := filepath.Rel(dir, path); !listed[filepath.ToSlash(rel)] {
				problems = append(problems, rel+": not listed in "+sumsName)
			}
			return nil
		})
	}
	sort.Strings(problems)
	return problems, nil
}
