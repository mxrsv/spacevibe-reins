package rules

import (
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/ojson"
)

// seedTransaction is the "rule" slot of MutationTransactionTests.seed: a settings file with a deny, an empty journal,
// and a lock file and a trash folder that already exist and are writable.
func seedTransaction(t *testing.T) sandbox {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", `{"permissions":{"deny":["Bash"]}}`)
	sb.write(".spacevibe/journal.json", "[]")
	// The lock file exists from an earlier write: a data folder that cannot be written could not create it.
	sb.write(".spacevibe/"+fsx.LockFileName, "")
	if err := os.MkdirAll(filepath.Join(sb.r.Data, "trash"), 0o700); err != nil {
		t.Fatal(err)
	}
	return sb
}

// ruleOperation is the operation the Swift test ran for "rule".
func (sb sandbox) ruleOperation() error {
	_, err := sb.store.ChangeVerdict(Global, "Bash", Deny, Allow)
	return err
}

func (sb sandbox) contents() map[string]string {
	sb.t.Helper()
	out := map[string]string{}
	for _, base := range []string{sb.r.Claude.Root, sb.r.Codex.Root} {
		_ = filepath.WalkDir(base, func(p string, d fs.DirEntry, err error) error {
			if err == nil && d.Type().IsRegular() {
				data, rerr := os.ReadFile(p)
				if rerr != nil {
					sb.t.Fatal(rerr)
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

// Swift: MutationTransactionTests.swift "corrupt history refuses every mutation before touching configuration" (rule)
func TestCorruptJournalRefusesRuleWrite(t *testing.T) {
	sb := seedTransaction(t)
	before := sb.contents()
	trash, _ := os.ReadDir(filepath.Join(sb.r.Data, "trash"))
	sb.write(".spacevibe/journal.json", "{ invalid history")
	if m := wantErr(t, sb.ruleOperation(), 409); m != mutate.UnreadableMessage {
		t.Errorf("message %q", m)
	}
	after, _ := os.ReadDir(filepath.Join(sb.r.Data, "trash"))
	if !sameContents(sb.contents(), before) || len(after) != len(trash) || sb.read(".spacevibe/journal.json") != "{ invalid history" {
		t.Error("a refused mutation changed something")
	}
}

// Swift: MutationTransactionTests.swift "journal persistence failure restores every mutation, including shared hook backups" (rule)
func TestPersistenceFailureRestoresRuleWrite(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root ignores folder permissions")
	}
	sb := seedTransaction(t)
	before := sb.contents()
	// Preflight can read the journal and mutations can save backups in the existing writable trash. Only creating the
	// atomic journal temp file fails, after the settings mutation completed.
	if err := os.Chmod(sb.r.Data, 0o500); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(sb.r.Data, 0o700)
	m := wantErr(t, sb.ruleOperation(), 500)
	if !strings.Contains(m, "journal.json.spacevibe-") || m == mutate.RollbackFailureMessage {
		t.Errorf("message %q", m)
	}
	if !sameContents(sb.contents(), before) || sb.read(".spacevibe/journal.json") != "[]" {
		t.Error("the mutation was not restored")
	}
	_ = filepath.WalkDir(sb.root, func(p string, d fs.DirEntry, err error) error {
		if err == nil && strings.Contains(p, ".spacevibe-") && strings.HasSuffix(p, ".tmp") {
			t.Errorf("stray temp file %s", p)
		}
		return nil
	})
}

// Swift: WriteConcurrencyTests.swift "50 concurrent rule additions to one settings.json all land, each with its own journal entry"
func TestConcurrentSettingsAppends(t *testing.T) {
	sb := newSandbox(t)
	settings := sb.write(".claude/settings.json", "{\n  \"model\": \"keep\"\n}\n")
	var wg sync.WaitGroup
	var refused atomic.Int32
	var succeeded atomic.Int32
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			rule := "Bash(rule-" + strconv.Itoa(i) + ":*)"
			if _, err := sb.store.AddRule(Global, Allow, rule); err != nil {
				refused.Add(1)
				return
			}
			succeeded.Add(1)
		}()
	}
	wg.Wait()
	// In one process the lock serializes the writers, so none may be refused; a refusal would be a 409, never a silent drop.
	if succeeded.Load() != 50 || refused.Load() != 0 {
		t.Fatalf("%d succeeded, %d refused", succeeded.Load(), refused.Load())
	}
	allowed, _ := permissionList(t, settings, Allow)
	seen := map[string]bool{}
	for _, a := range allowed {
		seen[a] = true
	}
	for i := 0; i < 50; i++ {
		if !seen["Bash(rule-"+strconv.Itoa(i)+":*)"] {
			t.Errorf("rule %d is missing", i)
		}
	}
	if len(allowed) != 50 {
		t.Errorf("%d rules in the file", len(allowed))
	}
	if model, ok := parsedRoot(t, settings).Member("model"); !ok || !model.Equal(ojson.String("keep")) {
		t.Error("model was not kept")
	}
	if n := len(historyOf(t, sb.r)); n != 50 {
		t.Errorf("%d journal entries", n)
	}
	if stray := strayTemp(filepath.Dir(settings), sb.r.Data); len(stray) != 0 {
		t.Errorf("stray temp files %v", stray)
	}
}
