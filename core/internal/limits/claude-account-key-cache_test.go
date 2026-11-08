package limits

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"spacevibe.dev/core/internal/hashes"
)

// The status line collector is a new process per refresh. CachedAccountKey keeps the key it computed in
// <data>/claude-limits/account-key, keyed by the state file's path, size, mtime and the Claude root, so an unchanged
// state file (up to 64 MiB) is not read and parsed again. New in Go; the key itself is AccountKey's, unchanged.

const (
	cacheAccount = "11111111-aaaa-bbbb-cccc-private-account"
	cacheOrg     = "22222222-aaaa-bbbb-cccc-private-org"
)

func stateText(account string) string {
	return `{"oauthAccount":{"accountUuid":"` + account + `","organizationUuid":"` + cacheOrg + `"}}`
}

// countReads counts the reads of the state file until the test ends.
func countReads(t *testing.T) *int {
	t.Helper()
	reads := 0
	real := readState
	readState = func(path string, max int64) ([]byte, error) { reads++; return real(path, max) }
	t.Cleanup(func() { readState = real })
	return &reads
}

func keyOf(account string, h tempHome) string {
	return hashes.SHA256Hex([]byte(h.path(".claude") + "\n" + account + "\n" + cacheOrg))
}

func cachePath(h tempHome) string {
	return filepath.Join(h.path(".spacevibe"), SnapshotDir, AccountKeyCacheFile)
}

func TestCachedAccountKeyDoesNotReadAnUnchangedStateFile(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/.claude.json", stateText(cacheAccount))
	reads := countReads(t)
	want := keyOf(cacheAccount, h)

	key, ok := CachedAccountKey(h.cfg(), h.roots())
	if !ok || key != want || *reads != 1 {
		t.Fatalf("first call: key %q ok %v reads %d", key, ok, *reads)
	}
	for i := 0; i < 3; i++ {
		key, ok = CachedAccountKey(h.cfg(), h.roots())
		if !ok || key != want {
			t.Fatalf("call %d: key %q ok %v", i+2, key, ok)
		}
	}
	if *reads != 1 {
		t.Errorf("the state file was read %d times, want once", *reads)
	}

	info, err := os.Stat(cachePath(h))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("cache mode %v, want 0600", info.Mode().Perm())
	}
	data, _ := os.ReadFile(cachePath(h))
	for _, secret := range []string{cacheAccount, cacheOrg} {
		if strings.Contains(string(data), secret) {
			t.Errorf("the cache holds an account id in clear text: %s", data)
		}
	}
	if !strings.Contains(string(data), want) {
		t.Errorf("the cache lacks the key: %s", data)
	}
	// The cache is not a session snapshot.
	for _, f := range SnapshotFiles(h.cfg(), h.roots()) {
		if filepath.Base(f) == AccountKeyCacheFile {
			t.Errorf("SnapshotFiles lists the cache: %s", f)
		}
	}
}

func TestCachedAccountKeyRecomputesWhenTheStateFileChanges(t *testing.T) {
	statePath := func(h tempHome) string { return h.path(".claude/.claude.json") }
	for name, change := range map[string]func(h tempHome){
		"same size, new mtime": func(h tempHome) {
			// Another account of the same length: only the modification time tells.
			next := strings.Replace(stateText(cacheAccount), "11111111", "99999999", 1)
			h.write(".claude/.claude.json", next)
			later := time.Now().Add(time.Hour)
			if err := os.Chtimes(statePath(h), later, later); err != nil {
				t.Fatal(err)
			}
		},
		"new size, same mtime": func(h tempHome) {
			info, _ := os.Stat(statePath(h))
			h.write(".claude/.claude.json", stateText(cacheAccount+"-longer"))
			if err := os.Chtimes(statePath(h), info.ModTime(), info.ModTime()); err != nil {
				t.Fatal(err)
			}
		},
	} {
		t.Run(name, func(t *testing.T) {
			h := newTempHome(t)
			h.write(".claude/.claude.json", stateText(cacheAccount))
			first, ok := CachedAccountKey(h.cfg(), h.roots())
			if !ok {
				t.Fatal("no key")
			}
			reads := countReads(t)
			change(h)
			again, ok := CachedAccountKey(h.cfg(), h.roots())
			wantKey, wantOK := AccountKey(h.roots())
			if !ok || !wantOK || again != wantKey || again == first {
				t.Errorf("key %q ok %v, want a new %q (was %q)", again, ok, wantKey, first)
			}
			if *reads < 1 {
				t.Error("a changed state file was not read")
			}
			if third, _ := CachedAccountKey(h.cfg(), h.roots()); third != again {
				t.Errorf("the new key was not stored: %q", third)
			}
		})
	}
}

func TestCachedAccountKeyIgnoresACacheThatDoesNotMatch(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/.claude.json", stateText(cacheAccount))
	want := keyOf(cacheAccount, h)
	if _, ok := CachedAccountKey(h.cfg(), h.roots()); !ok {
		t.Fatal("no key")
	}
	good, err := os.ReadFile(cachePath(h))
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if err := json.Unmarshal(good, &fields); err != nil {
		t.Fatal(err)
	}
	tamper := func(key string, value any) string {
		next := map[string]any{}
		for k, v := range fields {
			next[k] = v
		}
		next[key] = value
		b, _ := json.Marshal(next)
		return string(b)
	}
	for name, text := range map[string]string{
		"not json":      "not json {",
		"empty":         "",
		"wrong shape":   `["a"]`,
		"another path":  tamper("state", "/elsewhere/.claude.json"),
		"another size":  tamper("size", 1),
		"another mtime": tamper("mtime", 1),
		"another root":  tamper("root", "/another/claude/root"),
		"key not hex":   tamper("key", "ZZ"),
		"key missing":   tamper("key", ""),
	} {
		t.Run(name, func(t *testing.T) {
			if err := os.WriteFile(cachePath(h), []byte(text), 0o600); err != nil {
				t.Fatal(err)
			}
			reads := countReads(t)
			key, ok := CachedAccountKey(h.cfg(), h.roots())
			if !ok || key != want {
				t.Fatalf("key %q ok %v, want %q", key, ok, want)
			}
			if *reads != 1 {
				t.Errorf("the state file was read %d times, want once (a miss)", *reads)
			}
			healed, _ := os.ReadFile(cachePath(h))
			if string(healed) != string(good) {
				t.Errorf("the cache was not rewritten: %s", healed)
			}
		})
	}
}

func TestCachedAccountKeyNeverFailsOnTheCache(t *testing.T) {
	t.Run("no account is not cached", func(t *testing.T) {
		h := newTempHome(t)
		h.write(".claude/.claude.json", `{}`)
		if key, ok := CachedAccountKey(h.cfg(), h.roots()); ok || key != "" {
			t.Errorf("key %q ok %v", key, ok)
		}
		if _, err := os.Lstat(cachePath(h)); !os.IsNotExist(err) {
			t.Errorf("a cache was written for no account: %v", err)
		}
	})
	t.Run("no state file", func(t *testing.T) {
		h := newTempHome(t)
		if _, ok := CachedAccountKey(h.cfg(), h.roots()); ok {
			t.Error("a key without a state file")
		}
	})
	t.Run("the folder cannot be written", func(t *testing.T) {
		if os.Geteuid() == 0 {
			t.Skip("root writes everywhere")
		}
		h := newTempHome(t)
		h.write(".claude/.claude.json", stateText(cacheAccount))
		folder := filepath.Dir(cachePath(h))
		if err := os.MkdirAll(folder, 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.Chmod(folder, 0o500); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = os.Chmod(folder, 0o700) })
		key, ok := CachedAccountKey(h.cfg(), h.roots())
		if !ok || key != keyOf(cacheAccount, h) {
			t.Errorf("key %q ok %v", key, ok)
		}
	})
	t.Run("the cache is a folder", func(t *testing.T) {
		h := newTempHome(t)
		h.write(".claude/.claude.json", stateText(cacheAccount))
		if err := os.MkdirAll(cachePath(h), 0o700); err != nil {
			t.Fatal(err)
		}
		key, ok := CachedAccountKey(h.cfg(), h.roots())
		if !ok || key != keyOf(cacheAccount, h) {
			t.Errorf("key %q ok %v", key, ok)
		}
	})
}
