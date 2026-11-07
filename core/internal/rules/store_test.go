package rules

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// RulesTests.swift: the store tests (listing, writing, formatting, refusals, undo, cell writes, secrets). Every test runs on
// a temp home; the real ~/.claude and ~/.codex are never read (SPACEVIBE_TEST=1 and the roots guard).

// sandbox is a throwaway HOME whose projects are found by discovery, as in the app.
type sandbox struct {
	tempHome
	r     roots.Roots
	store *Store
}

func newSandbox(t *testing.T) sandbox {
	h := newHome(t)
	r := h.roots()
	return sandbox{h, r, NewStore(r, nil)}
}

func (sb sandbox) settings() string { return sb.r.Claude.HookFile }
func (sb sandbox) bytes(p string) []byte {
	sb.t.Helper()
	data, err := os.ReadFile(p)
	if err != nil {
		sb.t.Fatal(err)
	}
	return data
}

func (sb sandbox) undo(e mutate.Entry) {
	sb.t.Helper()
	if _, err := mutate.Undo(sb.r, e.ID); err != nil {
		sb.t.Fatalf("undo %q: %v", e.Label, err)
	}
}

func str(s string) ojson.Value { return ojson.String(s) }

func list(items ...string) ojson.Value {
	values := make([]ojson.Value, len(items))
	for i, s := range items {
		values[i] = ojson.String(s)
	}
	return ojson.Array(values...)
}

func member(k string, v ojson.Value) ojson.Member { return ojson.Member{Key: k, Value: v} }

// permissionsObject is {"allow": [...], "ask": [...], "deny": [...]} with the lists that are not nil.
func permissionsObject(allow, ask, deny []string) ojson.Value {
	var members []ojson.Member
	for _, l := range []struct {
		k string
		v []string
	}{{"allow", allow}, {"ask", ask}, {"deny", deny}} {
		if l.v != nil {
			members = append(members, member(l.k, list(l.v...)))
		}
	}
	return ojson.Object(members...)
}

func prettyOf(t *testing.T, v ojson.Value, indent string) string {
	t.Helper()
	text, err := ojson.PrettyStyled(v, indent, "\n", true)
	if err != nil {
		t.Fatal(err)
	}
	return text
}

func sameValue(t *testing.T, what string, got ojson.Value, ok bool, want ojson.Value) {
	t.Helper()
	if !ok || !got.Equal(want) {
		a, _ := ojson.Pretty(got)
		b, _ := ojson.Pretty(want)
		t.Errorf("%s = %s (found %v), want %s", what, strings.TrimSpace(a), ok, strings.TrimSpace(b))
	}
}

func (sb sandbox) member(p string, path ...string) (ojson.Value, bool) {
	sb.t.Helper()
	v := parsedRoot(sb.t, p)
	for _, k := range path {
		var ok bool
		if v, ok = v.Member(k); !ok {
			return ojson.Value{}, false
		}
	}
	return v, true
}

func ruleIDs(l Listing) []string {
	out := make([]string, len(l.Rules))
	for i, r := range l.Rules {
		out[i] = string(r.Scope) + ":" + string(r.Verdict) + ":" + r.Rule
	}
	return out
}

// Swift: RulesTests.swift "lists rules by scope and keeps values that are not rules out of the tool/specifier fields"
func TestListing(t *testing.T) {
	sb := newSandbox(t)
	proj := sb.project("proj")
	sb.write(".claude/settings.json", `{"env":{"TOKEN":"`+canary+`"},"permissions":{"allow":["Bash(npm test:*)",42,"not a rule!"],"deny":["Read(./.env)"]}}`)
	sb.write("proj/.claude/settings.json", `{"permissions":{"ask":["Edit"]}}`)
	sb.write("proj/.claude/settings.local.json", `{"permissions":{"allow":["WebFetch"]}}`)
	listing, err := sb.store.ListRules(ScopesFor(proj)...)
	if err != nil {
		t.Fatal(err)
	}
	if len(listing.Problems) != 0 {
		t.Errorf("problems %v", listing.Problems)
	}
	want := []string{"global:allow:Bash(npm test:*)", "global:allow:not a rule!", "global:deny:Read(./.env)", "project:ask:Edit", "local:allow:WebFetch"}
	if got := ruleIDs(listing); !slices.Equal(got, want) {
		t.Errorf("rules %v, want %v", got, want)
	}
	first := listing.Rules[0]
	if first.Tool == nil || *first.Tool != "Bash" || first.Specifier == nil || *first.Specifier != "npm test:*" {
		t.Errorf("first rule %+v", first)
	}
	if listing.Rules[1].Tool != nil {
		t.Error("a string that is not a rule has no tool")
	}
	if first.ID != "global:allow:Bash(npm test:*)" || listing.Rules[3].Dir == nil || *listing.Rules[3].Dir != proj {
		t.Errorf("ids and dirs: %+v %+v", first, listing.Rules[3])
	}
	empty, err := sb.store.ListRules(LocalScope(sb.project("empty")))
	if err != nil || len(empty.Rules) != 0 {
		t.Errorf("empty project: %+v %v", empty, err)
	}
	_, err = sb.store.ListRules(ProjectScope("relative"))
	wantErr(t, err, 400)
}

// Swift: RulesTests.swift "a project folder must be one discovery found: others are refused with 404 and nothing is created"
func TestUndiscoveredFolder(t *testing.T) {
	sb := newSandbox(t)
	sb.project("known")
	stranger := sb.path("stranger")
	if err := os.MkdirAll(stranger, 0o755); err != nil {
		t.Fatal(err)
	}
	missing := sb.path("missing")
	for _, scope := range []Scope{ProjectScope(stranger), LocalScope(stranger), ProjectScope(missing), LocalScope("/etc"), ProjectScope(sb.root)} {
		_, err := sb.store.ListRules(scope)
		wantErr(t, err, 404)
		_, err = sb.store.AddRule(scope, Allow, "Read")
		wantErr(t, err, 404)
		_, err = sb.store.SetCapability(scope, Read, Deny)
		wantErr(t, err, 404)
		_, err = sb.store.PreviewSetCapability(scope, Read, Deny)
		wantErr(t, err, 404)
	}
	for _, p := range []string{filepath.Join(stranger, ".claude"), "/etc/.claude"} {
		if _, err := os.Lstat(p); err == nil {
			t.Errorf("%s was created", p)
		}
	}
	if n := len(historyOf(t, sb.r)); n != 0 {
		t.Errorf("%d journal entries", n)
	}
	// a known folder with a trailing slash or a dot segment is the same folder
	l, err := sb.store.ListRules(ProjectScope(sb.path("known") + "/./"))
	if err != nil || len(l.Problems) != 0 {
		t.Errorf("known folder with a dot segment: %+v %v", l, err)
	}
}

// Swift: RulesTests.swift "add, change and remove keep other keys and the indent; undo restores identical bytes and the mode"
func TestAddChangeRemoveUndo(t *testing.T) {
	for _, indent := range []string{"    ", "\t"} {
		sb := newSandbox(t)
		start := prettyOf(t, ojson.Object(
			member("env", ojson.Object(member("TOKEN", str(canary)))), member("model", str("x")),
			member("permissions", permissionsObject([]string{"Read"}, nil, nil)), member("hooks", ojson.Object()),
		), indent)
		sb.write(".claude/settings.json", start)
		if err := os.Chmod(sb.settings(), 0o640); err != nil {
			t.Fatal(err)
		}
		before := sb.bytes(sb.settings())

		added := must(sb.store.AddRule(Global, Deny, "Bash(rm *)"))
		afterAdd := string(sb.bytes(sb.settings()))
		got, ok := sb.member(sb.settings(), "permissions")
		sameValue(t, "permissions after add", got, ok, permissionsObject([]string{"Read"}, nil, []string{"Bash(rm *)"}))
		got, ok = sb.member(sb.settings(), "env")
		sameValue(t, "env", got, ok, ojson.Object(member("TOKEN", str(canary))))
		got, ok = sb.member(sb.settings(), "model")
		sameValue(t, "model", got, ok, str("x"))
		got, ok = sb.member(sb.settings(), "hooks")
		sameValue(t, "hooks", got, ok, ojson.Object())
		if !strings.HasPrefix(afterAdd, "{\n"+indent+"\"env\"") || !strings.HasSuffix(afterAdd, "}\n") {
			t.Errorf("indent %q not kept:\n%s", indent, afterAdd)
		}
		if sb.mode(sb.settings()) != 0o640 {
			t.Errorf("mode %o", sb.mode(sb.settings()))
		}

		moved := must(sb.store.ChangeVerdict(Global, "Bash(rm *)", Deny, Ask))
		// the new list goes at the end of the block, after the lists that were already there
		got, ok = sb.member(sb.settings(), "permissions")
		sameValue(t, "permissions after change", got, ok, ojson.Object(member("allow", list("Read")), member("deny", list()), member("ask", list("Bash(rm *)"))))
		removed := must(sb.store.RemoveRule(Global, Ask, "Bash(rm *)"))
		got, ok = sb.member(sb.settings(), "permissions", "ask")
		sameValue(t, "ask after remove (an emptied list stays as [])", got, ok, list())

		sb.undo(removed)
		sb.undo(moved)
		sb.undo(added)
		if !bytes.Equal(sb.bytes(sb.settings()), before) {
			t.Errorf("undo did not restore the exact bytes:\n%s", sb.bytes(sb.settings()))
		}
		if sb.mode(sb.settings()) != 0o640 {
			t.Errorf("mode after undo %o", sb.mode(sb.settings()))
		}
		if stray := strayTemp(sb.r.Claude.Root); len(stray) != 0 {
			t.Errorf("stray temp files %v", stray)
		}
	}
}

// Swift: RulesTests.swift "CRLF line endings, a compact one-line file and a missing trailing newline are kept"
func TestFormattingKept(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", "{\r\n  \"model\": \"x\",\r\n  \"permissions\": {\r\n    \"allow\": [\r\n      \"Read\"\r\n    ]\r\n  }\r\n}\r\n")
	must(sb.store.AddRule(Global, Allow, "Edit"))
	crlf := string(sb.bytes(sb.settings()))
	if !strings.Contains(crlf, "\r\n") || strings.Contains(strings.ReplaceAll(crlf, "\r\n", ""), "\n") || !strings.HasSuffix(crlf, "}\r\n") {
		t.Errorf("not all CRLF: %q", crlf)
	}
	got, ok := sb.member(sb.settings(), "permissions", "allow")
	sameValue(t, "allow", got, ok, list("Read", "Edit"))

	sb.write(".claude/settings.json", `{"model":"x"}`)
	before := sb.bytes(sb.settings())
	entry := must(sb.store.AddRule(Global, Allow, "WebSearch"))
	if text := string(sb.bytes(sb.settings())); text != `{"model":"x","permissions":{"allow":["WebSearch"]}}` {
		t.Errorf("compact style, no newline added: %q", text)
	}
	sb.undo(entry)
	if !bytes.Equal(sb.bytes(sb.settings()), before) {
		t.Error("undo did not restore the compact file")
	}
}

// Swift: RulesTests.swift "rules go into a file without a permissions block, into `permissions: null`, and a created file is removed by undo"
// The undo of a rules edit in a project folder needs project discovery (the G2.3 dependency): the project is discoverable here.
func TestMissingBlockAndCreatedFile(t *testing.T) {
	sb := newSandbox(t)
	proj := sb.project("proj")
	local := sb.path("proj/.claude/settings.local.json")
	entry := must(sb.store.AddRule(LocalScope(proj), Allow, "Bash(git status)"))
	got, ok := sb.member(local)
	sameValue(t, "created file", got, ok, ojson.Object(member("permissions", permissionsObject([]string{"Bash(git status)"}, nil, nil))))
	if sb.mode(local) != 0o600 {
		t.Errorf("mode %o", sb.mode(local))
	}
	sb.undo(entry)
	if _, err := os.Lstat(local); err == nil {
		t.Error("undo left the created file")
	}

	sb.write(".claude/settings.json", `{"permissions":null,"model":"x"}`)
	must(sb.store.AddRule(Global, Deny, "Bash(rm *)"))
	got, ok = sb.member(sb.settings(), "permissions")
	sameValue(t, "permissions from null", got, ok, permissionsObject(nil, nil, []string{"Bash(rm *)"}))
	got, ok = sb.member(sb.settings(), "model")
	sameValue(t, "model", got, ok, str("x"))
}

// Swift: RulesTests.swift "values in a rule list that are not strings are kept, and a removed rule goes everywhere it appears"
func TestNonStringsAndDuplicates(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Read",42,"Edit","Read",null,{"a":1}]}}`)
	must(sb.store.RemoveRule(Global, Allow, "Read"))
	got, ok := sb.member(sb.settings(), "permissions", "allow")
	sameValue(t, "allow", got, ok, ojson.Array(ojson.Number("42"), str("Edit"), ojson.Null(), ojson.Object(member("a", ojson.Number("1")))))
}

// Swift: RulesTests.swift "a symlinked settings file stays a symlink and the target is edited"
func TestSymlinkedSettings(t *testing.T) {
	sb := newSandbox(t)
	target := sb.write("shared-settings.json", "{}\n")
	if err := os.MkdirAll(sb.r.Claude.Root, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, sb.settings()); err != nil {
		t.Fatal(err)
	}
	must(sb.store.AddRule(Global, Allow, "Read"))
	if _, err := os.Readlink(sb.settings()); err != nil {
		t.Error("the link was replaced by a file")
	}
	got, ok := sb.member(target, "permissions", "allow")
	sameValue(t, "allow in the target", got, ok, list("Read"))
}

// Swift: RulesTests.swift "invalid JSON, wrong shapes and bad input are refused without touching the file or quoting its text"
func TestRefusals(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", "{\"env\":{\"TOKEN\":\""+canary+"\"} oops")
	before := sb.bytes(sb.settings())
	attempts := map[string]func() error{
		"add":     func() error { _, err := sb.store.AddRule(Global, Allow, "Read"); return err },
		"remove":  func() error { _, err := sb.store.RemoveRule(Global, Allow, "Read"); return err },
		"change":  func() error { _, err := sb.store.ChangeVerdict(Global, "Read", Allow, Deny); return err },
		"set":     func() error { _, err := sb.store.SetCapability(Global, Read, Deny); return err },
		"preview": func() error { _, err := sb.store.PreviewSetCapability(Global, Read, Deny); return err },
	}
	for name, attempt := range attempts {
		message := wantErr(t, attempt(), 409)
		if !strings.Contains(message, "is not valid JSON") || strings.Contains(message, canary) {
			t.Errorf("%s: message %q", name, message)
		}
	}
	if !bytes.Equal(sb.bytes(sb.settings()), before) {
		t.Error("the file changed")
	}
	if l, err := sb.store.ListRules(); err != nil || len(l.Problems) == 0 || !strings.Contains(l.Problems[0], "is not valid JSON") {
		t.Errorf("listing: %+v %v", l, err)
	}
	if n := len(historyOf(t, sb.r)); n != 0 {
		t.Errorf("%d journal entries", n)
	}
	if stray := strayTemp(sb.r.Claude.Root); len(stray) != 0 {
		t.Errorf("stray temp files %v", stray)
	}
	if strings.Contains(sb.journal(), canary) {
		t.Error("the journal holds the canary")
	}

	addBash := func() string {
		_, err := sb.store.AddRule(Global, Allow, "Bash")
		return wantErr(t, err, 409)
	}
	sb.write(".claude/settings.json", `{"permissions":{"allow":"Read"}}`)
	if m := addBash(); !strings.Contains(m, "not a list") {
		t.Errorf("message %q", m)
	}
	sb.write(".claude/settings.json", `{"permissions":{"allow":null}}`)
	if m := addBash(); !strings.Contains(m, "not a list") {
		t.Errorf("a null list is not a list: %q", m)
	}
	sb.write(".claude/settings.json", `{"permissions":[]}`)
	if m := addBash(); !strings.Contains(m, "not an object") {
		t.Errorf("message %q", m)
	}
	sb.write(".claude/settings.json", "[]")
	if m := addBash(); !strings.Contains(m, "JSON object") {
		t.Errorf("message %q", m)
	}

	sb.write(".claude/settings.json", "{}")
	for _, rule := range []string{"", "   ", "two\nlines", "two\rlines", "Bash(unclosed", "(x)", strings.Repeat("a", 1001)} {
		_, err := sb.store.AddRule(Global, Allow, rule)
		wantErr(t, err, 400)
	}
	must(sb.store.AddRule(Global, Allow, strings.Repeat("a", 1000)))
	must(sb.store.AddRule(Global, Allow, "Bash"))
	_, err := sb.store.AddRule(Global, Deny, "Bash")
	if m := wantErr(t, err, 409); !strings.Contains(m, "already in allow") {
		t.Errorf("message %q", m)
	}
	_, err = sb.store.RemoveRule(Global, Deny, "Bash")
	if m := wantErr(t, err, 409); !strings.Contains(m, "already changed") {
		t.Errorf("message %q", m)
	}
	_, err = sb.store.ChangeVerdict(Global, "Bash", Allow, Allow)
	wantErr(t, err, 400)
	_, err = sb.store.ChangeVerdict(Global, "Bash", Ask, Deny)
	wantErr(t, err, 409)
	// A verdict or capability the type system cannot rule out in Go is refused too.
	_, err = sb.store.AddRule(Global, Verdict("permit"), "Read")
	wantErr(t, err, 400)
	_, err = sb.store.SetCapability(Global, Capability("fly"), Deny)
	wantErr(t, err, 400)
}

// Swift: RulesTests.swift "undo refuses when the file changed after the edit"
func TestUndoAfterHandEdit(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", "{}\n")
	entry := must(sb.store.AddRule(Global, Allow, "Read"))
	sb.write(".claude/settings.json", `{"model":"hand-edited"}`+"\n")
	_, err := mutate.Undo(sb.r, entry.ID)
	if m := wantErr(t, err, 409); !strings.Contains(m, "changed since") {
		t.Errorf("message %q", m)
	}
	got, ok := sb.member(sb.settings(), "model")
	sameValue(t, "model", got, ok, str("hand-edited"))
}

func verdictRules(pairs ...string) []VerdictRule {
	out := []VerdictRule{}
	for i := 0; i < len(pairs); i += 2 {
		out = append(out, VerdictRule{Verdict(pairs[i]), pairs[i+1]})
	}
	return out
}

// Swift: RulesTests.swift "preview and set replace the cell's rules, journaled and undoable; a no-op writes nothing"
func TestSetCapability(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", prettyOf(t, ojson.Object(
		member("model", str("x")),
		member("permissions", permissionsObject([]string{"Bash", "Read(./.env)", "WebFetch"}, []string{"Edit"}, []string{"Bash(git push *)"})),
	), "  "))
	before := sb.bytes(sb.settings())

	preview := must(sb.store.PreviewSetCapability(Global, Run, Deny))
	if !slices.Equal(preview.Replaces, verdictRules("allow", "Bash")) || !slices.Equal(preview.Writes, verdictRules("deny", "Bash")) {
		t.Errorf("preview %+v", preview)
	}
	if preview.Current != StateAllow || preview.Resulting != StateDeny || preview.ScopeLabel != "~/.claude/settings.json" {
		t.Errorf("preview %+v", preview)
	}
	if !bytes.Equal(sb.bytes(sb.settings()), before) {
		t.Error("preview wrote")
	}

	must(sb.store.SetCapability(Global, Run, Deny))
	if allow, _ := permissionList(t, sb.settings(), Allow); !slices.Equal(allow, []string{"Read(./.env)", "WebFetch"}) {
		t.Errorf("allow %v", allow)
	}
	if deny, _ := permissionList(t, sb.settings(), Deny); !slices.Equal(deny, []string{"Bash(git push *)", "Bash"}) {
		t.Errorf("deny %v", deny)
	}

	network := must(sb.store.SetCapability(Global, Network, Ask))
	if ask, _ := permissionList(t, sb.settings(), Ask); !slices.Equal(ask, []string{"Edit", "WebFetch", "WebSearch"}) {
		t.Errorf("ask %v", ask)
	}
	sb.undo(*network)
	if ask, _ := permissionList(t, sb.settings(), Ask); !slices.Equal(ask, []string{"Edit"}) {
		t.Errorf("ask after undo %v", ask)
	}

	edit := must(sb.store.PreviewSetCapability(Global, Edit, Allow))
	if !slices.Equal(edit.Replaces, verdictRules("ask", "Edit")) {
		t.Errorf("edit preview %+v", edit)
	}
	if entry := must(sb.store.SetCapability(Global, Edit, Ask)); entry != nil {
		t.Error("already that value: no write, no journal entry")
	}

	entries := historyOf(t, sb.r)
	if len(entries) != 2 {
		t.Fatalf("%d entries", len(entries))
	}
	if _, err := mutate.Undo(sb.r, entries[1].ID); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(sb.bytes(sb.settings()), before) {
		t.Error("undo did not restore the original bytes")
	}
	if stray := strayTemp(sb.r.Claude.Root); len(stray) != 0 {
		t.Errorf("stray temp files %v", stray)
	}
}

// Swift: RulesTests.swift "push and secrets cells write their canonical rules and report a rule that still wins"
func TestPushAndSecrets(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", `{"permissions":{"deny":["Bash"],"allow":["Read"]}}`)
	push := must(sb.store.PreviewSetCapability(Global, Push, Allow))
	if len(push.Replaces) != 0 {
		t.Errorf("a bare Bash belongs to Run commands and is kept: %+v", push.Replaces)
	}
	if !slices.Equal(push.Writes, verdictRules("allow", "Bash(git push *)", "allow", "Bash(vercel *)")) || push.Resulting != StateDeny {
		t.Errorf("push preview %+v (the bare Bash deny still wins)", push)
	}

	secrets := must(sb.store.SetCapability(Global, Secrets, Deny))
	if deny, _ := permissionList(t, sb.settings(), Deny); !slices.Equal(deny, []string{"Bash", "Read(./.env)", "Read(./.env.*)"}) {
		t.Errorf("deny %v", deny)
	}
	if got := stateOf(must(sb.store.ListRules()).Rules, Secrets); got != StateDeny {
		t.Errorf("secrets %s", got)
	}
	if got := stateOf(must(sb.store.ListRules()).Rules, Read); got != StateAllow {
		t.Errorf("read %s", got)
	}
	must(sb.store.SetCapability(Global, Secrets, Ask))
	deny, _ := permissionList(t, sb.settings(), Deny)
	ask, _ := permissionList(t, sb.settings(), Ask)
	if !slices.Equal(deny, []string{"Bash"}) || !slices.Equal(ask, []string{"Read(./.env)", "Read(./.env.*)"}) {
		t.Errorf("deny %v ask %v", deny, ask)
	}
	if secrets == nil || !strings.Contains(secrets.Label, "Secrets") {
		t.Errorf("label %+v", secrets)
	}
}

// Swift: RulesTests.swift "a mixed cell is refused for preview and write, and nothing changes"
func TestMixedRefused(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Bash","Edit(src/**)"],"deny":["Bash(rm *)"]}}`)
	before := sb.bytes(sb.settings())
	for _, c := range []Capability{Run, Edit} {
		_, err := sb.store.PreviewSetCapability(Global, c, Allow)
		if m := wantErr(t, err, 409); !strings.Contains(m, "no single value") {
			t.Errorf("message %q", m)
		}
		_, err = sb.store.SetCapability(Global, c, Deny)
		wantErr(t, err, 409)
	}
	if !bytes.Equal(sb.bytes(sb.settings()), before) || len(historyOf(t, sb.r)) != 0 {
		t.Error("a refusal changed something")
	}
}

// Swift: RulesTests.swift "a cell write in a project scope only touches that project file"
func TestProjectScopeWrite(t *testing.T) {
	sb := newSandbox(t)
	proj := sb.project("proj")
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Bash"]}}`)
	globalBefore := sb.bytes(sb.settings())
	entry := must(sb.store.SetCapability(ProjectScope(proj), Run, Deny))
	got, ok := sb.member(sb.path("proj/.claude/settings.json"))
	sameValue(t, "project file", got, ok, ojson.Object(member("permissions", permissionsObject(nil, nil, []string{"Bash"}))))
	if !bytes.Equal(sb.bytes(sb.settings()), globalBefore) {
		t.Error("the global file changed")
	}
	merged := must(sb.store.ListRules(ScopesFor(proj)...)).Rules
	if stateOf(merged, Run) != StateDeny {
		t.Error("a project deny beats a global allow")
	}
	if h := historyOf(t, sb.r); len(h) == 0 || h[0].Label != "Set Run commands to Deny (project "+proj+")" {
		t.Errorf("history %+v", h)
	}
	// G2.3's dependency: the undo of an edit in a project folder needs project discovery, and the project is discoverable.
	sb.undo(*entry)
	if _, err := os.Lstat(sb.path("proj/.claude/settings.json")); err == nil {
		t.Error("undo left the created project file")
	}
}

// Swift: RulesTests.swift "a secret in settings never appears in a return value, a message, a label or the journal"
func TestSecretsNeverEscape(t *testing.T) {
	sb := newSandbox(t)
	proj := sb.project("proj")
	secret := prettyOf(t, ojson.Object(
		member("env", ojson.Object(member("TOKEN", str(canary)))), member("apiKeyHelper", str("echo "+canary)),
		member("permissions", permissionsObject([]string{"Read"}, nil, nil)),
	), "  ")
	sb.write(".claude/settings.json", secret)
	sb.write("proj/.claude/settings.json", secret)
	sb.write(".codex/config.toml", sb.read(".codex/config.toml")+"[mcp_servers.x.env]\nTOKEN = \""+canary+"\"\n[shell_environment_policy]\nset = { API_KEY = \""+canary+"\" }\n")
	var seen []string
	keep := func(v any) {
		data, err := json.Marshal(v)
		if err != nil {
			t.Fatal(err)
		}
		seen = append(seen, string(data))
	}
	listing := must(sb.store.ListRules(ScopesFor(proj)...))
	keep(listing)
	keep(CapabilityGrid(listing.Rules))
	keep(must(sb.store.PreviewSetCapability(Global, Run, Ask)))
	added := must(sb.store.AddRule(Global, Deny, "Bash(rm *)"))
	keep(added.Ref())
	keep(must(sb.store.ChangeVerdict(Global, "Bash(rm *)", Deny, Ask)).Ref())
	keep(must(sb.store.SetCapability(ProjectScope(proj), Network, Deny)).Ref())
	keep(must(sb.store.RemoveRule(Global, Ask, "Bash(rm *)")).Ref())
	keep(historyOf(t, sb.r))
	keep(ReadCodexPermissions(sb.r))
	sb.write(".claude/settings.json", `{"env":{"T":"`+canary+`"`)
	_, err := sb.store.AddRule(Global, Allow, "Read")
	seen = append(seen, err.Error())
	_, err = mutate.Undo(sb.r, added.ID) // hand-edited, so undo refuses
	seen = append(seen, err.Error())
	if len(seen) <= 8 {
		t.Fatalf("only %d results seen", len(seen))
	}
	for i, text := range seen {
		if text == "" || strings.Contains(text, canary) {
			t.Errorf("result %d is empty or holds the canary: %.80s", i, text)
		}
	}
	journal := sb.journal()
	if strings.Contains(journal, canary) || strings.Contains(journal, "TOKEN") {
		t.Error("the journal holds the canary or a key; backups are files in the app trash, not in the journal")
	}
}

// Swift: RulesTests.swift "all writes stay inside the temporary HOME (SPACEVIBE_TEST=1)"
func TestStaysInTempHome(t *testing.T) {
	sb := newSandbox(t)
	if os.Getenv("SPACEVIBE_TEST") != "1" {
		t.Error("SPACEVIBE_TEST is not 1")
	}
	real, err := roots.RealHome()
	if err != nil {
		t.Fatal(err)
	}
	real = roots.ResolvedPath(real)
	for _, p := range []string{sb.r.Claude.Root, sb.r.Codex.Root, sb.r.Data} {
		if strings.HasPrefix(roots.ResolvedPath(p), real+"/") {
			t.Errorf("%s is under the real home", p)
		}
	}
	if !strings.HasPrefix(sb.r.Claude.HookFile, sb.root) {
		t.Errorf("hook file %s", sb.r.Claude.HookFile)
	}
}
