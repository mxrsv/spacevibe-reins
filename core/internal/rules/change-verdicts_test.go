package rules

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/ojson"
)

// 250 allow rules plus one that stays: the call moves 250 in one write and one Undo puts every byte back.
func TestChangeVerdictsManyRulesOneEntryByteExactUndo(t *testing.T) {
	sb := newSandbox(t)
	var allow []string
	var moves []RuleMove
	for i := 0; i < 250; i++ {
		rule := fmt.Sprintf("Bash(tool%03d *)", i)
		allow = append(allow, rule)
		moves = append(moves, RuleMove{Rule: rule, From: Allow})
	}
	allow = append(allow, "Read")
	start := prettyOf(t, ojson.Object(
		member("env", ojson.Object(member("TOKEN", str(canary)))),
		member("permissions", permissionsObject(allow, []string{"Glob"}, nil)),
	), "  ")
	sb.write(".claude/settings.json", start)
	before := sb.bytes(sb.settings())

	entry, err := sb.store.ChangeVerdicts(Global, Deny, moves)
	if err != nil {
		t.Fatal(err)
	}
	if entry.Label != "Changed 250 rules to deny (global)" {
		t.Errorf("label %q", entry.Label)
	}
	if h := historyOf(t, sb.r); len(h) != 1 || h[0].ID != entry.ID {
		t.Fatalf("history %+v, want exactly the one entry", h)
	}
	listing, err := sb.store.ListRules(Global)
	if err != nil {
		t.Fatal(err)
	}
	counts := map[Verdict]int{}
	for _, r := range listing.Rules {
		counts[r.Verdict]++
	}
	if counts[Deny] != 250 || counts[Allow] != 1 || counts[Ask] != 1 {
		t.Errorf("verdict counts after the move: %v", counts)
	}

	sb.undo(entry)
	if !bytes.Equal(sb.bytes(sb.settings()), before) {
		t.Error("one Undo did not restore the file byte for byte")
	}
}

// A rule no longer under its from is 409 and the file keeps its bytes; no journal entry appears.
func TestChangeVerdictsStaleFromWritesNothing(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Read"],"ask":["Bash(ls)"]}}`)
	before := sb.bytes(sb.settings())

	_, err := sb.store.ChangeVerdicts(Global, Deny, []RuleMove{{"Read", Allow}, {"Bash(ls)", Allow}}) // Bash(ls) is under ask
	wantErr(t, err, 409)
	if !bytes.Equal(sb.bytes(sb.settings()), before) {
		t.Error("a stale from changed the file")
	}
	if h := historyOf(t, sb.r); len(h) != 0 {
		t.Errorf("a refused call left %d journal entries", len(h))
	}
}

func TestChangeVerdictsRefusals(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Read"]}}`)
	before := sb.bytes(sb.settings())
	for name, run := range map[string]func() error{
		"empty list": func() error { _, err := sb.store.ChangeVerdicts(Global, Deny, nil); return err },
		"bad to":     func() error { _, err := sb.store.ChangeVerdicts(Global, "x", []RuleMove{{"Read", Allow}}); return err },
		"bad from":   func() error { _, err := sb.store.ChangeVerdicts(Global, Deny, []RuleMove{{"Read", "x"}}); return err },
		"from equals to": func() error {
			_, err := sb.store.ChangeVerdicts(Global, Allow, []RuleMove{{"Read", Allow}})
			return err
		},
	} {
		wantErr(t, run(), 400)
		_ = name
	}
	if !bytes.Equal(sb.bytes(sb.settings()), before) || len(historyOf(t, sb.r)) != 0 {
		t.Error("a refused call changed something")
	}
}

// The RPC layer: the same refusals by status, the label for one rule, a project scope, and 404 for a stranger.
func TestServiceChangeVerdicts(t *testing.T) {
	sb := newSandbox(t)
	proj := sb.project("proj")
	sb.write("proj/.claude/settings.local.json", `{"permissions":{"ask":["Bash(a)","Bash(b)"]}}`)
	s := newService(t, sb)
	ctx := context.Background()

	_, err := s.ChangeVerdicts(ctx, ChangesParams{Scope: KindLocal, Dir: dirPtr(proj), To: "x", Rules: []RuleMove{{"Bash(a)", Ask}}})
	wantErr(t, err, 400)
	_, err = s.ChangeVerdicts(ctx, ChangesParams{Scope: KindLocal, Dir: dirPtr(proj), To: Deny, Rules: []RuleMove{{"Bash(a)", "x"}}})
	wantErr(t, err, 400)
	_, err = s.ChangeVerdicts(ctx, ChangesParams{Scope: KindLocal, Dir: dirPtr(proj), To: Deny})
	wantErr(t, err, 400)
	_, err = s.ChangeVerdicts(ctx, ChangesParams{Scope: KindProject, Dir: dirPtr(sb.path("stranger")), To: Deny, Rules: []RuleMove{{"Bash(a)", Ask}}})
	wantErr(t, err, 404)

	got, err := s.ChangeVerdicts(ctx, ChangesParams{Scope: KindLocal, Dir: dirPtr(proj), To: Deny, Rules: []RuleMove{{"Bash(a)", Ask}, {"Bash(b)", Ask}}})
	if err != nil || got.Entry.Label != "Changed 2 rules to deny (local "+proj+")" || got.Entry.Count != 1 {
		t.Fatalf("change %+v %v", got, err)
	}
	one, err := s.ChangeVerdicts(ctx, ChangesParams{Scope: KindLocal, Dir: dirPtr(proj), To: Allow, Rules: []RuleMove{{"Bash(a)", Deny}}})
	if err != nil || !strings.HasPrefix(one.Entry.Label, "Changed 1 rule to allow") {
		t.Fatalf("one rule %+v %v", one, err)
	}
	_, err = s.ChangeVerdicts(ctx, ChangesParams{Scope: KindLocal, Dir: dirPtr(proj), To: Allow, Rules: []RuleMove{{"Bash(a)", Deny}}})
	if m := wantErr(t, err, 409); m != ruleChangedMessage {
		t.Errorf("message %q", m)
	}
	if _, err := os.Stat(sb.path("proj/.claude/settings.local.json")); err != nil {
		t.Fatal(err)
	}
}
