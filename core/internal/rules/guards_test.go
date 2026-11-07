package rules

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// WriteGuardTests.swift: the three tests that go through RulesStore (a project .claude that is a link, a settings file
// that is a link, the controls that still work). The other eight are in the mutate package.

func folderNames(t *testing.T, dir string) []string {
	t.Helper()
	entries, _ := os.ReadDir(dir)
	out := make([]string, len(entries))
	for i, e := range entries {
		out[i] = e.Name()
	}
	return out
}

func sameNames(a, b []string) bool { return strings.Join(a, "|") == strings.Join(b, "|") }

// Swift: WriteGuardTests.swift "a project whose .claude is a link to another folder is refused (409) and that folder is untouched"
func TestClaudeFolderLinkEscapes(t *testing.T) {
	sb := newSandbox(t)
	project := sb.path("proj")
	sb.write("elsewhere/settings.json", "{\"model\":\"theirs\"}\n")
	sb.write("elsewhere/settings.local.json", "{\"model\":\"theirs-local\"}\n")
	elsewhere := sb.path("elsewhere")
	if err := os.MkdirAll(project, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(elsewhere, filepath.Join(project, ".claude")); err != nil {
		t.Fatal(err)
	}
	store := NewStore(sb.r, func() []string { return []string{project} })
	before := folderNames(t, elsewhere)

	for _, scope := range []Scope{ProjectScope(project), LocalScope(project)} {
		_, err := store.AddRule(scope, Allow, "Bash(ls:*)")
		wantErr(t, err, 409)
	}
	if sb.read("elsewhere/settings.json") != "{\"model\":\"theirs\"}\n" || sb.read("elsewhere/settings.local.json") != "{\"model\":\"theirs-local\"}\n" {
		t.Error("the other folder's files changed")
	}
	if !sameNames(folderNames(t, elsewhere), before) {
		t.Error("the other folder gained or lost a file")
	}
	if len(historyOf(t, sb.r)) != 0 {
		t.Error("the journal is not empty")
	}
	listing, err := store.ListRules(ProjectScope(project))
	if err != nil || len(listing.Rules) != 0 || len(listing.Problems) != 1 {
		t.Errorf("listing %+v %v", listing, err)
	}
}

// Swift: WriteGuardTests.swift "a project settings file that is a link to another file is refused (409) and that file is untouched"
func TestSettingsFileLinkEscapes(t *testing.T) {
	sb := newSandbox(t)
	project := sb.path("proj")
	other := sb.write("other.json", "{\"permissions\":{\"allow\":[\"Read\"]}}\n")
	if err := os.MkdirAll(filepath.Join(project, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"settings.json", "settings.local.json"} {
		if err := os.Symlink(other, filepath.Join(project, ".claude", name)); err != nil {
			t.Fatal(err)
		}
	}
	store := NewStore(sb.r, func() []string { return []string{project} })
	before := sb.read("other.json")
	for _, scope := range []Scope{ProjectScope(project), LocalScope(project)} {
		_, err := store.AddRule(scope, Deny, "Bash(rm:*)")
		wantErr(t, err, 409)
		if _, err := store.RemoveRule(scope, Allow, "Read"); err == nil {
			t.Error("remove through a link succeeded")
		}
	}
	if sb.read("other.json") != before || len(historyOf(t, sb.r)) != 0 {
		t.Error("the linked file or the journal changed")
	}
}

// Swift: WriteGuardTests.swift "a normal project is still edited, and the global settings file may be a link (followed)"
func TestControlsStillWork(t *testing.T) {
	sb := newSandbox(t)
	project := sb.path("proj")
	if err := os.MkdirAll(filepath.Join(project, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	store := NewStore(sb.r, func() []string { return []string{project} })
	must(store.AddRule(ProjectScope(project), Allow, "Bash(ls:*)"))
	must(store.AddRule(LocalScope(project), Ask, "Bash(git push:*)"))
	if !strings.Contains(sb.read("proj/.claude/settings.json"), "Bash(ls:*)") || !strings.Contains(sb.read("proj/.claude/settings.local.json"), "Bash(git push:*)") {
		t.Error("the project files were not edited")
	}
	dotfiles := sb.write("dotfiles/claude-settings.json", "{}\n")
	if err := os.MkdirAll(sb.r.Claude.Root, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(dotfiles, sb.r.Claude.HookFile); err != nil {
		t.Fatal(err)
	}
	must(store.AddRule(Global, Allow, "Read"))
	if !strings.Contains(sb.read("dotfiles/claude-settings.json"), `"Read"`) {
		t.Error("the link target was not edited")
	}
	if target, err := os.Readlink(sb.r.Claude.HookFile); err != nil || target != dotfiles {
		t.Errorf("not a link to the dotfiles any more: %q %v", target, err)
	}
}
