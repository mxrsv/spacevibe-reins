package mutate

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/usage"
)

// MutationTransactionTests.swift. The Swift "rule" operation used RulesStore.changeVerdict, which the rules package
// (G2.4) ports; here the same slot is an EditJSON of the settings file, which is the journal and rollback path a rule
// write takes. The seed gives existing-agent instructions, because copying an agent without any is now refused (G-fix.17).

type operation string

var allOperations = []operation{"rule", "addSkill", "addAgent", "removeSkill", "removeAgent", "copySkill", "copyAgent", "addHook", "removeHook", "removeDeadHooks"}

func seedTransaction(t *testing.T) (tempHome, roots.Roots) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/settings.json", `{"permissions":{"deny":["Bash"]}}`)
	claude := []usage.CLI{inventory.Claude}
	must(AddSkill(r, claude, "existing-skill", "Synthetic skill", ""))
	must(AddAgent(r, claude, "existing-agent", "Synthetic agent", "Synthetic instructions."))
	for _, name := range []string{"missing-first.sh", "missing-second.sh"} {
		must(AddHook(r, claude, "Stop", nil, h.path(name), nil))
	}
	h.write(".spacevibe/journal.json", "[]")
	return h, r
}

func runOperation(t *testing.T, op operation, r roots.Roots) error {
	t.Helper()
	snap := inventory.Read(r)
	itemID := func(kind inventory.Kind) string {
		for _, it := range snap.Items {
			if it.Kind == kind && it.CLI == inventory.Claude {
				return it.ID
			}
		}
		t.Fatalf("no claude %s", kind)
		return ""
	}
	both := []usage.CLI{inventory.Claude, inventory.Codex}
	var err error
	switch op {
	case "rule":
		_, err = EditJSON(r, r.Claude.HookFile, "Changed Bash from deny to allow (global)", nil, func(d *ojson.Document) (*ojson.Document, error) {
			return d.Set(ojson.Path("permissions", "deny"), ojson.Array())
		})
	case "addSkill":
		_, err = AddSkill(r, both, "new-skill", "Synthetic", "")
	case "addAgent":
		_, err = AddAgent(r, both, "new-agent", "Synthetic", "")
	case "removeSkill":
		_, err = RemoveItem(r, itemID(inventory.KindSkill))
	case "removeAgent":
		_, err = RemoveItem(r, itemID(inventory.KindAgent))
	case "copySkill":
		_, err = CopyToOther(r, itemID(inventory.KindSkill))
	case "copyAgent":
		_, err = CopyToOther(r, itemID(inventory.KindAgent))
	case "addHook":
		_, err = AddHook(r, both, "Stop", nil, "echo synthetic", nil)
	case "removeHook":
		_, err = RemoveItem(r, snap.Hooks[0].ID)
	case "removeDeadHooks":
		dead := 0
		for _, h := range snap.Hooks {
			if h.CLI == inventory.Claude && h.Dead {
				dead++
			}
		}
		if dead != 2 {
			t.Fatalf("%d dead hooks, want 2", dead)
		}
		_, err = RemoveDeadHooks(r, inventory.Claude)
	}
	return err
}

// contents are all agent configuration bytes, including copied skill files; empty parent folders are harmless.
func contents(t *testing.T, r roots.Roots) map[string]string {
	t.Helper()
	out := map[string]string{}
	for _, base := range []string{r.Claude.Root, r.Codex.Root} {
		_ = filepath.WalkDir(base, func(p string, d fs.DirEntry, err error) error {
			if err == nil && d.Type().IsRegular() {
				data, rerr := os.ReadFile(p)
				if rerr != nil {
					t.Fatal(rerr)
				}
				out[p] = string(data)
			}
			return nil
		})
	}
	return out
}

func sameContents(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if bv, ok := b[k]; !ok || bv != v {
			return false
		}
	}
	return true
}

// Swift: MutationTransactionTests.swift "corrupt history refuses every mutation before touching configuration"
func TestCorruptJournalRefusesEveryMutation(t *testing.T) {
	for _, op := range allOperations {
		t.Run(string(op), func(t *testing.T) {
			h, r := seedTransaction(t)
			before := contents(t, r)
			trash := names(trashDir(r))
			h.write(".spacevibe/journal.json", "{ invalid history")
			err := runOperation(t, op, r)
			if m := wantErr(t, err, 409); m != UnreadableMessage {
				t.Errorf("message %q", m)
			}
			if !sameContents(contents(t, r), before) || !slicesEqual(names(trashDir(r)), trash) || h.read(".spacevibe/journal.json") != "{ invalid history" {
				t.Error("a refused mutation changed something")
			}
		})
	}
}

func slicesEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// Swift: MutationTransactionTests.swift "journal persistence failure restores every mutation, including shared hook backups"
func TestPersistenceFailureRestoresEveryMutation(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root ignores folder permissions")
	}
	for _, op := range allOperations {
		t.Run(string(op), func(t *testing.T) {
			h, r := seedTransaction(t)
			before := contents(t, r)
			// Preflight can read the journal and mutations can save backups in the existing writable trash. Only
			// creating the atomic journal temp file fails, after the config mutation completed.
			if err := os.Chmod(r.Data, 0o500); err != nil {
				t.Fatal(err)
			}
			defer os.Chmod(r.Data, 0o700)
			err := runOperation(t, op, r)
			m := wantErr(t, err, 500)
			if !strings.Contains(m, "journal.json.spacevibe-") || m == RollbackFailureMessage {
				t.Errorf("message %q", m)
			}
			if !sameContents(contents(t, r), before) || h.read(".spacevibe/journal.json") != "[]" {
				t.Error("the mutation was not restored")
			}
			_ = filepath.WalkDir(h.root, func(p string, d fs.DirEntry, err error) error {
				if err == nil && strings.Contains(p, ".spacevibe-") && strings.HasSuffix(p, ".tmp") {
					t.Errorf("stray temp file %s", p)
				}
				return nil
			})
		})
	}
}

// Swift: MutationTransactionTests.swift "a journal that fails after preflight restores a symlink target and its mode"
func TestFailureAfterPreflightRestoresSymlinkTarget(t *testing.T) {
	h, r := seedTransaction(t)
	target := h.write("dotfiles/settings.json", "{}\n")
	if err := os.Chmod(target, 0o640); err != nil {
		t.Fatal(err)
	}
	link := h.symlink(target, ".claude/linked-settings.json")
	_, err := EditJSON(r, link, "Synthetic edit", nil, func(d *ojson.Document) (*ojson.Document, error) {
		// This closure runs after the journal preflight, before the config mutation.
		journal := filepath.Join(r.Data, "journal.json")
		if err := os.Remove(journal); err != nil {
			t.Fatal(err)
		}
		if err := os.Mkdir(journal, 0o755); err != nil {
			t.Fatal(err)
		}
		return d.Set(ojson.Path("model"), ojson.String("synthetic"))
	})
	if m := wantErr(t, err, 409); m != UnreadableMessage {
		t.Errorf("message %q", m)
	}
	if h.read("dotfiles/settings.json") != "{}\n" || h.mode(target) != 0o640 {
		t.Error("target or its mode not restored")
	}
	if l, _ := os.Readlink(link); l != target {
		t.Errorf("link now %q", l)
	}
}

// Swift: MutationTransactionTests.swift "rollback failure preserves a concurrent edit and still restores the other operations"
// G-fix.9: the original error stays reachable behind the fixed rollback sentence.
func TestRollbackFailurePreservesConcurrentEdit(t *testing.T) {
	h, r := seedTransaction(t)
	codex := h.write(".codex/config.toml", "model = \"before\"\n")
	err := WithLock(r, func(tx *Tx) error {
		if err := tx.PrepareMutation(); err != nil {
			return err
		}
		set := func(text string) TextChange { return func(*string) (*string, error) { return &text, nil } }
		first, err := tx.Apply(codex, nil, set("model = \"after\"\n"))
		if err != nil || first == nil {
			t.Fatalf("first apply: %v", err)
		}
		op, err := tx.Apply(r.Claude.HookFile, nil, set("{}\n"))
		if err != nil || op == nil {
			t.Fatalf("second apply: %v", err)
		}
		h.write(".claude/settings.json", "concurrent writer\n")
		h.write(".spacevibe/journal.json", "{ now corrupt")
		_, err = tx.RecordMutation("Synthetic edit", []Op{*first, *op})
		return err
	})
	if m := wantErr(t, err, 500); m != RollbackFailureMessage {
		t.Errorf("message %q", m)
	}
	if !errors.Is(err, coreerr.NewStatus(UnreadableMessage, 409)) {
		t.Error("the original error is not reachable behind the rollback failure")
	}
	if h.read(".claude/settings.json") != "concurrent writer\n" || h.read(".codex/config.toml") != "model = \"before\"\n" {
		t.Error("the concurrent edit was overwritten or the other operation was not restored")
	}
}
