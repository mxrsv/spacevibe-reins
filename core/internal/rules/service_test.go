package rules

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/inventory"
)

// The RPC surface: params are checked, the settings-file path never reaches a message, and the project list is the one
// of the process.

func newService(t *testing.T, sb sandbox) *Service {
	s := NewService(sb.r)
	s.Discover = func(context.Context) ([]string, error) { return inventory.DiscoverProjects(sb.r), nil }
	return s
}

func dirPtr(s string) *string { return &s }

func TestServiceSnapshotAndScrub(t *testing.T) {
	sb := newSandbox(t)
	proj := sb.project("proj")
	broken := sb.project("broken")
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Read","Bash(ls)"]}}`)
	sb.write("proj/.claude/settings.json", `{"permissions":{"deny":["Edit"]}}`)
	sb.write("broken/.claude/settings.json", "{\"env\":{\"T\":\""+canary+"\"} oops")
	s := newService(t, sb)
	ctx := context.Background()

	global, err := s.Snapshot(ctx, SnapshotParams{Scope: KindGlobal})
	if err != nil {
		t.Fatal(err)
	}
	if global.Scope != KindGlobal || global.Dir != nil || global.GlobalRuleCount != 2 || len(global.Rules) != 2 || !global.Exists || global.FileLabel != "~/.claude/settings.json" {
		t.Errorf("global snapshot %+v", global)
	}
	if len(global.ProjectDirs) != 2 || len(global.Grid) != len(Capabilities) {
		t.Errorf("dirs %v grid %d", global.ProjectDirs, len(global.Grid))
	}

	snap, err := s.Snapshot(ctx, SnapshotParams{Scope: KindProject, Dir: dirPtr(proj)})
	if err != nil || snap.Scope != KindProject || snap.Dir == nil || *snap.Dir != proj || snap.GlobalRuleCount != 2 || len(snap.Rules) != 1 || snap.FileLabel != ".claude/settings.json" {
		t.Errorf("project snapshot %+v %v", snap, err)
	}

	// A broken file: the problem names the label, never the absolute path, and never the content.
	bad, err := s.Snapshot(ctx, SnapshotParams{Scope: KindProject, Dir: dirPtr(broken)})
	if err != nil || len(bad.Problems) != 1 {
		t.Fatalf("broken snapshot %+v %v", bad, err)
	}
	if bad.Problems[0] != ".claude/settings.json is not valid JSON." {
		t.Errorf("problem %q", bad.Problems[0])
	}
	// Every write on it is refused with the label in the message.
	_, err = s.Add(ctx, RuleParams{Scope: KindProject, Dir: dirPtr(broken), Verdict: Allow, Rule: "Read"})
	if m := wantErr(t, err, 409); m != ".claude/settings.json is not valid JSON. Nothing was changed." {
		t.Errorf("message %q", m)
	}
	_, err = s.Preview(ctx, CapabilityParams{Scope: KindProject, Dir: dirPtr(broken), Capability: Read, Verdict: Deny})
	if m := wantErr(t, err, 409); strings.Contains(m, sb.root) {
		t.Errorf("preview message %q names the folder", m)
	}

	// A folder that is not in the list falls back to global, as the Swift screen does.
	fallback, err := s.Snapshot(ctx, SnapshotParams{Scope: KindLocal, Dir: dirPtr(sb.path("stranger"))})
	if err != nil || fallback.Scope != KindGlobal || fallback.Dir != nil {
		t.Errorf("fallback %+v %v", fallback, err)
	}

	// The shape on the wire: camelCase members, [] and not null for the empty lists.
	data, err := json.Marshal(fallback)
	if err != nil {
		t.Fatal(err)
	}
	var wire map[string]json.RawMessage
	if err := json.Unmarshal(data, &wire); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"projectDirs", "globalRuleCount", "scope", "dir", "fileLabel", "exists", "problems", "rules", "grid", "codex", "notReadable", "globalNotReadable"} {
		if _, ok := wire[key]; !ok {
			t.Errorf("snapshot has no %q", key)
		}
	}
	if string(wire["problems"]) != "[]" || string(wire["dir"]) != "null" {
		t.Errorf("problems %s dir %s", wire["problems"], wire["dir"])
	}
	var codex map[string]json.RawMessage
	_ = json.Unmarshal(wire["codex"], &codex)
	for _, key := range []string{"present", "model", "unrestricted", "warnings", "approvalPolicy", "sandboxMode", "sandboxWorkspaceWrite", "defaultPermissions", "approvalsReviewer", "profiles", "projects", "rules"} {
		if _, ok := codex[key]; !ok {
			t.Errorf("codex has no %q", key)
		}
	}
	if string(codex["approvalPolicy"]) != "null" || string(codex["profiles"]) != "[]" || string(codex["warnings"]) != "[]" {
		t.Errorf("codex %s", data)
	}
}

func TestServiceParamsAreChecked(t *testing.T) {
	sb := newSandbox(t)
	proj := sb.project("proj")
	sb.write(".claude/settings.json", "{}\n")
	before := sb.read(".claude/settings.json")
	s := newService(t, sb)
	ctx := context.Background()
	cases := map[string]func() error{
		"unknown scope": func() error { _, err := s.Snapshot(ctx, SnapshotParams{Scope: "everywhere"}); return err },
		"global with a folder": func() error {
			_, err := s.Snapshot(ctx, SnapshotParams{Scope: KindGlobal, Dir: dirPtr(proj)})
			return err
		},
		"project without folder": func() error { _, err := s.Snapshot(ctx, SnapshotParams{Scope: KindProject}); return err },
		"relative folder": func() error {
			_, err := s.Snapshot(ctx, SnapshotParams{Scope: KindLocal, Dir: dirPtr("proj")})
			return err
		},
		"add: bad verdict": func() error {
			_, err := s.Add(ctx, RuleParams{Scope: KindGlobal, Verdict: "permit", Rule: "Read"})
			return err
		},
		"add: empty verdict": func() error { _, err := s.Add(ctx, RuleParams{Scope: KindGlobal, Rule: "Read"}); return err },
		"remove: bad scope": func() error {
			_, err := s.Remove(ctx, RuleParams{Scope: "x", Verdict: Allow, Rule: "Read"})
			return err
		},
		"change: bad from": func() error {
			_, err := s.ChangeVerdict(ctx, ChangeParams{Scope: KindGlobal, Rule: "Read", From: "x", To: Deny})
			return err
		},
		"change: bad to": func() error {
			_, err := s.ChangeVerdict(ctx, ChangeParams{Scope: KindGlobal, Rule: "Read", From: Allow, To: "x"})
			return err
		},
		"change: same verdict": func() error {
			_, err := s.ChangeVerdict(ctx, ChangeParams{Scope: KindGlobal, Rule: "Read", From: Allow, To: Allow})
			return err
		},
		"preview: bad capability": func() error {
			_, err := s.Preview(ctx, CapabilityParams{Scope: KindGlobal, Capability: "fly", Verdict: Deny})
			return err
		},
		"set: bad verdict": func() error {
			_, err := s.SetCapability(ctx, CapabilityParams{Scope: KindGlobal, Capability: Read, Verdict: ""})
			return err
		},
		"add: invalid rule": func() error {
			_, err := s.Add(ctx, RuleParams{Scope: KindGlobal, Verdict: Allow, Rule: "not a rule!"})
			return err
		},
	}
	for name, run := range cases {
		err := run()
		if _, ok := coreerr.As(err); !ok {
			t.Errorf("%s: %v is not a refusal", name, err)
			continue
		}
		wantErr(t, err, 400)
	}
	if sb.read(".claude/settings.json") != before || len(historyOf(t, sb.r)) != 0 {
		t.Error("a refused call changed something")
	}

	// A cancelled request never starts.
	cancelled, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := s.Add(cancelled, RuleParams{Scope: KindGlobal, Verdict: Allow, Rule: "Read"}); err == nil {
		t.Error("a cancelled add ran")
	}
	if sb.read(".claude/settings.json") != before {
		t.Error("a cancelled add wrote")
	}
}

func TestServiceWritesAndCheck(t *testing.T) {
	sb := newSandbox(t)
	proj := sb.project("proj")
	s := newService(t, sb)
	ctx := context.Background()

	added, err := s.Add(ctx, RuleParams{Scope: KindLocal, Dir: dirPtr(proj), Verdict: Ask, Rule: "  Bash(git push *)  "})
	if err != nil || added.Entry.Label != "Added ask rule Bash(git push *) (local "+proj+")" || added.Entry.Count != 1 || added.Entry.Undone {
		t.Fatalf("add %+v %v", added, err)
	}
	moved, err := s.ChangeVerdict(ctx, ChangeParams{Scope: KindLocal, Dir: dirPtr(proj), Rule: "Bash(git push *)", From: Ask, To: Deny})
	if err != nil || !strings.HasPrefix(moved.Entry.Label, "Changed Bash(git push *) from ask to deny") {
		t.Fatalf("change %+v %v", moved, err)
	}
	set, err := s.SetCapability(ctx, CapabilityParams{Scope: KindGlobal, Capability: Network, Verdict: Allow})
	if err != nil || set.Entry == nil || set.Entry.Label != "Set Network to Allow (global)" {
		t.Fatalf("set %+v %v", set, err)
	}
	again, err := s.SetCapability(ctx, CapabilityParams{Scope: KindGlobal, Capability: Network, Verdict: Allow})
	if err != nil || again.Entry != nil {
		t.Errorf("the second set must be the null entry: %+v %v", again, err)
	}
	data, _ := json.Marshal(again)
	if string(data) != `{"entry":null}` {
		t.Errorf("wire %s", data)
	}
	removed, err := s.Remove(ctx, RuleParams{Scope: KindLocal, Dir: dirPtr(proj), Verdict: Deny, Rule: "Bash(git push *)"})
	if err != nil || removed.Entry.Label != "Removed deny rule Bash(git push *) (local "+proj+")" {
		t.Fatalf("remove %+v %v", removed, err)
	}
	_, err = s.Remove(ctx, RuleParams{Scope: KindLocal, Dir: dirPtr(proj), Verdict: Deny, Rule: "Bash(git push *)"})
	wantErr(t, err, 409)

	// A project the list does not hold is 404, for every write.
	stranger := dirPtr(sb.path("stranger"))
	_, err = s.Add(ctx, RuleParams{Scope: KindProject, Dir: stranger, Verdict: Allow, Rule: "Read"})
	wantErr(t, err, 404)
	_, err = s.Preview(ctx, CapabilityParams{Scope: KindProject, Dir: stranger, Capability: Read, Verdict: Deny})
	wantErr(t, err, 404)

	for rule, wantValid := range map[string]bool{"Bash(npm test *)": true, "": false, "two\nlines": false, "(x)": false, "Bash(a\vb)": false} {
		got, err := s.Check(ctx, CheckParams{Rule: rule})
		if err != nil || got.Valid != wantValid || (got.Message == nil) != wantValid {
			t.Errorf("Check(%q) = %+v %v", rule, got, err)
		}
	}
	ok, _ := json.Marshal(must(s.Check(ctx, CheckParams{Rule: "Read"})))
	bad, _ := json.Marshal(must(s.Check(ctx, CheckParams{Rule: ""})))
	if string(ok) != `{"valid":true,"message":null}` || string(bad) != `{"valid":false,"message":"Enter a rule such as Bash(npm test *)."}` {
		t.Errorf("wire %s %s", ok, bad)
	}
}

// The process keeps one project list: a write uses the list the last snapshot read, a refresh adds a new project, and
// discovery runs once when the list is empty.
func TestServiceProjectList(t *testing.T) {
	sb := newSandbox(t)
	first := sb.project("first")
	runs := 0
	s := NewService(sb.r)
	s.Discover = func(context.Context) ([]string, error) { runs++; return inventory.DiscoverProjects(sb.r), nil }
	ctx := context.Background()

	if _, err := s.Add(ctx, RuleParams{Scope: KindProject, Dir: dirPtr(first), Verdict: Allow, Rule: "Read"}); err != nil || runs != 1 {
		t.Fatalf("first write: %v, %d discoveries", err, runs)
	}
	second := sb.project("second")
	// Not refreshed: the new project is unknown to the process.
	_, err := s.Add(ctx, RuleParams{Scope: KindProject, Dir: dirPtr(second), Verdict: Allow, Rule: "Read"})
	wantErr(t, err, 404)
	if runs != 1 {
		t.Errorf("%d discoveries without a refresh", runs)
	}
	snap, err := s.Snapshot(ctx, SnapshotParams{Scope: KindProject, Dir: dirPtr(second), RefreshProjects: true})
	if err != nil || snap.Scope != KindProject || runs != 2 || len(snap.ProjectDirs) != 2 {
		t.Fatalf("refresh: %+v %v, %d discoveries", snap, err, runs)
	}
	if _, err := s.Add(ctx, RuleParams{Scope: KindProject, Dir: dirPtr(second), Verdict: Allow, Rule: "Read"}); err != nil {
		t.Errorf("a listed project must be writable: %v", err)
	}
	s.SetProjects(nil)
	if _, err := s.Snapshot(ctx, SnapshotParams{Scope: KindGlobal}); err != nil || runs != 3 {
		t.Errorf("an empty list runs discovery once: %v, %d", err, runs)
	}
}
