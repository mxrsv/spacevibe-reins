package usage

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/logs"
)

// CacheFileName is the scan cache inside the data folder.
const CacheFileName = "usage-cache.json"

// maxCacheBytes caps how much of the cache is read; a larger file is an empty cache.
const maxCacheBytes = 512 << 20

// errCacheTooLarge stops the chunked read of an oversized cache.
var errCacheTooLarge = errors.New("usage cache is too large")

// cachedFile is one scanned log as the cache keeps it. The layout matches Node usage and the Swift engine,
// so a cache written by any of them is readable by the others (UsageScanCache.swift:3-16).
type cachedFile struct {
	// V is ScanVersion when the log was parsed.
	V int `json:"v"`
	// Stamp is "<size>:<floor(mtime ms)>": a changed log is parsed again.
	Stamp   string `json:"stamp"`
	CLI     CLI    `json:"cli"`
	Session string `json:"session"`
	// First is the day of the first timestamp; the key is left out when there is none, as Swift's
	// synthesized encoder leaves out a nil optional.
	First *string    `json:"first,omitempty"`
	Rec   fileRecord `json:"rec"`
}

// mtimeMs is the modification time of the log in ms, from the stamp.
func (c cachedFile) mtimeMs() int64 {
	parts := strings.Split(c.Stamp, ":")
	n, err := strconv.ParseInt(parts[len(parts)-1], 10, 64)
	if err != nil {
		return 0
	}
	return n
}

// The raw shapes decode with pointers so a missing or null member rejects the entry, as Swift's synthesized
// Decodable does for a non-optional field. Optional members (First, Last) stay optional.
type (
	rawEntry struct {
		V       *int       `json:"v"`
		Stamp   *string    `json:"stamp"`
		CLI     *string    `json:"cli"`
		Session *string    `json:"session"`
		First   *string    `json:"first"`
		Rec     *rawRecord `json:"rec"`
	}
	rawRecord struct {
		Skill *map[string][]string `json:"skill"`
		Agent *map[string][]string `json:"agent"`
		Hook  *map[string]rawHook  `json:"hook"`
	}
	rawHook struct {
		Runs   *int     `json:"runs"`
		Ms     *float64 `json:"ms"`
		Timed  *int     `json:"timed"`
		Errors *int     `json:"errors"`
		Last   *string  `json:"last"`
	}
)

func (r rawEntry) valid() (cachedFile, bool) {
	if r.V == nil || r.Stamp == nil || r.CLI == nil || r.Session == nil || r.Rec == nil ||
		r.Rec.Skill == nil || r.Rec.Agent == nil || r.Rec.Hook == nil {
		return cachedFile{}, false
	}
	cli := CLI(*r.CLI)
	if cli != Claude && cli != Codex {
		return cachedFile{}, false
	}
	rec := fileRecord{Skill: *r.Rec.Skill, Agent: *r.Rec.Agent, Hook: make(map[string]HookTotals, len(*r.Rec.Hook))}
	for key, h := range *r.Rec.Hook {
		if h.Runs == nil || h.Ms == nil || h.Timed == nil || h.Errors == nil {
			return cachedFile{}, false
		}
		rec.Hook[key] = HookTotals{Runs: *h.Runs, Ms: *h.Ms, Timed: *h.Timed, Errors: *h.Errors, Last: h.Last}
	}
	return cachedFile{V: *r.V, Stamp: *r.Stamp, CLI: cli, Session: *r.Session, First: r.First, Rec: rec}, true
}

// CachePath is the scan cache file under a data folder.
func CachePath(dataDir string) string { return filepath.Join(dataDir, CacheFileName) }

// loadCache reads the cache. An unreadable, oversized or corrupt cache is an empty one; a single bad entry
// drops only itself. A path that is not a regular file (a FIFO) is unreadable, never waited on.
func loadCache(dataDir string) map[string]cachedFile {
	var data []byte
	err := logs.ForEachChunk(CachePath(dataDir), func(chunk []byte) error {
		if len(data)+len(chunk) > maxCacheBytes {
			return errCacheTooLarge
		}
		data = append(data, chunk...)
		return nil
	})
	out := map[string]cachedFile{}
	if err != nil {
		return out
	}
	var entries map[string]json.RawMessage
	if json.Unmarshal(data, &entries) != nil {
		return out
	}
	for path, raw := range entries {
		var entry rawEntry
		if json.Unmarshal(raw, &entry) != nil {
			continue
		}
		if file, ok := entry.valid(); ok {
			out[path] = file
		}
	}
	return out
}

// encodeCache writes the cache the way Swift's JSONEncoder does: compact, no HTML escaping, and "/" written
// as "\/". Swift's key order is random per process, so the order here (sorted) is not part of the format.
func encodeCache(cache map[string]cachedFile) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(cache); err != nil {
		return nil, err
	}
	// The only "/" in the output sit inside strings, so escaping every one is safe.
	return bytes.ReplaceAll(bytes.TrimSuffix(buf.Bytes(), []byte("\n")), []byte("/"), []byte(`\/`)), nil
}

// saveCache is best effort: a cache that cannot be written only costs the next scan its speed. The folder is
// created 0700 and the file is 0600.
func saveCache(cache map[string]cachedFile, dataDir string) {
	data, err := encodeCache(cache)
	if err != nil || os.MkdirAll(dataDir, 0o700) != nil {
		return
	}
	_ = fsx.AtomicWrite(CachePath(dataDir), data, 0o600, fsx.AtomicWriteOptions{})
}
