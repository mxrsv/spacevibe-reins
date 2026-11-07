package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/roots"
)

type invItem struct {
	ID        string `json:"id"`
	CLI       string `json:"cli"`
	Kind      string `json:"kind"`
	Name      string `json:"name"`
	Owner     string `json:"owner"`
	Path      string `json:"path"`
	Removable bool   `json:"removable"`
	Scope     string `json:"scope"`
}

// writeCases are the contract cases that change files or prove a write is refused.
func writeCases(t *testing.T) {
	t.Run("loadout_removeItem_then_undo", func(t *testing.T) {
		c := startOn(t, shippedBin, copiedHome(t))
		c.initialize()
		var snap struct{ Items []invItem }
		decodeInto(t, c.ok(c.call("1", "inventory.read", `{}`)), &snap)
		var victim, plugin *invItem
		for i := range snap.Items {
			it := &snap.Items[i]
			switch {
			case victim == nil && it.CLI == "claude" && it.Kind == "agent" && it.Owner == "user" && it.Removable && it.Scope == "global":
				victim = it
			case plugin == nil && !it.Removable:
				plugin = it
			}
		}
		if victim == nil || plugin == nil {
			t.Fatalf("the fixture lacks a removable agent or a locked item: %+v", snap.Items)
		}
		before, err := os.ReadFile(victim.Path)
		if err != nil {
			t.Fatal(err)
		}
		infoBefore, _ := os.Stat(victim.Path)

		// Refusals change nothing.
		if got := c.status(c.call("2", "loadout.removeItem", `{"id":"`+plugin.ID+`"}`)); got != 403 {
			t.Errorf("a plugin item: status %d", got)
		}
		if got := c.status(c.call("3", "loadout.removeItem", `{"id":"claude:agent:local:no-such.md"}`)); got != 404 {
			t.Errorf("an unknown id: status %d", got)
		}
		c.wantError(c.call("4", "loadout.removeItem", `{"id":"x","path":"/etc/passwd"}`), -32602)
		c.wantError(c.call("5", "loadout.removeItem", `{"id":7}`), -32602)
		var hist struct{ Entries []json.RawMessage }
		decodeInto(t, c.ok(c.call("6", "journal.history", `{}`)), &hist)
		if len(hist.Entries) != 0 {
			t.Fatalf("a refused write left %d journal entries", len(hist.Entries))
		}

		var removed struct {
			Entry struct {
				ID, Label string
				Undone    bool
				Count     int
			}
		}
		decodeInto(t, c.ok(c.call("7", "loadout.removeItem", `{"id":"`+victim.ID+`"}`)), &removed)
		c.norm.mask(removed.Entry.ID, "$ENTRY_ID")
		if !strings.HasPrefix(removed.Entry.Label, "Removed agent "+victim.Name) || removed.Entry.Undone || removed.Entry.Count == 0 {
			t.Fatalf("entry %+v", removed.Entry)
		}
		if _, err := os.Lstat(victim.Path); err == nil {
			t.Fatal("the agent file is still there")
		}
		decodeInto(t, c.ok(c.call("8", "journal.history", `{}`)), &hist)
		if len(hist.Entries) != 1 {
			t.Fatalf("history has %d entries", len(hist.Entries))
		}

		var undone struct{ Label string }
		decodeInto(t, c.ok(c.call("9", "journal.undo", `{"id":"`+removed.Entry.ID+`"}`)), &undone)
		if undone.Label != removed.Entry.Label {
			t.Fatalf("undo label %q", undone.Label)
		}
		after, err := os.ReadFile(victim.Path)
		if err != nil || !bytes.Equal(before, after) {
			t.Fatalf("the file is not back byte for byte (%v)", err)
		}
		if infoAfter, _ := os.Stat(victim.Path); infoAfter.Mode() != infoBefore.Mode() {
			t.Errorf("mode %v, was %v", infoAfter.Mode(), infoBefore.Mode())
		}
		if got := c.status(c.call("10", "journal.undo", `{"id":"`+removed.Entry.ID+`"}`)); got != 409 { // already undone
			t.Errorf("a second undo: status %d", got)
		}
		if got := c.status(c.call("11", "journal.undo", `{"id":"no-such-entry"}`)); got != 404 {
			t.Errorf("an unknown entry: status %d", got)
		}
		decodeInto(t, c.ok(c.call("12", "journal.history", `{}`)), &hist)
		var first struct{ Undone bool }
		decodeInto(t, hist.Entries[0], &first)
		if !first.Undone {
			t.Error("history does not show the entry as undone")
		}
		c.finish("loadout_removeItem_then_undo")
	})

	t.Run("write_guard_installed", func(t *testing.T) {
		real, err := roots.RealHome()
		if err != nil {
			t.Skip(err)
		}
		// The probe sits in a folder that does not exist: with the guard missing the write fails for a different
		// reason and nothing is created, so a broken guard shows up as a wrong message, never as a stray file.
		probe := filepath.Join(real, ".spacevibe-never-written", "probe")
		c := startCore(t, debugBin)
		c.norm = newNormalizer(c.home)
		c.norm.mask(real, "$REAL_HOME") // a transcript never names the real home (S-R2)
		c.initialize()
		r := c.call("1", "debug.write", `{"path":`+quote(probe)+`}`)
		if got := c.status(r); got != 500 || !strings.Contains(r.Error.Message, "real home") {
			t.Fatalf("a write aimed at the real home got %d %q, want the guard's refusal", got, r.Error.Message)
		}
		if _, err := os.Lstat(filepath.Dir(probe)); err == nil {
			t.Fatal("the probe folder exists under the real home")
		}
		// A write inside the synthetic home is not refused.
		own := filepath.Join(c.home, "own-file")
		if r := c.call("2", "debug.write", `{"path":`+quote(own)+`}`); r.Error != nil {
			t.Fatalf("a write in the synthetic home was refused: %+v", r.Error)
		}
		c.finish("write_guard_installed")
	})
}

func quote(s string) string { b, _ := json.Marshal(s); return string(b) }
