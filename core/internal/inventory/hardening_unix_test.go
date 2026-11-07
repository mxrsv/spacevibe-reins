//go:build unix

package inventory

import (
	"os"
	"strings"
	"syscall"
	"testing"
	"time"
)

// withFIFORescue runs body; a regressed blocking reader fails the test instead of hanging the suite. If the
// read has not returned after a moment, a writer is opened to give it EOF, and needing that is itself a
// failure. Ported from ReadHardeningTests.swift withFIFORescue.
func withFIFORescue(t *testing.T, fifo string, body func()) {
	t.Helper()
	done := make(chan struct{})
	go func() { defer close(done); body() }()
	select {
	case <-done:
		return
	case <-time.After(500 * time.Millisecond):
	}
	t.Error("a regular-file reader must reject a FIFO without a writer")
	for {
		// ENXIO means the reader has not opened yet; retry so scheduler delays cannot strand it.
		if w, err := os.OpenFile(fifo, os.O_WRONLY|syscall.O_NONBLOCK, 0); err == nil {
			_ = w.Close()
		}
		select {
		case <-done:
			return
		case <-time.After(10 * time.Millisecond):
		}
	}
}

func mkfifo(t *testing.T, path string) {
	t.Helper()
	if err := syscall.Mkfifo(path, 0o600); err != nil {
		t.Fatalf("mkfifo: %v", err)
	}
}

// Swift: ReadHardeningTests.swift "inventory readers reject FIFOs and links to FIFOs without waiting for input" (linked: false, true)
func TestRejectFIFO(t *testing.T) {
	for _, linked := range []bool{false, true} {
		h := newTempHome(t)
		fifo := h.path("input")
		mkfifo(t, fifo)
		path := fifo
		if linked {
			path = h.path("input-link")
			if err := os.Symlink(fifo, path); err != nil {
				t.Fatal(err)
			}
		}
		withFIFORescue(t, fifo, func() {
			if _, ok := readData(path, 64); ok {
				t.Errorf("linked=%v: readData read a FIFO", linked)
			}
		})
		withFIFORescue(t, fifo, func() {
			if _, status := readJSON(path); status != jsonUnreadable {
				t.Errorf("linked=%v: FIFO status %v, want unreadable (not valid JSON, not missing)", linked, status)
			}
		})
		withFIFORescue(t, fifo, func() {
			if _, ok := readText(path, 64); ok {
				t.Errorf("linked=%v: readText read a FIFO", linked)
			}
		})
	}
}

// Swift: ReadHardeningTests.swift "a discovered project with FIFO settings reports unreadable and preserves other inventory"
func TestDiscoveredProjectFIFO(t *testing.T) {
	h := newTempHome(t)
	project := h.path("project")
	h.write("project/.claude/skills/example/SKILL.md", "---\nname: example\n---\n")
	h.write(".codex/config.toml", "[projects.\""+project+"\"]\ntrust_level = \"trusted\"\n")
	fifo := project + "/.claude/settings.json"
	mkfifo(t, fifo)
	r := h.roots()
	var snapshot Snapshot
	withFIFORescue(t, fifo, func() { snapshot = Read(r) })
	if it := item(snapshot, "example"); it == nil || it.Project == nil || *it.Project != project {
		t.Errorf("the project skill is missing: %+v", snapshot.Items)
	}
	found := false
	for _, p := range snapshot.Problems {
		found = found || (strings.Contains(p, fifo) && strings.Contains(p, "cannot be read"))
	}
	if !found {
		t.Errorf("problems = %q", snapshot.Problems)
	}
}

func requireNotRoot(t *testing.T) {
	t.Helper()
	if os.Geteuid() == 0 {
		t.Skip("root ignores permission bits")
	}
}

// Swift: ReadHardeningTests.swift "a hook whose script sits under a folder that denies the lookup is not dead, and a problem says so"
func TestDeniedScriptIsNotDead(t *testing.T) {
	requireNotRoot(t)
	h := newTempHome(t)
	locked := h.path("locked")
	h.write("locked/hook.sh", "echo hi\n")
	h.write(".claude/settings.json", `{"hooks": {"Stop": [{"hooks": [
	  {"type": "command", "command": "sh '`+locked+`/hook.sh'"},
	  {"type": "command", "command": "sh '`+h.root+`/gone/missing.sh'"}
	]}]}}`)
	if err := os.Chmod(locked, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o755) })
	snapshot := Read(h.roots())
	if len(snapshot.Hooks) != 2 || snapshot.Hooks[0].Dead || !snapshot.Hooks[1].Dead {
		t.Errorf("dead = %+v", snapshot.Hooks)
	}
	var notes []string
	for _, p := range snapshot.Problems {
		if strings.Contains(p, "cannot be checked") {
			notes = append(notes, p)
		}
	}
	if len(notes) != 1 || strings.Contains(notes[0], "hook.sh") {
		t.Errorf("notes = %q (one note, naming the settings file, not the script)", notes)
	}
}

// Swift: ReadHardeningTests.swift "presence: only ENOENT and ENOTDIR mean missing"
func TestPresenceKinds(t *testing.T) {
	requireNotRoot(t)
	h := newTempHome(t)
	h.write("a/file.txt", "x")
	if pathPresence(h.path("a/file.txt")) != present || pathPresence(h.path("a/none.txt")) != missing || pathPresence(h.path("a/file.txt/below")) != missing {
		t.Error("present, missing, missing expected")
	}
	if err := os.Chmod(h.path("a"), 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(h.path("a"), 0o755) })
	if pathPresence(h.path("a/file.txt")) != unknown || exists(h.path("a/file.txt")) {
		t.Error("a denied folder must read as unknown, and not exist")
	}
}

// Swift: ReadHardeningTests.swift "a project under a folder Reins cannot stat is listed and reported as not readable, not dropped"
func TestDeniedProject(t *testing.T) {
	requireNotRoot(t)
	h := newTempHome(t)
	project := h.path("work/proj")
	h.write("work/proj/.claude/skills/s/SKILL.md", "---\nname: s\n---\n")
	h.write(".claude/projects/-enc-proj/s1.jsonl", `{"type":"user","cwd":"`+project+`"}`+"\n")
	r := h.roots()
	if got := DiscoverProjects(r); len(got) != 1 || got[0] != project {
		t.Fatalf("projects = %q", got)
	}
	if err := os.Chmod(project, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(project, 0o755) })
	if got := DiscoverProjects(r); len(got) != 1 || got[0] != project {
		t.Errorf("a denied project was dropped: %q", got)
	}
	snapshot := Read(r)
	found := false
	for _, p := range snapshot.Problems {
		found = found || (strings.HasPrefix(p, project) && strings.Contains(p, "cannot be read"))
	}
	if !found || len(snapshot.Items) != 0 {
		t.Errorf("problems = %q, items = %d", snapshot.Problems, len(snapshot.Items))
	}
}

// Swift: InventoryTests.swift "unreadable, oversized, and odd files never crash the read"
func TestHostileFiles(t *testing.T) {
	requireNotRoot(t)
	h := newTempHome(t)
	// A skill that is a folder, an agent that is a folder, a SKILL.md that is binary, a huge settings file, an unreadable one.
	if err := os.MkdirAll(h.path(".claude/skills/odd/SKILL.md"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(h.path(".claude/agents/folder.md"), 0o755); err != nil {
		t.Fatal(err)
	}
	h.write(".claude/skills/binary/SKILL.md", []byte{0xFF, 0xFE, 0x00, 0x2D, 0x2D, 0x2D, 0x80})
	h.write(".codex/hooks.json", []byte(strings.Repeat(" ", maxJSONBytes+10)))
	denied := h.write("work/p/.claude/settings.json", hookConfig("Stop", "echo denied"))
	h.write(".claude/projects/-enc-p/s1.jsonl", `{"type":"user","cwd":"`+h.path("work/p")+`"}`+"\n")
	if err := os.Chmod(denied, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(denied, 0o644) })

	inv := Read(h.roots())
	if itemByEntry(inv, "binary") == nil {
		t.Error("the binary SKILL.md was dropped")
	}
	if itemByEntry(inv, "odd") != nil || itemByEntry(inv, "folder.md") != nil {
		t.Error("a folder was read as a file")
	}
	var tooLarge, cannotRead bool
	for _, p := range inv.Problems {
		tooLarge = tooLarge || (strings.Contains(p, "hooks.json") && strings.Contains(p, "too large"))
		cannotRead = cannotRead || (strings.Contains(p, "work/p/.claude/settings.json") && strings.Contains(p, "cannot be read"))
	}
	if !tooLarge || !cannotRead {
		t.Errorf("problems = %q", inv.Problems)
	}
}
