package rules

import (
	"encoding/json"
	"strings"
	"testing"
)

// RulesTests.swift: the pure parts (rule shape, push and deploy text, the capability grid) and the Codex reader.

func sp(s string) *string { return &s }

func rl(v Verdict, rule string) Rule { return syntheticRule(v, rule) }

func stateOf(rules []Rule, c Capability) State { return cellOf(CapabilityGrid(rules), c).State }

// Swift: RulesTests.swift "parseRule: Tool, Tool(specifier), blanks, and what is not a rule"
func TestParseRuleShapes(t *testing.T) {
	good := []struct {
		in   string
		want ParsedRule
	}{
		{"Bash(npm test:*)", ParsedRule{"Bash", sp("npm test:*")}},
		{"  Read  ", ParsedRule{"Read", nil}},
		{"Bash()", ParsedRule{"Bash", nil}},
		{"Bash(  )", ParsedRule{"Bash", nil}},
		{"mcp__demo__lookup", ParsedRule{"mcp__demo__lookup", nil}},
		{"Edit( a b )(c)", ParsedRule{"Edit", sp(" a b )(c")}},
		{"Bash(a\nb)", ParsedRule{"Bash", sp("a\nb")}},
	}
	for _, c := range good {
		got, ok := ParseRule(c.in)
		if !ok || got.Tool != c.want.Tool || (got.Specifier == nil) != (c.want.Specifier == nil) || (got.Specifier != nil && *got.Specifier != *c.want.Specifier) {
			t.Errorf("ParseRule(%q) = %+v %v, want %+v", c.in, got, ok, c.want)
		}
	}
	for _, bad := range []string{"", "   ", "not a rule!", "Bash(unclosed", "(x)", "Bash)", "9Bash", "Bash(x) y", "Bàsh", "???"} {
		if got, ok := ParseRule(bad); ok {
			t.Errorf("ParseRule(%q) = %+v, want none", bad, got)
		}
	}
}

// Swift: RulesTests.swift "pushes and deploys are recognised by ASCII word rules, as JavaScript does"
func TestPushDeployText(t *testing.T) {
	for _, yes := range []string{"git push", "git   push origin", "vercel --prod", "gh pr merge 1", "npm publish", "echo deploy now", "deploy", "wrangler deploy", "yarn\tpublish"} {
		if !looksLikePushOrDeploy(yes) {
			t.Errorf("%q should look like a push or deploy", yes)
		}
	}
	for _, no := range []string{"git pushd", "vercelx", "npm test", "redeploy", "git status", "deployment"} {
		if looksLikePushOrDeploy(no) {
			t.Errorf("%q should not look like a push or deploy", no)
		}
	}
	// A letter next to the word is a word character only in ICU's view; JavaScript treats it as a boundary.
	if !looksLikePushOrDeploy("vercelé") {
		t.Error("vercelé: a non-ASCII letter is a boundary")
	}
	for _, yes := range []string{"./.env", ".env.local", "**/.env*", "a/.env"} {
		if !namesEnvFile(yes) {
			t.Errorf("namesEnvFile(%q) = false", yes)
		}
	}
	for _, no := range []string{"src/x.env", "environment"} {
		if namesEnvFile(no) {
			t.Errorf("namesEnvFile(%q) = true", no)
		}
	}
}

// Extra vectors for the regex traps of the plan: the JS space class (\v, U+FEFF, NBSP, U+3000), no ICU lookaround, and
// no `$`: a trailing newline or a leading JS space does not change the answer.
func TestPushPatternVectors(t *testing.T) {
	yes := []string{
		"git\vpush", "git\u00a0push", "git\u3000push", "git\ufeffpush", "wrangler\u2003publish", "  git push", "\ufeffvercel",
		"git push\n", "echo\ndeploy\n",
	}
	for _, s := range yes {
		if !looksLikePushOrDeploy(s) {
			t.Errorf("%q should match", s)
		}
	}
	// U+0085 and U+200B are not JavaScript space; "_" and digits are word characters, so there is no boundary.
	no := []string{"git\u0085push", "git\u200bpush", "gitpush", "echo deploy_", "echo _deploy", "echo deploy1", "fly deploy2", "docker pushed", "gh release2"}
	for _, s := range no {
		if looksLikePushOrDeploy(s) {
			t.Errorf("%q should not match", s)
		}
	}
}

// Swift: RulesTests.swift "capability grid, one row per mapping"
func TestGridMapping(t *testing.T) {
	a, k, d := Allow, Ask, Deny
	type row struct {
		c     Capability
		rules []Rule
		want  State
	}
	rows := []row{
		{Read, []Rule{rl(a, "Read")}, StateAllow},
		{Secrets, []Rule{rl(a, "Read")}, StateAllow},
		{Read, []Rule{rl(a, "Read(src/**)")}, StateMixed},
		{Read, []Rule{rl(d, "Read(./.env)")}, StateNone},
		{Secrets, []Rule{rl(d, "Read(./.env)")}, StateDeny},
		{Secrets, []Rule{rl(d, "Read(**/.env*)")}, StateDeny},
		{Secrets, []Rule{rl(a, "Read(./.env)"), rl(k, "Read(./.env.*)")}, StateMixed},
		{Secrets, []Rule{rl(a, "Read"), rl(d, "Read(./.env)")}, StateDeny},
		{Read, []Rule{rl(a, "Read"), rl(d, "Read(./.env)")}, StateAllow},
		{Edit, []Rule{rl(k, "Edit")}, StateAsk},
		{Edit, []Rule{rl(a, "MultiEdit")}, StateAllow},
		{Edit, []Rule{rl(d, "Write")}, StateDeny},
		{Edit, []Rule{rl(k, "Edit"), rl(a, "Write(src/**)")}, StateAsk},
		{Edit, []Rule{rl(d, "Edit(secrets/**)")}, StateMixed},
		{Edit, []Rule{rl(d, "Write"), rl(a, "Edit(a)")}, StateDeny},
		{Edit, []Rule{rl(a, "Edit"), rl(k, "Edit(docs/**)")}, StateMixed},
		{Run, []Rule{rl(a, "Bash")}, StateAllow},
		{Run, []Rule{rl(a, "Bash(*)")}, StateAllow},
		{Push, []Rule{rl(a, "Bash")}, StateAllow},
		{Run, []Rule{rl(a, "Bash(npm test:*)")}, StateMixed},
		{Push, []Rule{rl(a, "Bash(npm test:*)")}, StateNone},
		{Run, []Rule{rl(a, "Bash"), rl(a, "Bash(ls)")}, StateAllow},
		{Run, []Rule{rl(a, "Bash"), rl(d, "Bash(rm *)")}, StateMixed},
		{Run, []Rule{rl(k, "Bash"), rl(a, "Bash(ls)")}, StateAsk},
		{Run, []Rule{rl(k, "Bash"), rl(d, "Bash(rm *)")}, StateMixed},
		{Run, []Rule{rl(a, "Bash"), rl(d, "Bash")}, StateDeny},
		{Run, []Rule{rl(a, "Bash"), rl(k, "Bash")}, StateAsk},
		{Run, []Rule{rl(a, "Bash"), rl(d, "Bash(git push:*)")}, StateAllow},
		{Push, []Rule{rl(a, "Bash"), rl(d, "Bash(git push:*)")}, StateDeny},
		{Push, []Rule{rl(d, "Bash"), rl(a, "Bash(git push *)")}, StateDeny},
		{Push, []Rule{rl(a, "Bash(vercel deploy)")}, StateAllow},
		{Push, []Rule{rl(a, "Bash(npm publish)")}, StateAllow},
		{Push, []Rule{rl(a, "Bash(git push *)"), rl(d, "Bash(vercel *)")}, StateMixed},
		{Run, []Rule{rl(a, "Bash(git push *)")}, StateNone},
		{Network, []Rule{rl(d, "WebFetch")}, StateDeny},
		{Network, []Rule{rl(a, "WebSearch")}, StateAllow},
		{Network, []Rule{rl(a, "WebSearch"), rl(a, "WebFetch(domain:a.dev)")}, StateAllow},
		{Network, []Rule{rl(a, "WebFetch(domain:a.dev)")}, StateMixed},
	}
	for _, r := range rows {
		if got := stateOf(r.rules, r.c); got != r.want {
			t.Errorf("%s of %v = %s, want %s", r.c, ruleTexts(r.rules), got, r.want)
		}
	}
	for _, cell := range CapabilityGrid(nil) {
		if cell.State != StateNone {
			t.Errorf("empty grid: %s is %s", cell.Capability, cell.State)
		}
	}
	// Rules that belong to no cell
	for _, cell := range CapabilityGrid([]Rule{rl(a, "mcp__x__y"), rl(a, "Skill(a)"), rl(a, "???")}) {
		if cell.State != StateNone {
			t.Errorf("no-cell rules: %s is %s", cell.Capability, cell.State)
		}
	}
	// The concrete rules behind a cell, and editable
	cell := cellOf(CapabilityGrid([]Rule{rl(a, "Bash"), rl(d, "Bash(rm *)")}), Run)
	if got := ruleTexts(cell.Rules); strings.Join(got, "|") != "Bash|Bash(rm *)" || cell.Editable || cell.Label != "Run commands" {
		t.Errorf("run cell = %v editable %v %q", got, cell.Editable, cell.Label)
	}
}

func ruleTexts(rules []Rule) []string {
	out := make([]string, len(rules))
	for i, r := range rules {
		out[i] = r.Rule
	}
	return out
}

// Swift: RulesTests.swift "a star specifier is wide for every tool, so Read(*) reads as allow"
func TestStarSpecifier(t *testing.T) {
	if stateOf([]Rule{rl(Allow, "Read(*)")}, Read) != StateAllow ||
		stateOf([]Rule{rl(Allow, "WebFetch(*)")}, Network) != StateAllow ||
		stateOf([]Rule{rl(Allow, "Edit(*)"), rl(Deny, "Edit(~/.ssh/**)")}, Edit) != StateMixed ||
		stateOf([]Rule{rl(Allow, "Bash( * )")}, Run) != StateAllow {
		t.Error("a star specifier is not wide")
	}
}

func TestRuleCheck(t *testing.T) {
	// check is the live check, write the sentence checkedRule refuses with ("" when it accepts).
	cases := []struct{ rule, check, write string }{
		// Where the two agree.
		{"Bash(npm test *)", "", ""}, {"  Read  ", "", ""}, {"", enterRuleMessage, enterRuleMessage}, {"   ", enterRuleMessage, enterRuleMessage},
		{"two\nlines", invalidRuleMessage, invalidRuleMessage}, {"two\rlines", invalidRuleMessage, invalidRuleMessage},
		{"(x)", invalidRuleMessage, invalidRuleMessage}, {strings.Repeat("a", 1001), invalidRuleMessage, invalidRuleMessage}, {strings.Repeat("a", 1000), "", ""},
		// Where they differ on purpose, as in Swift: shapeError trims whitespacesAndNewlines (U+0085 yes, U+FEFF no) and
		// refuses every Unicode newline, where the write only refuses \n and \r and trims the JavaScript space set.
		{"Bash(a\vb)", invalidRuleMessage, ""}, {"Bash(a\u2028b)", invalidRuleMessage, ""}, {"Bash(a\u0085b)", invalidRuleMessage, ""},
		{"\u0085", enterRuleMessage, invalidRuleMessage}, {"\u0085Read", "", invalidRuleMessage},
		{"\ufeff", invalidRuleMessage, enterRuleMessage}, {"\ufeffRead", "", ""},
	}
	for _, c := range cases {
		if got := Check(c.rule); got != c.check {
			t.Errorf("Check(%q) = %q, want %q", c.rule, got, c.check)
		}
		write := ""
		if _, err := checkedRule(c.rule); err != nil {
			write = err.Error()
		}
		if write != c.write {
			t.Errorf("checkedRule(%q) refused with %q, want %q", c.rule, write, c.write)
		}
	}
}

// codexOf reads a home with the given config.toml (nil: none) and rules files.
func codexOf(t *testing.T, config *string, rulesFiles map[string]string) CodexPermissions {
	t.Helper()
	h := newHome(t)
	h.write(".codex/.keep", "")
	if config != nil {
		h.write(".codex/config.toml", *config)
	}
	for name, text := range rulesFiles {
		h.write(".codex/rules/"+name, text)
	}
	return ReadCodexPermissions(h.roots())
}

func flagList(c []Flag) string {
	data, _ := json.Marshal(c)
	return string(data)
}

// Swift: RulesTests.swift "Codex reader: legacy model, comments, multi-line arrays, inline tables, and nothing from mcp or env tables"
func TestCodexLegacy(t *testing.T) {
	config := "# comment\napproval_policy = \"never\"   # trailing comment\nsandbox_mode = \"danger-full-access\"\napprovals_reviewer = \"user\"\nmodel = \"demo-model\"\n" +
		"developer_instructions = \"\"\"\napproval_policy = \"on-request\"\n[permissions.fake]\n\"\"\"\n\n" +
		"[sandbox_workspace_write]\nnetwork_access = true\nwritable_roots = [\n  \"/tmp/a\",\n  \"/tmp/b\", # note\n]\n\n" +
		"[projects.\"/work/app\"]\ntrust_level = \"trusted\"\n\n[projects.\"/work/weird]path\"]\ntrust_level = \"untrusted\"\n\n" +
		"[projects]\n\"/work/inline\" = { trust_level = \"trusted\" }\n\n[mcp_servers.github]\ncommand = \"npx\"\n[mcp_servers.github.env]\nGITHUB_TOKEN = \"" + canary + "\"\n\n" +
		"[shell_environment_policy]\nset = { API_KEY = \"" + canary + "\" }\n"
	rules := map[string]string{"default.rules": "# prefix_rule(pattern=[\"x\"], decision=\"forbidden\")\nprefix_rule(pattern=[\"git\", \"status\"], decision=\"allow\")\n" +
		"prefix_rule(\n  pattern=[\"rm\"],\n  decision=\"forbidden\",\n)\nprefix_rule(pattern=[\"curl\", \"" + canary + "\"], decision=\"prompt\")\nprefix_rule(pattern=[\"ls\"])"}
	c := codexOf(t, &config, rules)
	if !c.Present || c.Model != ModelLegacy || !c.Unrestricted {
		t.Errorf("present %v model %s unrestricted %v", c.Present, c.Model, c.Unrestricted)
	}
	if c.ApprovalPolicy == nil || c.ApprovalPolicy.IsGranular || c.ApprovalPolicy.Mode != "never" || *c.SandboxMode != "danger-full-access" || *c.ApprovalsReviewer != "user" {
		t.Errorf("policy %+v sandbox %v reviewer %v", c.ApprovalPolicy, c.SandboxMode, c.ApprovalsReviewer)
	}
	w := c.SandboxWorkspaceWrite
	if w == nil || w.NetworkAccess == nil || !*w.NetworkAccess || strings.Join(w.WritableRoots, ",") != "/tmp/a,/tmp/b" {
		t.Errorf("workspace write %+v", w)
	}
	want := []struct{ path, trust string }{{"/work/app", "trusted"}, {"/work/weird]path", "untrusted"}, {"/work/inline", "trusted"}}
	if len(c.Projects) != len(want) {
		t.Fatalf("projects %+v", c.Projects)
	}
	for i, p := range want {
		if c.Projects[i].Path != p.path || c.Projects[i].TrustLevel == nil || *c.Projects[i].TrustLevel != p.trust {
			t.Errorf("project %d = %+v", i, c.Projects[i])
		}
	}
	if len(c.Profiles) != 0 || len(c.Warnings) != 0 {
		t.Errorf("profiles %+v warnings %v", c.Profiles, c.Warnings)
	}
	if got := (RulesSummary{Files: 1, Allow: 2, Prompt: 1, Forbidden: 1}); c.Rules != got {
		t.Errorf("rules %+v, want %+v", c.Rules, got)
	}
	data, _ := json.Marshal(c)
	if strings.Contains(string(data), canary) {
		t.Error("something from mcp_servers, env tables or rule patterns leaked")
	}
}

// Swift: RulesTests.swift "Codex reader: profiles model, granular approval policy, and a missing config"
func TestCodexProfiles(t *testing.T) {
	missing := codexOf(t, nil, nil)
	if missing.Present || missing.Model != ModelLegacy || missing.Unrestricted || len(missing.Profiles) != 0 || len(missing.Projects) != 0 || missing.NotReadable {
		t.Errorf("missing config read as %+v", missing)
	}
	if missing.Rules != (RulesSummary{}) {
		t.Errorf("missing config has rules %+v", missing.Rules)
	}

	config := "default_permissions = \"dev\"\n\n[approval_policy.granular]\nsandbox_approval = true\nrules = false\n\n" +
		"[permissions.dev.filesystem]\n\"/tmp\" = \"write\"\n\"~/.ssh\" = \"none\"\n\n[permissions.dev.network]\nenabled = true\nmode = \"limited\"\n\n" +
		"[permissions.strict.filesystem]\n\"/\" = \"read\"\n"
	c := codexOf(t, &config, nil)
	if c.Model != ModelProfiles || c.DefaultPermissions == nil || *c.DefaultPermissions != "dev" || c.SandboxMode != nil || c.Unrestricted {
		t.Errorf("model %s default %v sandbox %v", c.Model, c.DefaultPermissions, c.SandboxMode)
	}
	if c.ApprovalPolicy == nil || !c.ApprovalPolicy.IsGranular || flagList(c.ApprovalPolicy.Granular) != `[{"key":"sandbox_approval","value":true},{"key":"rules","value":false}]` {
		t.Errorf("approval policy %+v", c.ApprovalPolicy)
	}
	if len(c.Profiles) != 2 {
		t.Fatalf("profiles %+v", c.Profiles)
	}
	dev, strict := c.Profiles[0], c.Profiles[1]
	if dev.Name != "dev" || dev.FilesystemEntries != 2 || dev.NetworkEntries != 2 || flagList(dev.NetworkFlags) != `[{"key":"enabled","value":true},{"key":"mode","value":"limited"}]` {
		t.Errorf("dev %+v", dev)
	}
	if strict.Name != "strict" || strict.FilesystemEntries != 1 || strict.NetworkEntries != 0 || len(strict.NetworkFlags) != 0 {
		t.Errorf("strict %+v", strict)
	}
	if c.SandboxWorkspaceWrite != nil {
		t.Errorf("workspace write %+v", c.SandboxWorkspaceWrite)
	}
}

// Swift: RulesTests.swift "Codex reader: both models set warns"
func TestCodexBoth(t *testing.T) {
	config := "default_permissions = \"dev\"\nsandbox_mode = \"workspace-write\"\napproval_policy = { granular = { rules = true } }\n[permissions.dev.network]\nenabled = false\n"
	c := codexOf(t, &config, nil)
	if c.Model != ModelBoth || len(c.Warnings) != 1 || !strings.Contains(c.Warnings[0], "default_permissions and sandbox_mode") || c.Unrestricted {
		t.Errorf("model %s warnings %v", c.Model, c.Warnings)
	}
	if c.ApprovalPolicy == nil || !c.ApprovalPolicy.IsGranular || flagList(c.ApprovalPolicy.Granular) != `[{"key":"rules","value":true}]` {
		t.Errorf("approval policy %+v", c.ApprovalPolicy)
	}
}

// ICU `$` and lookarounds are not in the Codex patterns, but the rules text still has to cut at \r\n, accept the JS
// space class between the tokens and not match a word that only ends in prefix_rule.
func TestCodexRulesTextVectors(t *testing.T) {
	text := "prefix_rule\u00a0(pattern=[\"a\"], decision\u3000=\u3000'forbidden')\r\nxprefix_rule(decision=\"prompt\")\r\n  # prefix_rule(decision=\"prompt\")\r\n" +
		"my_prefix_rule(pattern=[], decision=\"prompt\")\nprefix_rule(decision=\"weird_1\")\n\tprefix_rule(decision = \"prompt\") # c\n"
	c := codexOf(t, nil, map[string]string{"a.rules": text, "notes.txt": "prefix_rule(decision=\"allow\")"})
	if got := (RulesSummary{Files: 1, Prompt: 1, Forbidden: 1, Other: 1}); c.Rules != got {
		t.Errorf("rules %+v, want %+v", c.Rules, got)
	}
}
