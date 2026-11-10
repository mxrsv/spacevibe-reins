package inventory

import (
	"encoding/json"
	"errors"
	"io/fs"
	"path/filepath"
	"syscall"
	"time"

	"spacevibe.dev/core/internal/fsx"
)

// The first-seen store: "Added" is the first time SpaceVibe saw an item id, not the modification time of its
// file (any edit, or an archive tool, moves that). It lives in <data>/first-seen.json and is written only by
// Service.Rows; the pure builders (AttachUsage, BuildLoadoutRows) take the times as an argument.
//
//	missing file   seeded from today's modification times, so the first run reads exactly as before
//	id not stored  its first-seen time is "now" (the file's date is ignored)
//	id absent      kept, so a Remove and its Undo keep the original time; dropped once it has been absent
//	               for firstSeenForget (and only then)
//	unusable file  corrupt, too large, unreadable or from a newer version: left alone, and the read falls back
//	               to modification times. A store that cannot be written does the same.
const (
	firstSeenFile    = "first-seen.json"
	firstSeenVersion = 1
	// firstSeenForget is how long an id may stay absent before its entry is dropped.
	firstSeenForget = 90 * 24 * time.Hour
	// firstSeenRefresh is how stale "last seen" may get before it is written again, so a read that changes
	// nothing else does not write the file.
	firstSeenRefresh = 24 * time.Hour
	firstSeenMaxByte = 8 << 20
)

// seenEntry is one id: when it was first seen and when a read last found it, in ms since 1970.
type seenEntry struct {
	First float64 `json:"first"`
	Last  float64 `json:"last"`
}

type seenStore struct {
	Version int                  `json:"version"`
	Items   map[string]seenEntry `json:"items"`
}

// loadSeen reads the store. seed is true when there is no file yet. ok is false when the file cannot be used.
func loadSeen(path string) (store seenStore, seed, ok bool) {
	data, err := fsx.ReadRegular(path, firstSeenMaxByte)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) || errors.Is(err, syscall.ENOTDIR) {
			return seenStore{Version: firstSeenVersion, Items: map[string]seenEntry{}}, true, true
		}
		return seenStore{}, false, false
	}
	if json.Unmarshal(data, &store) != nil || store.Version != firstSeenVersion || store.Items == nil {
		return seenStore{}, false, false
	}
	return store, false, true
}

// firstSeenMs returns the first-seen time of every id of the snapshot that has one, in ms, and updates the
// store on disk. It never fails: nil means "use modification times".
func (s *Service) firstSeenMs(snapshot Snapshot, now time.Time) map[string]float64 {
	s.seenMu.Lock()
	defer s.seenMu.Unlock()
	path := filepath.Join(s.roots.Data, firstSeenFile)
	store, seed, ok := loadSeen(path)
	if !ok {
		return nil
	}
	nowMs := float64(now.UnixNano()) / 1e6
	refreshMs := float64(firstSeenRefresh.Milliseconds())
	forgetMs := float64(firstSeenForget.Milliseconds())
	changed := false
	present := make(map[string]bool, len(snapshot.Items)+len(snapshot.Hooks))
	touch := func(id, file string) {
		present[id] = true
		entry, known := store.Items[id]
		switch {
		case known:
			if nowMs-entry.Last < refreshMs {
				return
			}
			entry.Last = nowMs
		case seed:
			ms, found := modifiedMs(file)
			if !found {
				return // the same as without the store: no time, no "added" note
			}
			entry = seenEntry{First: ms, Last: nowMs}
		default:
			entry = seenEntry{First: nowMs, Last: nowMs}
		}
		store.Items[id] = entry
		changed = true
	}
	for _, item := range snapshot.Items {
		touch(item.ID, item.File)
	}
	for _, hook := range snapshot.Hooks {
		touch(hook.ID, hook.File)
	}
	for id, entry := range store.Items {
		if !present[id] && nowMs-entry.Last > forgetMs {
			delete(store.Items, id)
			changed = true
		}
	}
	if changed && !saveSeen(path, store) {
		return nil
	}
	out := make(map[string]float64, len(present))
	for id := range present {
		if entry, known := store.Items[id]; known {
			out[id] = entry.First
		}
	}
	return out
}

// saveSeen writes the store 0600 in a 0700 data folder, through the guarded fsx primitives. False when it
// could not.
func saveSeen(path string, store seenStore) bool {
	data, err := json.Marshal(store)
	if err != nil || fsx.MkdirAll(filepath.Dir(path), 0o700) != nil {
		return false
	}
	return fsx.AtomicWrite(path, data, 0o600, fsx.AtomicWriteOptions{}) == nil
}
