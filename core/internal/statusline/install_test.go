package statusline

import (
	"os"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/ojson"
)

func (h tempHome) install(binary string) *mutate.Entry {
	h.t.Helper()
	entry, err := Install(h.cfg(), h.roots(), binary)
	if err != nil {
		h.t.Fatal(err)
	}
	return entry
}

func (h tempHome) statusLine() (command string, doc ojson.Value) {
	h.t.Helper()
	parsed, err := ojson.ParseString(h.text(".claude/settings.json"))
	if err != nil {
		h.t.Fatal(err)
	}
	command, _ = stringMember(mustMember(h.t, parsed.Root(), "statusLine"), "command")
	return command, parsed.Root()
}

func mustMember(t *testing.T, v ojson.Value, key string) ojson.Value {
	t.Helper()
	m, ok := v.Member(key)
	if !ok {
		t.Fatalf("no %q", key)
	}
	return m
}

// Swift: LimitsStatuslineTests.swift "setup preserves the original command and unrelated bytes; repeated setup is a no-op and Undo restores"
func TestInstallPreservesAndUndoes(t *testing.T) {
	h := newTempHome(t)
	original := `{ "permissions": {"allow": ["Read"]}, "statusLine": {"type":"command","command":"printf 'hello'","padding":2}, "other":true }`
	settings := h.write(".claude/settings.json", original)
	binary := h.write("fake-binary", "synthetic executable")

	entry := h.install(binary)
	if entry == nil {
		t.Fatal("first install made no journal entry")
	}
	changed := h.text(".claude/settings.json")
	if !strings.Contains(changed, `"permissions": {"allow": ["Read"]}`) {
		t.Errorf("unrelated bytes changed:\n%s", changed)
	}
	command, root := h.statusLine()
	padding, _ := mustMember(t, root, "statusLine").Member("padding")
	if text, _ := padding.NumberText(); text != "2" {
		t.Errorf("padding = %v", padding)
	}
	if !strings.HasSuffix(command, Quote("printf 'hello'")) {
		t.Errorf("command does not end with the quoted original: %s", command)
	}
	if want := WrapperCommand(h.roots(), "printf 'hello'"); command != want {
		t.Errorf("command = %s\nwant      %s", command, want)
	}
	if !strings.HasPrefix(command, Quote(h.path(".spacevibe/bin/spacevibe"))+" statusline capture "+Quote(h.path(".spacevibe"))+" "+Quote(h.path(".claude"))+" ") {
		t.Errorf("wrapper prefix: %s", command)
	}
	if again := h.install(binary); again != nil {
		t.Fatalf("repeated setup made an entry: %+v", again)
	}
	if err := Undo(h.roots(), entry.ID); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(settings); string(got) != original {
		t.Fatalf("Undo did not restore:\n%s", got)
	}
}

func TestInstallCopiesTheExecutable(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/settings.json", "{}")
	binary := h.write("binary", "first build")
	h.install(binary)
	dest := Executable(h.roots())
	if dest != h.path(".spacevibe/bin/spacevibe") {
		t.Fatalf("Executable = %s", dest)
	}
	if h.text(".spacevibe/bin/spacevibe") != "first build" || h.mode(".spacevibe/bin") != 0o700 || h.mode(".spacevibe/bin/spacevibe") != 0o700 {
		t.Fatalf("copy %q, folder %o, file %o", h.text(".spacevibe/bin/spacevibe"), h.mode(".spacevibe/bin"), h.mode(".spacevibe/bin/spacevibe"))
	}
	// A reinstall refreshes the copy even when the settings are already right.
	h.write("binary", "second build")
	if entry := h.install(binary); entry != nil {
		t.Fatalf("entry = %+v", entry)
	}
	if h.text(".spacevibe/bin/spacevibe") != "second build" {
		t.Fatalf("copy not refreshed: %q", h.text(".spacevibe/bin/spacevibe"))
	}
	// Installing from the installed copy leaves it alone.
	if h.install(dest); h.text(".spacevibe/bin/spacevibe") != "second build" {
		t.Fatal("the copy was overwritten by itself")
	}
}

// Swift: LimitsStatuslineTests.swift "managed subdirectory links cannot redirect collector or installer writes" (the installer half)
func TestInstallManagedDirectoryLink(t *testing.T) {
	h := newTempHome(t)
	outside := newTempHome(t)
	h.write(".claude/settings.json", "{}")
	binary := h.write("fake-binary", "synthetic")
	sentinel := outside.write("sentinel.json", "keep")
	if err := os.MkdirAll(h.path(".spacevibe"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside.root, h.path(".spacevibe/bin")); err != nil {
		t.Fatal(err)
	}
	if _, err := Install(h.cfg(), h.roots(), binary); err == nil {
		t.Fatal("install wrote through a link")
	}
	entries, _ := os.ReadDir(outside.root)
	if len(entries) != 1 || entries[0].Name() != "sentinel.json" {
		t.Fatalf("the folder outside holds %v", entries)
	}
	if got, _ := os.ReadFile(sentinel); string(got) != "keep" || h.text(".claude/settings.json") != "{}" {
		t.Fatal("something outside the data folder, or the settings, changed")
	}
}

// G-fix.19: a wrapper is replaced, never wrapped again, whichever data root or spelling it carries.
func TestInstallNeverDoubleWraps(t *testing.T) {
	const user = `printf 'it'"'"'s mine'`
	cases := map[string]string{
		"legacy Swift collector":     Quote("/Users/me/.reins/bin/reins-statusline") + " --capture " + Quote("/Users/me/.reins") + " " + Quote("/Users/me/.claude") + " " + Quote(user),
		"spacevibe, moved data root": Quote("/old/data/bin/spacevibe") + " statusline capture " + Quote("/old/data") + " " + Quote("/old/claude") + " " + Quote(user),
		"twice wrapped by Swift":     Quote("/a/bin/reins-statusline") + " --capture '/a' '/c' " + Quote(Quote("/b/bin/reins-statusline")+" --capture '/b' '/c' "+Quote(user)),
		"legacy around a spacevibe":  Quote("/a/bin/reins-statusline") + " --capture '/a' '/c' " + Quote(Quote("/b/bin/spacevibe")+" statusline capture '/b' '/c' "+Quote(user)),
		"the user's own, no wrapper": user,
	}
	for name, command := range cases {
		t.Run(name, func(t *testing.T) {
			h := newTempHome(t)
			doc := `{"statusLine":{"type":"command","command":` + jsonString(t, command) + `}}`
			h.write(".claude/settings.json", doc)
			if entry := h.install(h.write("bin", "x")); entry == nil {
				t.Fatal("no entry")
			}
			got, _ := h.statusLine()
			if want := WrapperCommand(h.roots(), user); got != want {
				t.Fatalf("command = %s\nwant      %s", got, want)
			}
			if h.install(h.path("bin")) != nil {
				t.Fatal("a second install changed the settings")
			}
		})
	}
}

func jsonString(t *testing.T, s string) string {
	t.Helper()
	text, err := ojson.Pretty(ojson.String(s))
	if err != nil {
		t.Fatal(err)
	}
	return strings.TrimSpace(text)
}

func TestInstallStatusLineShapes(t *testing.T) {
	cases := map[string]struct {
		settings string
		original string // what the wrapper delegates to; "" for none
		refused  bool
	}{
		"no settings file":   {settings: "", original: ""},
		"empty object":       {settings: "{}", original: ""},
		"null status line":   {settings: `{"statusLine":null,"keep":1}`, original: ""},
		"command with quote": {settings: `{"statusLine":{"type":"command","command":"echo 'a'"}}`, original: "echo 'a'"},
		"empty command":      {settings: `{"statusLine":{"type":"command","command":""}}`, original: ""},
		"not a command type": {settings: `{"statusLine":{"type":"text","command":"x"}}`, refused: true},
		"no command":         {settings: `{"statusLine":{"type":"command"}}`, refused: true},
		"string":             {settings: `{"statusLine":"x"}`, refused: true},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			h := newTempHome(t)
			if c.settings != "" {
				h.write(".claude/settings.json", c.settings)
			}
			entry, err := Install(h.cfg(), h.roots(), h.write("bin", "x"))
			if c.refused {
				if err == nil {
					t.Fatal("no error")
				}
				if h.text(".claude/settings.json") != c.settings {
					t.Fatal("settings changed")
				}
				return
			}
			if err != nil || entry == nil {
				t.Fatalf("entry %v, err %v", entry, err)
			}
			if got, _ := h.statusLine(); got != WrapperCommand(h.roots(), c.original) {
				t.Fatalf("command = %s", got)
			}
		})
	}
}

func TestUnwrapIgnoresLookalikes(t *testing.T) {
	for _, command := range []string{
		"",
		"echo hi",
		Quote("/a/bin/spacevibe") + " statusline capture '/d' '/c'",                // too few words
		Quote("/a/bin/spacevibe") + " statusline capture '/d' '/c' 'x' extra",      // too many
		Quote("/a/bin/other") + " statusline capture '/d' '/c' 'x'",                // another program
		Quote("/a/spacevibe") + " statusline capture '/d' '/c' 'x'",                // not in a bin folder
		Quote("bin/spacevibe") + " statusline capture '/d' '/c' 'x'",               // not absolute
		Quote("/a/bin/spacevibe") + " statusline capture 'd' '/c' 'x'",             // data not absolute
		Quote("/a/bin/spacevibe") + " statusline capture '/d' '/c' 'x' ; rm -rf /", // trailing command
		Quote("/a/bin/spacevibe") + " statusline capture '/d' '/c' $(x)",           // not a Quote() word
		Quote("/a/bin/spacevibe") + "  statusline capture '/d' '/c' 'x'",           // doubled space
		Quote("/a/bin/spacevibe") + " statusline capture '/d' '/c' 'x' ",           // trailing space
		Quote("/a/bin/spacevibe") + " statusline capture '/d' '/c' 'unterminated",  // open quote
		Quote("/a/bin/reins-statusline") + " --capture '/d' '/c' 'x' 'y'",          // too many for legacy
	} {
		if inner, ok := unwrapOnce(command); ok {
			t.Errorf("unwrapOnce(%q) = %q, want no wrapper", command, inner)
		}
		if unwrap(command) != command {
			t.Errorf("unwrap(%q) changed it", command)
		}
	}
}

func TestQuoteRoundTrip(t *testing.T) {
	for _, s := range []string{"", "plain", "a b", "it's", "'", "''", `a\'b`, "$(x) `y` \"z\"", "new\nline", "é☃"} {
		w, ok := words(Quote(s))
		if !ok || len(w) != 1 || w[0] != s {
			t.Errorf("words(Quote(%q)) = %q, %v", s, w, ok)
		}
		if unwrap(WrapperCommand(newTempHome(t).roots(), s)) != s {
			t.Errorf("unwrap(wrapper(%q)) changed it", s)
		}
	}
	if Quote("it's") != `'it'\''s'` {
		t.Errorf("Quote(it's) = %s", Quote("it's"))
	}
}
