package limits

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
)

// Claude invokes the separate collector; this package only reads the private, bounded snapshots it leaves, one
// file per session under <data>/claude-limits. It never reads another application's captures or stores the rest
// of the status-line input. The names below are exported for the collector (internal/statusline, G2.6).
const (
	// SnapshotDir is the folder under the data root that holds the snapshots (fsx.ManagedDirectory name).
	SnapshotDir = "claude-limits"
	// MaxInputBytes caps the status line input the collector accepts.
	MaxInputBytes = 1 << 20
	// MaxSnapshotBytes caps one snapshot file; a bigger one is ignored.
	MaxSnapshotBytes = 4096
	// MaxSessions is how many snapshots are read, newest first, and how many the collector keeps.
	MaxSessions = 64
	// MaxAgeSeconds: only readings this close to the newest one are merged.
	MaxAgeSeconds = 3600
	// LastErrorFile is the name, inside SnapshotDir, of the one-line file in which the collector records why its
	// last capture failed (G-fix.19). It has no ".json" suffix, so SnapshotFiles never lists it as a session.
	LastErrorFile = "last-error"

	// maxStateBytes is the one cap on Claude's global state file, for the usage cache and the account key alike: a
	// file past it is unreadable for both, never read by one and skipped by the other (the status line merge needs
	// the account key). The owner's file is about 0.4 MB.
	maxStateBytes = 64 << 20
)

// StatuslineWindow maps a status line `rate_limits` key to the window id and length it reads as.
type StatuslineWindow struct {
	Key     string
	ID      string
	Minutes int
}

// StatuslineWindows are the windows a snapshot can hold, in output order.
func StatuslineWindows() []StatuslineWindow {
	return []StatuslineWindow{{"five_hour", "five_hour", 300}, {"seven_day", "weekly_all", 10080}}
}

// AccountKey binds captures to the configured account without persisting its identifiers: the hex SHA-256 of
// "<claude root>\n<accountUuid>\n<organizationUuid>". False when the state file names no account. No credential
// is read: only the two ids.
func AccountKey(r roots.Roots) (string, bool) {
	data, err := readState(r.ClaudeState, maxStateBytes)
	if err != nil {
		return "", false
	}
	document, err := ojson.ParseString(textjs.Repair(string(data)))
	if err != nil {
		return "", false
	}
	oauth, ok := document.Root().Member("oauthAccount")
	if !ok {
		return "", false
	}
	account, ok := memberOf(oauth, "accountUuid")
	if !ok || account == "" {
		return "", false
	}
	organization, _ := memberOf(oauth, "organizationUuid")
	// URL.standardizedFileURL.path in Swift: "." and ".." folded, no trailing slash.
	root := filepath.Clean(r.Claude.Root)
	return hashes.SHA256Hex([]byte(root + "\n" + account + "\n" + organization)), true
}

// memberOf is a string member, not filtered for null (a null is not a string anyway).
func memberOf(v ojson.Value, key string) (string, bool) {
	value, ok := v.Member(key)
	if !ok {
		return "", false
	}
	return value.StringValue()
}

// SessionIDSyntax reports whether s uses only the characters a session id or a snapshot file stem may have:
// ASCII letters, digits, "-" and "_". It does not check emptiness or length.
func SessionIDSyntax(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= '0' && c <= '9' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c == '-' || c == '_') {
			return false
		}
	}
	return true
}

// SnapshotFiles lists the snapshot files, newest modification first. Empty when the folder is not a private
// directory the data root owns (fsx.ManagedDirectory refuses a link out of it). Only regular files named
// <session>.json count: a FIFO, a link or a stray name is skipped.
func SnapshotFiles(cfg config.Config, r roots.Roots) []string {
	folder, err := fsx.ManagedDirectory(cfg, r, SnapshotDir)
	if err != nil {
		return nil
	}
	entries, err := os.ReadDir(folder)
	if err != nil {
		return nil
	}
	type stamped struct {
		path     string
		modified float64
	}
	var files []stamped
	for _, entry := range entries { // ReadDir is sorted by name
		name := entry.Name()
		stem, isJSON := strings.CutSuffix(name, ".json")
		if !isJSON || !SessionIDSyntax(stem) {
			continue
		}
		path := folder + "/" + name
		if info, err := os.Lstat(path); err != nil || !info.Mode().IsRegular() {
			continue
		}
		files = append(files, stamped{path, modifiedMs(path)})
	}
	slices.SortStableFunc(files, func(a, b stamped) int {
		switch {
		case a.modified > b.modified:
			return -1
		case a.modified < b.modified:
			return 1
		}
		return 0
	})
	paths := make([]string, len(files))
	for i, f := range files {
		paths[i] = f.path
	}
	return paths
}

// modifiedMs is the modification time in ms since 1970, following links; 0 when it cannot be statted.
func modifiedMs(path string) float64 {
	info, err := os.Stat(path)
	if err != nil {
		return 0
	}
	t := info.ModTime()
	return float64(t.Unix())*1000 + float64(t.Nanosecond())/1_000_000
}

// ReadSnapshot reads and parses one snapshot file: at most MaxSnapshotBytes, a regular file only (a FIFO is
// refused without waiting). False for anything that cannot be read or parsed.
func ReadSnapshot(path string) (ojson.Value, bool) {
	data, err := fsx.ReadRegular(path, MaxSnapshotBytes)
	if err != nil {
		return ojson.Value{}, false
	}
	document, err := ojson.Parse(data)
	if err != nil {
		return ojson.Value{}, false
	}
	return document.Root(), true
}

// ParseWindows validates the status line `rate_limits` object and returns the windows it holds, in
// StatuslineWindows order. A window that is present but out of range is an error, so a partial malformed reading
// never replaces a good snapshot. The error is a fixed 400 sentence.
func ParseWindows(raw ojson.Value) ([]Window, error) {
	if _, ok := raw.ObjectValue(); !ok {
		return nil, coreerr.NewStatus("Invalid status line limits.", coreerr.StatusBadRequest)
	}
	var windows []Window
	for _, spec := range StatuslineWindows() {
		value, ok := member(raw, spec.Key)
		if !ok {
			continue
		}
		used, okUsed := memberNumber(value, "used_percentage")
		reset, okReset := memberNumber(value, "resets_at")
		if !okUsed || used < 0 || used > 100 || !okReset || reset <= 0 || reset >= 253_402_300_800 || reset != float64(int64(reset)) {
			return nil, coreerr.NewStatus("Invalid status line window.", coreerr.StatusBadRequest)
		}
		minutes := spec.Minutes
		windows = append(windows, Window{
			ID: spec.ID, Minutes: &minutes, UsedPercent: used, ResetsAt: dateSeconds(reset), Active: true,
		})
	}
	return windows, nil
}

type reading struct {
	at      float64
	windows []Window
}

// readClaude is the Claude Code entry: the usage cache, superseded by the newest status line snapshots of this
// account when they are newer than the cache's fetch.
func readClaude(ctx context.Context, cfg config.Config, r roots.Roots, now float64) (Entry, error) {
	cached := readClaudeCache(r)
	account, ok := AccountKey(r)
	if !ok {
		return cached, nil
	}
	var readings []reading
	for _, path := range limitFiles(SnapshotFiles(cfg, r)) {
		if err := ctx.Err(); err != nil {
			return Entry{}, err
		}
		snapshot, ok := ReadSnapshot(path)
		if !ok {
			continue
		}
		if got, _ := memberOf(snapshot, "account"); got != account {
			continue
		}
		seconds, ok := snapshot.Member("observedAt")
		observed, okNumber := number(seconds)
		if !ok || !okNumber || observed <= 0 || observed > now {
			continue
		}
		raw, ok := snapshot.Member("rate_limits")
		if !ok {
			continue
		}
		windows, err := ParseWindows(raw)
		if err != nil || len(windows) == 0 {
			continue
		}
		readings = append(readings, reading{dateSeconds(observed), windows})
	}
	slices.SortStableFunc(readings, func(a, b reading) int {
		switch {
		case a.at > b.at:
			return -1
		case a.at < b.at:
			return 1
		}
		return 0
	})
	if len(readings) == 0 {
		return cached, nil
	}
	newest := readings[0]
	if cached.State == Measured && *cached.At > newest.at {
		return cached, nil
	}
	// An idle session can repeat an older percentage after an active session. Within the same reset window, use
	// the highest recent observation so receiving that old session's status line cannot move usage backwards.
	var recent []Window
	for _, rd := range readings {
		if newest.at-rd.at <= MaxAgeSeconds {
			recent = append(recent, rd.windows...)
		}
	}
	var merged []Window
	for _, spec := range StatuslineWindows() {
		first := slices.IndexFunc(recent, func(w Window) bool { return w.ID == spec.ID })
		if first < 0 {
			continue
		}
		best := recent[first]
		for _, w := range recent {
			if w.ID == best.ID && w.ResetsAt == recent[first].ResetsAt && w.UsedPercent > best.UsedPercent {
				best = w
			}
		}
		merged = append(merged, best)
	}
	source := ClaudeStatusline
	entry := measured(Claude, newest.at, merged)
	entry.Source = &source
	return entry, nil
}

func limitFiles(paths []string) []string {
	if len(paths) > MaxSessions {
		return paths[:MaxSessions]
	}
	return paths
}
