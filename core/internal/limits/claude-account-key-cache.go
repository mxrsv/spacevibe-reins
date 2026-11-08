package limits

import (
	"encoding/json"
	"os"
	"path/filepath"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/roots"
)

// AccountKeyCacheFile is the name, inside SnapshotDir, of the one-object file in which a capture remembers the
// account key it computed. It has no ".json" suffix, so SnapshotFiles never lists it as a session.
const AccountKeyCacheFile = "account-key"

// maxAccountKeyCacheBytes caps the cache file; a bigger one is ignored.
const maxAccountKeyCacheBytes = 4096

// readState reads Claude's global state file. A variable so a test can count the reads.
var readState = fsx.ReadRegular

// accountKeyCache is what the file holds: the stamp of the state file the key was computed from, and the key. Only
// the hex hash is kept, never an account or organization id.
type accountKeyCache struct {
	State string `json:"state"` // absolute path of the state file
	Size  int64  `json:"size"`  // its size in bytes
	MTime int64  `json:"mtime"` // its modification time, ns since 1970
	Root  string `json:"root"`  // the cleaned Claude root the key was hashed with
	Key   string `json:"key"`   // AccountKey's result
}

// CachedAccountKey is AccountKey for the status line collector, which runs once per refresh as a new process and would
// otherwise read and parse the whole state file (up to 64 MiB) every time. It looks first in <data>/claude-limits/
// account-key: when the state file's path, size, modification time (ns) and the Claude root are those the cached key
// was computed from, the key is returned without reading the file. Otherwise the key is computed as AccountKey does
// and stored. The cache is only an accelerator: any trouble with it (folder refused, unreadable, corrupt, not
// writable) falls back to the plain computation, and a failed store is ignored, so it can never fail a capture.
func CachedAccountKey(cfg config.Config, r roots.Roots) (string, bool) {
	want, stamped := stampOf(r)
	if !stamped {
		return AccountKey(r)
	}
	folder, err := fsx.ManagedDirectory(cfg, r, SnapshotDir)
	if err != nil {
		return AccountKey(r)
	}
	file := filepath.Join(folder, AccountKeyCacheFile)
	if data, err := fsx.ReadRegular(file, maxAccountKeyCacheBytes); err == nil {
		var got accountKeyCache
		if json.Unmarshal(data, &got) == nil && got.matches(want) {
			return got.Key, true
		}
	}
	key, ok := AccountKey(r)
	if ok {
		want.Key = key
		if data, err := json.Marshal(want); err == nil && fsx.MkdirAll(folder, 0o700) == nil {
			_ = fsx.AtomicWrite(file, data, 0o600, fsx.AtomicWriteOptions{})
		}
	}
	return key, ok
}

// stampOf is the cache key of the current state file; false when it is no regular file within the cap (the plain
// computation then answers "no key" as it always did).
func stampOf(r roots.Roots) (accountKeyCache, bool) {
	path, err := filepath.Abs(r.ClaudeState)
	if err != nil {
		return accountKeyCache{}, false
	}
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() || info.Size() > maxStateBytes {
		return accountKeyCache{}, false
	}
	return accountKeyCache{State: path, Size: info.Size(), MTime: info.ModTime().UnixNano(), Root: filepath.Clean(r.Claude.Root)}, true
}

// matches is true when got was computed from the file want describes and holds a well-formed key.
func (got accountKeyCache) matches(want accountKeyCache) bool {
	return got.State == want.State && got.Size == want.Size && got.MTime == want.MTime && got.Root == want.Root && isHexKey(got.Key)
}

// isHexKey: the 64 lowercase hex digits of a SHA-256.
func isHexKey(s string) bool {
	if len(s) != 64 {
		return false
	}
	for i := 0; i < len(s); i++ {
		if c := s[i]; !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	return true
}
