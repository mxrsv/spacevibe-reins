//go:build unix

package rules

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/inventory"
)

// G-fix.1 and G-fix.18. A macOS privacy denial is simulated with chmod 000 on a folder: a stat below it fails with
// EACCES, so the path reads as "unknown", not as "missing". Skipped for root, which ignores folder permissions.

// deny removes every permission of dir for the test and puts them back when it ends, so the temp folder can be removed.
func deny(t *testing.T, dir string) {
	t.Helper()
	if os.Geteuid() == 0 {
		t.Skip("root ignores folder permissions")
	}
	info, err := os.Stat(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, info.Mode().Perm()) })
}

// guardedProject is a discovered project whose folder is denied: <home>/guarded/proj.
func guardedProject(t *testing.T) (sandbox, string, func()) {
	sb := newSandbox(t)
	proj := sb.project("guarded/proj")
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Read"],"deny":["Bash(rm *)"]}}`)
	guard := sb.path("guarded")
	info, _ := os.Stat(guard)
	deny(t, guard)
	return sb, proj, func() { _ = os.Chmod(guard, info.Mode().Perm()) }
}

// G-fix.1: a project folder that cannot be looked at must not abort the listing or read as "no rules".
func TestUnreadableProjectIsNotNoRules(t *testing.T) {
	sb, proj, restore := guardedProject(t)
	if got := inventory.DiscoverProjects(sb.r); len(got) != 1 || got[0] != proj {
		t.Fatalf("discovery lost the denied project: %v", got)
	}

	// The merged list keeps the global rules and says the project is not readable.
	listing, err := sb.store.ListRules(ScopesFor(proj)...)
	if err != nil {
		t.Fatalf("the listing aborted: %v", err)
	}
	if len(listing.Rules) != 2 || !listing.NotReadable || len(listing.Problems) != 2 {
		t.Fatalf("listing %+v", listing)
	}
	for _, p := range listing.Problems {
		if !strings.HasSuffix(p, notReadableSentence) {
			t.Errorf("problem %q", p)
		}
	}

	// The snapshot of that project is a normal result with a distinct state.
	s := newService(t, sb)
	snap, err := s.Snapshot(context.Background(), SnapshotParams{Scope: KindProject, Dir: dirPtr(proj)})
	if err != nil {
		t.Fatalf("the snapshot aborted: %v", err)
	}
	if snap.Scope != KindProject || !snap.NotReadable || snap.GlobalNotReadable || snap.Exists || len(snap.Rules) != 0 || snap.GlobalRuleCount != 2 {
		t.Errorf("snapshot %+v", snap)
	}
	if len(snap.Problems) != 1 || snap.Problems[0] != ".claude/settings.json"+notReadableSentence {
		t.Errorf("problems %v", snap.Problems)
	}
	if strings.Contains(strings.Join(snap.Problems, "|"), sb.root) {
		t.Error("the problem names the folder")
	}

	// Nothing may be written there: not a preview, not a cell write, not a rule.
	ctx := context.Background()
	_, err = s.Preview(ctx, CapabilityParams{Scope: KindProject, Dir: dirPtr(proj), Capability: Read, Verdict: Deny})
	wantErr(t, err, 409)
	_, err = s.SetCapability(ctx, CapabilityParams{Scope: KindLocal, Dir: dirPtr(proj), Capability: Read, Verdict: Deny})
	wantErr(t, err, 409)
	_, err = s.Add(ctx, RuleParams{Scope: KindProject, Dir: dirPtr(proj), Verdict: Allow, Rule: "Read"})
	if m := wantErr(t, err, 409); strings.Contains(m, sb.root) || !strings.Contains(m, "not readable") {
		t.Errorf("message %q", m)
	}
	restore()
	for _, name := range []string{"settings.json", "settings.local.json"} {
		if _, err := os.Lstat(filepath.Join(proj, ".claude", name)); err == nil {
			t.Errorf("%s was created", name)
		}
	}
	if len(historyOf(t, sb.r)) != 0 {
		t.Error("the journal is not empty")
	}
}

// G-fix.1: a project folder deleted since discovery is a 404 when it is the one asked for, and a problem line (not an
// abort) in a merged listing.
func TestDeletedProjectIsNotFoundOnlyWhenSelected(t *testing.T) {
	sb := newSandbox(t)
	proj := sb.project("gone")
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Read"]}}`)
	store := NewStore(sb.r, func() []string { return []string{proj} })
	if err := os.RemoveAll(proj); err != nil {
		t.Fatal(err)
	}

	merged, err := store.ListRules(ScopesFor(proj)...)
	if err != nil {
		t.Fatalf("the merged listing aborted: %v", err)
	}
	if len(merged.Rules) != 1 || len(merged.Problems) != 2 || merged.NotReadable {
		t.Errorf("merged %+v", merged)
	}
	_, err = store.ListRules(ProjectScope(proj))
	wantErr(t, err, 404)
	_, err = store.PreviewSetCapability(LocalScope(proj), Read, Deny)
	wantErr(t, err, 404)
	_, err = store.AddRule(ProjectScope(proj), Allow, "Read")
	wantErr(t, err, 404)

	s := NewService(sb.r)
	s.SetProjects([]string{proj})
	_, err = s.Snapshot(context.Background(), SnapshotParams{Scope: KindProject, Dir: dirPtr(proj)})
	wantErr(t, err, 404)
	global, err := s.Snapshot(context.Background(), SnapshotParams{Scope: KindGlobal})
	if err != nil || len(global.Rules) != 1 {
		t.Errorf("the global snapshot must not be affected: %+v %v", global, err)
	}
	if _, err := os.Lstat(filepath.Join(proj, ".claude")); err == nil {
		t.Error("a write recreated the deleted project")
	}
}

// G-fix.1: a settings file that exists but cannot be read, and one that sits below a denied folder, are not "no rules".
func TestUnreadableSettingsFileIsNotNoRules(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Read"]}}`)
	deny(t, sb.settings())
	listing, err := sb.store.ListRules(Global)
	if err != nil || len(listing.Rules) != 0 || !listing.NotReadable || len(listing.Problems) != 1 || !strings.HasSuffix(listing.Problems[0], "could not be read.") {
		t.Errorf("file without permission: %+v %v", listing, err)
	}
	_, err = sb.store.PreviewSetCapability(Global, Read, Deny)
	wantErr(t, err, 409)
	_, err = sb.store.SetCapability(Global, Read, Deny)
	wantErr(t, err, 409)

	below := newSandbox(t)
	below.write(".claude/settings.json", `{"permissions":{"allow":["Read"]}}`)
	deny(t, below.r.Claude.Root)
	listing, err = below.store.ListRules(Global)
	if err != nil || len(listing.Rules) != 0 || !listing.NotReadable || len(listing.Problems) != 1 || !strings.HasSuffix(listing.Problems[0], notReadableSentence) {
		t.Errorf("file below a denied folder: %+v %v", listing, err)
	}
	snap, err := newService(t, below).Snapshot(context.Background(), SnapshotParams{Scope: KindGlobal})
	if err != nil || !snap.NotReadable || !snap.GlobalNotReadable || snap.Exists {
		t.Errorf("snapshot %+v %v", snap, err)
	}
	_, err = below.store.AddRule(Global, Allow, "Edit")
	wantErr(t, err, 409)
}

// G-fix.18: a Codex config.toml or .rules file that cannot be read is "not readable", never the safe defaults.
func TestUnreadableCodexFilesAreNotDefaults(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".codex/config.toml", "sandbox_mode = \"danger-full-access\"\n# "+canary+"\n")
	sb.write(".codex/rules/a.rules", `prefix_rule(pattern=["x"], decision="forbidden")`)
	sb.write(".codex/rules/b.rules", `prefix_rule(pattern=["y"])`)
	deny(t, sb.path(".codex/config.toml"))
	deny(t, sb.path(".codex/rules/a.rules"))
	c := ReadCodexPermissions(sb.r)
	if !c.Present || !c.NotReadable || c.Model != ModelLegacy || c.Unrestricted {
		t.Errorf("config %+v", c)
	}
	if c.Rules.Files != 1 || c.Rules.Allow != 1 || c.Rules.Unreadable != 1 || c.Rules.FolderNotReadable {
		t.Errorf("rules %+v", c.Rules)
	}
	if len(c.Warnings) != 2 || !strings.Contains(c.Warnings[0], "config.toml could not be read") || !strings.Contains(c.Warnings[1], "1 Codex .rules file could not be read and is not counted") {
		t.Errorf("warnings %v", c.Warnings)
	}

	folder := newSandbox(t)
	folder.write(".codex/config.toml", "sandbox_mode = \"read-only\"\n")
	folder.write(".codex/rules/a.rules", `prefix_rule(pattern=["x"])`)
	deny(t, folder.path(".codex"))
	c = ReadCodexPermissions(folder.r)
	if c.Present || !c.NotReadable || !c.Rules.FolderNotReadable || c.Rules.Files != 0 {
		t.Errorf("below a denied folder: %+v", c)
	}
	if len(c.Warnings) != 2 || !strings.Contains(c.Warnings[1], "rules folder could not be read") {
		t.Errorf("warnings %v", c.Warnings)
	}
}
