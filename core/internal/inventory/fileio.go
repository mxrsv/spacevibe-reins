package inventory

import (
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"

	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/textjs"
)

const (
	// maxTextBytes: SKILL.md and agent files: only the head matters (frontmatter, description).
	maxTextBytes = 1 << 20
	// maxJSONBytes: settings and hook files.
	maxJSONBytes = 16 << 20
	// itemFileBytes is how much of a skill or agent file the detail view shows.
	itemFileBytes = 64 * 1024
)

// jsonStatus says how reading a JSON file went.
type jsonStatus int

const (
	jsonMissing jsonStatus = iota
	// jsonUnreadable: exists but cannot be opened or read (permission, a folder, a FIFO, an I/O error).
	jsonUnreadable
	jsonTooLarge
	jsonInvalid
	jsonValue
)

// presence is the answer to "is anything there?".
type presence int

const (
	present presence = iota
	// missing is ENOENT or ENOTDIR: nothing is there.
	missing
	// unknown means the lookup failed for another reason (EACCES, EPERM, ELOOP, ...): the path may well exist.
	unknown
)

// pathPresence is stat following symlinks. Only ENOENT and ENOTDIR mean missing; a denied parent folder must
// not read as "gone".
func pathPresence(path string) presence {
	_, err := os.Stat(path)
	switch {
	case err == nil:
		return present
	case errors.Is(err, syscall.ENOENT), errors.Is(err, syscall.ENOTDIR), errors.Is(err, fs.ErrNotExist):
		return missing
	default:
		return unknown
	}
}

// exists is true only when the path is there.
func exists(path string) bool { return pathPresence(path) == present }

// openRegular opens a regular file without blocking and checks the opened descriptor, not a path that could
// change between stat and open. Symlinks to regular files are followed (shared skill installs). A FIFO, a
// device or a folder is refused.
func openRegular(path string) (*os.File, error) {
	f, err := openNonblocking(path)
	if err != nil {
		return nil, err
	}
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		_ = f.Close()
		return nil, errors.New("not a regular file")
	}
	return f, nil
}

// readData is up to maxBytes of the file; nil, false when it cannot be read.
func readData(path string, maxBytes int) ([]byte, bool) {
	f, err := openRegular(path)
	if err != nil {
		return nil, false
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, int64(maxBytes)))
	if err != nil {
		return nil, false
	}
	return data, true
}

// readText is up to maxBytes of the file as text; invalid UTF-8 becomes U+FFFD, as Node does.
func readText(path string, maxBytes int) (string, bool) {
	data, ok := readData(path, maxBytes)
	if !ok {
		return "", false
	}
	return textjs.Repair(string(data)), true
}

// readJSON reads and parses a settings or hook file, classifying every failure.
func readJSON(path string) (ojson.Value, jsonStatus) {
	f, err := openRegular(path)
	if err != nil {
		if pathPresence(path) == missing {
			return ojson.Value{}, jsonMissing
		}
		return ojson.Value{}, jsonUnreadable
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, maxJSONBytes+1))
	if err != nil {
		return ojson.Value{}, jsonUnreadable
	}
	if len(data) > maxJSONBytes {
		return ojson.Value{}, jsonTooLarge
	}
	doc, err := ojson.ParseString(textjs.Repair(string(data)))
	if err != nil {
		return ojson.Value{}, jsonInvalid
	}
	return doc.Root(), jsonValue
}

// listDir is the entry names of a folder, sorted. Empty when the folder is missing or cannot be read.
func listDir(path string) []string {
	entries, err := os.ReadDir(path)
	if err != nil {
		return nil
	}
	names := make([]string, len(entries))
	for i, e := range entries {
		names[i] = e.Name()
	}
	slices.Sort(names)
	return names
}

// isUnreadableFolder: the folder exists but cannot be listed, or a parent denies the lookup so nobody can
// tell (a denied folder reads as "not readable", never as empty).
func isUnreadableFolder(path string) bool {
	switch pathPresence(path) {
	case missing:
		return false
	case unknown:
		return true
	}
	if !isDirectory(path) {
		return false
	}
	_, err := os.ReadDir(path)
	return err != nil
}

// isDirectory follows symlinks. False for a path that cannot be statted.
func isDirectory(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

// modifiedMs is the modification time in ms since 1970, following symlinks; false when it cannot be statted.
// Computed as seconds*1000 + nanoseconds/1e6 in floating point, like the Swift reader.
func modifiedMs(path string) (float64, bool) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, false
	}
	t := info.ModTime()
	return float64(t.Unix())*1000 + float64(t.Nanosecond())/1_000_000, true
}

// isSymlink reports whether the path itself is a symlink.
func isSymlink(path string) bool {
	info, err := os.Lstat(path)
	return err == nil && info.Mode()&fs.ModeSymlink != 0
}

// join is NSString's appendingPathComponent: single slashes, nothing cleaned.
func join(base string, parts ...string) string {
	for _, p := range parts {
		base = strings.TrimRight(base, "/") + "/" + p
	}
	return base
}

// normalize is path.resolve for an absolute path: "." and ".." folded, no trailing slash. Symlinks are not
// followed.
func normalize(path string) string {
	var stack []string
	for _, part := range strings.Split(path, "/") {
		switch part {
		case "", ".":
		case "..":
			if len(stack) > 0 {
				stack = stack[:len(stack)-1]
			}
		default:
			stack = append(stack, part)
		}
	}
	return "/" + strings.Join(stack, "/")
}

// realPath is the path with symlinks followed, or the normalized path when it does not exist.
func realPath(path string) string {
	abs := normalize(path)
	if resolved, err := filepath.EvalSymlinks(abs); err == nil {
		return resolved
	}
	return abs
}

func osStat(path string) (fs.FileInfo, error) { return os.Stat(path) }
