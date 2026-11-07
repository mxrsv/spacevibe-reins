package mutate

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// Stands in for a secret value in settings: it must never show up in an error, a label or the journal.
const editCanary = "CANARY-sk-live-0123456789"

type sandbox struct {
	tempHome
	r        roots.Roots
	settings string
}

func newSandbox(t *testing.T) sandbox {
	h := newHome(t)
	return sandbox{h, h.roots(), filepath.Join(h.claude(), "settings.json")}
}

func (s sandbox) bytes(p ...string) string {
	s.t.Helper()
	path := s.settings
	if len(p) > 0 {
		path = p[0]
	}
	data, err := os.ReadFile(path)
	if err != nil {
		s.t.Fatal(err)
	}
	return string(data)
}

func (s sandbox) journalText() string {
	data, _ := os.ReadFile(filepath.Join(s.r.Data, "journal.json"))
	return string(data)
}

func (s sandbox) stray() []string { return strayTemp(s.claude(), s.r.Data) }

func addRule(rule string) JSONChange {
	return func(d *ojson.Document) (*ojson.Document, error) {
		if _, ok := d.Get(ojson.Key("permissions"), ojson.Key("allow")); !ok {
			return d.Set(ojson.Path("permissions", "allow"), ojson.Array(ojson.String(rule)))
		}
		return d.Append(ojson.String(rule), ojson.Path("permissions", "allow"))
	}
}

func noChange(d *ojson.Document) (*ojson.Document, error) { return d, nil }

// Swift: FileEditTests.swift "set then undo restores identical bytes and keeps the mode, for tab, space and CRLF files"
func TestSetThenUndo(t *testing.T) {
	for _, original := range []string{
		"{\n\t\"env\": {\"TOKEN\": \"" + editCanary + "\"},\n\t\"model\": \"x\"\n}\n",
		"{\n    \"model\": \"x\",\n    \"permissions\": {\n        \"allow\": [\"Read\"]\n    }\n}",
		"{\r\n  \"model\": \"x\"\r\n}\r\n",
	} {
		sb := newSandbox(t)
		sb.write(".claude/settings.json", original)
		if err := os.Chmod(sb.settings, 0o640); err != nil {
			t.Fatal(err)
		}
		before := sb.bytes()
		entry := must(EditJSON(sb.r, sb.settings, "Added allow rule Read (global)", nil, addRule("Read")))
		after := sb.bytes()
		if after == original {
			t.Error("file not changed")
		}
		if m := sb.mode(sb.settings); m != 0o640 {
			t.Errorf("mode %o", m)
		}
		if strings.Contains(original, "\r\n") && !(strings.Contains(after, "\r\n") && !strings.Contains(strings.ReplaceAll(after, "\r\n", ""), "\n")) {
			t.Errorf("CRLF not kept: %q", after)
		}
		if strings.Contains(original, "\t") && !strings.Contains(after, "\t\"model\"") {
			t.Errorf("tab not kept: %q", after)
		}
		parsed := jsonObject(t, after)
		allow, _ := parsed["permissions"].(map[string]any)["allow"].([]any)
		found := false
		for _, a := range allow {
			found = found || a == "Read"
		}
		if !found || parsed["model"] != "x" {
			t.Errorf("parsed %v", parsed)
		}
		if label := must(Undo(sb.r, entry.ID)); label != "Added allow rule Read (global)" {
			t.Errorf("label %q", label)
		}
		if sb.bytes() != before || sb.mode(sb.settings) != 0o640 || len(sb.stray()) != 0 {
			t.Error("undo did not restore the bytes, the mode, or left a temp file")
		}
	}
}

// Swift: FileEditTests.swift "undo is refused once the file changed, and leaves the hand edit alone"
func TestUndoRefusedAfterHandEdit(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", "{}\n")
	entry := must(EditJSON(sb.r, sb.settings, "Added", nil, addRule("Read")))
	sb.write(".claude/settings.json", "{\"model\":\"hand-edited\"}\n")
	_, err := Undo(sb.r, entry.ID)
	if m := wantErr(t, err, 409); !strings.Contains(m, "changed since") {
		t.Errorf("message %q", m)
	}
	if sb.bytes() != "{\"model\":\"hand-edited\"}\n" || historyOf(t, sb.r)[0].Undone {
		t.Error("state changed")
	}
}

// Swift: FileEditTests.swift "a second undo of the same entry is refused"
func TestDoubleUndo(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", "{}\n")
	entry := must(EditJSON(sb.r, sb.settings, "Added", nil, addRule("Read")))
	must(Undo(sb.r, entry.ID))
	_, err := Undo(sb.r, entry.ID)
	if m := wantErr(t, err, 409); !strings.Contains(m, "already undone") {
		t.Errorf("message %q", m)
	}
	if sb.bytes() != "{}\n" {
		t.Error("file changed")
	}
}

// Swift: FileEditTests.swift "a validator that rejects the temp file leaves the target, the folder and the journal untouched"
func TestFailedWriteLeavesNothing(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", "{\"model\":\"x\"}\n")
	before := sb.bytes()
	next := "{\"model\":\"y\"}\n"
	_, err := Edit(sb.r, sb.settings, "Never",
		func(string) error { return coreerr.NewStatus("rejected", 409) },
		func(*string) (*string, error) { return &next, nil })
	if m := wantErr(t, err, 409); m != "rejected" {
		t.Errorf("message %q", m)
	}
	if sb.bytes() != before || len(sb.stray()) != 0 || len(trashFiles(sb.r)) != 0 || len(historyOf(t, sb.r)) != 0 {
		t.Errorf("left something: stray %v trash %v", sb.stray(), trashFiles(sb.r))
	}
	// A failing `change` is the same.
	_, err = Edit(sb.r, sb.settings, "Never", nil, func(*string) (*string, error) { return nil, coreerr.New("no") })
	if err == nil || sb.bytes() != before || len(sb.stray()) != 0 {
		t.Error("a failing change left something")
	}
}

// Swift: FileEditTests.swift "invalid JSON and wrong shapes are refused with a 409 that never quotes content"
func TestInvalidInputRefused(t *testing.T) {
	sb := newSandbox(t)
	for _, content := range []string{
		"{\"env\":{\"TOKEN\":\"" + editCanary + "\"} oops",
		"[\"" + editCanary + "\"]",
		"\"" + editCanary + "\"",
		"{\"a\":\"" + editCanary + "\",}",
	} {
		sb.write(".claude/settings.json", content)
		_, err := EditJSON(sb.r, sb.settings, "Never", nil, addRule("Read"))
		m := wantErr(t, err, 409)
		if strings.Contains(m, editCanary) || !strings.Contains(m, "Nothing was changed") || sb.bytes() != content {
			t.Errorf("message %q", m)
		}
	}
	if len(historyOf(t, sb.r)) != 0 || len(sb.stray()) != 0 {
		t.Error("journal or temp file left")
	}
	// The same file is also refused when the new bytes would not parse.
	sb.write(".claude/settings.json", "{}\n")
	broken := "{\"a\":" + editCanary
	_, err := Edit(sb.r, sb.settings, "Never",
		func(text string) error { _, err := ParseObject(text, sb.settings); return err },
		func(*string) (*string, error) { return &broken, nil })
	if m := wantErr(t, err, 409); strings.Contains(m, editCanary) {
		t.Errorf("message %q", m)
	}
	if sb.bytes() != "{}\n" {
		t.Error("file changed")
	}
}

// Swift: FileEditTests.swift "a symlinked settings file stays a symlink and the target is written"
func TestSymlinkKept(t *testing.T) {
	sb := newSandbox(t)
	target := sb.write("shared/settings.json", "{}\n")
	sb.symlink(target, ".claude/settings.json")
	if err := os.Chmod(target, 0o600); err != nil {
		t.Fatal(err)
	}
	entry := must(EditJSON(sb.r, sb.settings, "Added", nil, addRule("Read")))
	if l, _ := os.Readlink(sb.settings); l != target {
		t.Errorf("link now %q", l)
	}
	if !strings.Contains(sb.bytes(target), "\"Read\"") || sb.mode(target) != 0o600 {
		t.Error("target not written or mode changed")
	}
	must(Undo(sb.r, entry.ID))
	if l, _ := os.Readlink(sb.settings); l != target || sb.bytes(target) != "{}\n" || len(sb.stray()) != 0 {
		t.Error("undo did not restore the link target")
	}
}

// Swift: FileEditTests.swift "a link to nothing is refused instead of being replaced"
func TestDanglingLink(t *testing.T) {
	sb := newSandbox(t)
	sb.symlink(sb.path("missing.json"), ".claude/settings.json")
	_, err := EditJSON(sb.r, sb.settings, "Never", nil, addRule("Read"))
	wantErr(t, err, 409)
	if _, err := os.Readlink(sb.settings); err != nil {
		t.Error("the link was replaced")
	}
}

// Swift: FileEditTests.swift "a missing file is created with mode 0600, and undo moves it to the trash"
func TestCreatedFile(t *testing.T) {
	sb := newSandbox(t)
	project := sb.path("proj/.claude/settings.local.json")
	entry := must(EditJSON(sb.r, project, "Added", nil, addRule("Bash(git status)")))
	if sb.mode(project) != 0o600 {
		t.Errorf("mode %o", sb.mode(project))
	}
	text := sb.bytes(project)
	allow := jsonObject(t, text)["permissions"].(map[string]any)["allow"].([]any)
	if !strings.HasSuffix(text, "}\n") || len(allow) != 1 || allow[0] != "Bash(git status)" {
		t.Errorf("text %q", text)
	}
	// Undo of a project file needs the project to be one discovery found; here the file is outside every managed
	// folder, so the containment check (G-fix.3) refuses it: see TestUndoRefusesOutsideTheManagedFolders. Use a CLI file.
	own := filepath.Join(sb.claude(), "settings.local.json")
	entry = must(EditJSON(sb.r, own, "Added", nil, addRule("Bash(git status)")))
	must(Undo(sb.r, entry.ID))
	if exists(own) {
		t.Error("file still there")
	}
	files := trashFiles(sb.r)
	if len(files) != 1 || !strings.HasSuffix(files[0], "/settings.local.json") {
		t.Errorf("trash %v", files)
	}
}

// Swift: FileEditTests.swift "a no-op writes nothing and records nothing, even for a missing file"
func TestNoOp(t *testing.T) {
	sb := newSandbox(t)
	if e := must(EditJSON(sb.r, sb.settings, "Never", nil, noChange)); e != nil || exists(sb.settings) {
		t.Error("a missing file was written")
	}
	sb.write(".claude/settings.json", "{\"model\":\"x\"}")
	before := sb.bytes()
	if e := must(EditJSON(sb.r, sb.settings, "Never", nil, noChange)); e != nil {
		t.Error("EditJSON no-op recorded")
	}
	if e := must(Edit(sb.r, sb.settings, "Never", nil, func(c *string) (*string, error) { return c, nil })); e != nil {
		t.Error("Edit no-op recorded")
	}
	if sb.bytes() != before || len(historyOf(t, sb.r)) != 0 {
		t.Error("file or journal changed")
	}
}

// Swift: FileEditTests.swift "a blank file counts as an empty object"
func TestBlankFile(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", "  \n")
	entry := must(EditJSON(sb.r, sb.settings, "Added", nil, addRule("Read")))
	if !strings.Contains(sb.bytes(), "\"Read\"") {
		t.Error("rule missing")
	}
	must(Undo(sb.r, entry.ID))
	if sb.bytes() != "  \n" {
		t.Errorf("after undo %q", sb.bytes())
	}
}

// Swift: FileEditTests.swift "text edit keeps bytes that Swift string equality would treat as equal"
func TestCanonicalEquivalence(t *testing.T) {
	sb := newSandbox(t)
	precomposed, decomposed := "caf\u00e9\n", "cafe\u0301\n"
	file := sb.write(".claude/notes.txt", precomposed)
	entry := must(Edit(sb.r, file, "Rewrote", nil, func(*string) (*string, error) { return &decomposed, nil }))
	if sb.bytes(file) != decomposed {
		t.Error("the decomposed text was not written")
	}
	must(Undo(sb.r, entry.ID))
	if sb.bytes(file) != precomposed {
		t.Error("undo did not restore the precomposed text")
	}
}

// Swift: FileEditTests.swift "a file that is not UTF-8 text is refused, not rewritten"
func TestBinaryRefused(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", "{\xff\xfe}")
	_, err := EditJSON(sb.r, sb.settings, "Never", nil, addRule("Read"))
	wantErr(t, err, 409)
	if sb.bytes() != "{\xff\xfe}" {
		t.Error("file rewritten")
	}
}

// Swift: FileEditTests.swift "a secret in the settings never appears in an error message, a label or the journal"
func TestEditCanaryNeverLeaks(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", "{\n  \"env\": {\"TOKEN\": \""+editCanary+"\"},\n  \"apiKeyHelper\": \"echo "+editCanary+"\"\n}\n")
	var seen []string
	first := must(EditJSON(sb.r, sb.settings, "Added allow rule Read (global)", nil, addRule("Read")))
	second := must(EditJSON(sb.r, sb.settings, "Added allow rule Edit (global)", nil, addRule("Edit")))
	for _, h := range historyOf(t, sb.r) {
		seen = append(seen, h.Label+" "+h.ID+" "+h.At)
	}
	// Hand edit with a broken file: every refusal message is collected.
	sb.write(".claude/settings.json", "{\"env\":{\"TOKEN\":\""+editCanary+"\"} oops")
	attempts := []func() error{
		func() error { _, err := EditJSON(sb.r, sb.settings, "x", nil, addRule("Read")); return err },
		func() error { _, err := Undo(sb.r, second.ID); return err },
		func() error { _, err := Undo(sb.r, first.ID); return err },
	}
	for _, attempt := range attempts {
		if err := attempt(); err != nil {
			seen = append(seen, err.Error())
		}
	}
	if len(seen) < 5 {
		t.Errorf("only %d texts collected", len(seen))
	}
	for _, s := range seen {
		if strings.Contains(s, editCanary) {
			t.Errorf("leak in %q", s)
		}
	}
	if strings.Contains(sb.journalText(), editCanary) {
		t.Error("the journal holds the secret")
	}
	// The old bytes do live in the trash (that is where undo reads them), never in the journal.
	if len(trashFiles(sb.r)) != 2 {
		t.Errorf("trash %v", trashFiles(sb.r))
	}
}

// Swift: FileEditTests.swift "under SPACEVIBE_TEST=1 an edit refuses a path under the real home"
func TestRefusesRealHome(t *testing.T) {
	sb := newSandbox(t)
	real, err := roots.RealHome()
	if err != nil {
		t.Skip(err)
	}
	file := filepath.Join(real, ".spacevibe-never-written", "settings.json")
	_, err = EditJSON(sb.r, file, "Never", nil, addRule("Read"))
	if m := wantErr(t, err, 500); !strings.Contains(m, "real home") {
		t.Errorf("message %q", m)
	}
	if exists(file) || exists(filepath.Dir(file)) {
		t.Error("something was written under the real home")
	}
}
