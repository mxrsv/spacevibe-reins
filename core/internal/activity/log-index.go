package activity

import (
	"bytes"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"spacevibe.dev/core/internal/logs"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
)

// Log discovery (Activity.swift listLogs and its helpers).

const (
	childHeadBytes = 64 * 1024
	indexTailBytes = 1024 * 1024
)

type logFile struct {
	path    string
	cli     CLI
	session string
	sub     bool
	mtimeMs float64
}

type logIndex struct {
	files      []logFile
	claudeMain map[string]logFile
	claudeSubs map[string][]logFile
	codexByID  map[string]logFile
}

// listLogs finds every transcript and rollout. A Claude log is `<projects>/<folder>/<session>.jsonl`, a subagent log
// is `<projects>/<folder>/<session>/subagents/<file>`; a rollout name ends in the thread uuid.
func listLogs(r roots.Roots) logIndex {
	index := logIndex{claudeMain: map[string]logFile{}, claudeSubs: map[string][]logFile{}, codexByID: map[string]logFile{}}
	for _, path := range logs.Walk(r.Claude.Logs) {
		rel, err := filepath.Rel(r.Claude.Logs, path)
		if err != nil {
			continue
		}
		parts := strings.Split(filepath.ToSlash(rel), "/")
		sub := len(parts) >= 4 && parts[2] == "subagents"
		session := logs.BaseName(path)
		if sub {
			session = parts[1]
		}
		mtime, ok := mtimeMs(path)
		if !ok {
			continue
		}
		file := logFile{path: path, cli: CLIClaude, session: session, sub: sub, mtimeMs: mtime}
		index.files = append(index.files, file)
		if sub {
			index.claudeSubs[session] = append(index.claudeSubs[session], file)
		} else if len(parts) == 2 {
			index.claudeMain[session] = file
		}
	}
	for _, path := range logs.Walk(r.Codex.Logs) {
		if !strings.HasPrefix(filepath.Base(path), "rollout-") {
			continue
		}
		id, ok := threadID(path)
		if !ok {
			continue
		}
		mtime, ok := mtimeMs(path)
		if !ok {
			continue
		}
		file := logFile{path: path, cli: CLICodex, session: id, mtimeMs: mtime}
		index.files = append(index.files, file)
		index.codexByID[id] = file
	}
	return index
}

// threadID is the uuid that ends a rollout's name: `rollout-2026-11-02T09-00-01-<uuid>.jsonl[.zst]`. Swift took the
// last 36 Characters; this takes the last 36 bytes, which is the same for the ASCII-only uuid shape.
func threadID(path string) (string, bool) {
	base := logs.BaseName(path)
	if len(base) < 36 {
		return "", false
	}
	tail := base[len(base)-36:]
	for i := 0; i < 36; i++ {
		c := tail[i]
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' {
				return "", false
			}
		} else if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return "", false
		}
	}
	return tail, true
}

// mtimeMs is the modification time in milliseconds, computed as seconds*1000 + nanoseconds/1e6 in floating point.
func mtimeMs(path string) (float64, bool) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, false
	}
	t := info.ModTime()
	return textjs.BoundedTimestamp(float64(t.Unix())*1000 + float64(t.Nanosecond())/1e6)
}

// readRegularFile reads a file that is a regular file. A FIFO would block a reader that has no writer.
func readRegularFile(path string) ([]byte, bool) {
	data, err := readRegularFileErr(path)
	return data, err == nil
}

// errNotRegular is what readRegularFileErr returns for a FIFO, a directory or a device.
var errNotRegular = errors.New("not a regular file")

// readRegularFileErr is readRegularFile with the reason: an fs error (os.IsNotExist tells a vanished file from an
// unreadable one) or errNotRegular.
func readRegularFileErr(path string) ([]byte, error) {
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, errNotRegular
	}
	return os.ReadFile(path)
}

// readJSONObject reads a file whose root is a JSON object.
func readJSONObject(path string) (jv, bool) {
	data, ok := readRegularFile(path)
	if !ok {
		return jv{}, false
	}
	return parseLine(data)
}

// readHead is the first n bytes of a regular file.
func readHead(path string, n int) []byte {
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() {
		return nil
	}
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	buf := make([]byte, n)
	got, _ := io.ReadFull(f, buf)
	return buf[:got]
}

// isChildRollout: Codex subagent rollouts name their parent thread in session_meta (the first 64 KB is enough).
func isChildRollout(path string) bool {
	head := readHead(path, childHeadBytes)
	if textjs.Contains(head, `"source":{"subagent"`) {
		return true
	}
	key := []byte(`"parent_thread_id":"`)
	// The Swift loop stops one byte early (i + key.count < bytes.count), so a key at the very end never counts.
	for i := 0; i+len(key) < len(head); i++ {
		if head[i] == key[0] && bytes.Equal(head[i:i+len(key)], key) {
			c := head[i+len(key)]
			if (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') {
				return true
			}
		}
	}
	return false
}

// codexThreadNames reads thread names from the tail of the session index; a later line wins.
func codexThreadNames(r roots.Roots) map[string]string {
	names := map[string]string{}
	path := filepath.Join(r.Codex.Root, "session_index.jsonl")
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() {
		return names
	}
	f, err := os.Open(path)
	if err != nil {
		return names
	}
	defer f.Close()
	size := info.Size()
	start := int64(0)
	if size > indexTailBytes {
		start = size - indexTailBytes
	}
	data, err := io.ReadAll(io.NewSectionReader(f, start, size-start))
	if err != nil {
		return names
	}
	lines := bytes.Split(data, []byte{'\n'})
	if start > 0 && len(lines) > 0 {
		lines = lines[1:]
	}
	for _, line := range lines {
		doc, err := ojson.Parse(line)
		if err != nil {
			continue
		}
		root := present(doc.Root())
		id, ok := root.field("id").str()
		if !ok || id == "" {
			continue
		}
		if name, ok := root.field("thread_name").str(); ok {
			names[id] = name
		}
	}
	return names
}

// isStatusFileName is `<digits>.json`.
func isStatusFileName(name string) bool {
	if !strings.HasSuffix(name, ".json") || len(name) <= 5 {
		return false
	}
	for _, c := range []byte(name[:len(name)-5]) {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// statusFileNames lists the Claude status files (`<pid>.json`) of a sessions folder, sorted.
func statusFileNames(dir string) []string {
	names, _ := listStatusFiles(dir)
	return names
}

// listStatusFiles is statusFileNames with the read error. A folder that does not exist is no error (nothing is
// running); one that cannot be read (permissions, I/O) is, because then "no status file" proves nothing.
func listStatusFiles(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if isStatusFileName(e.Name()) {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names, nil
}
