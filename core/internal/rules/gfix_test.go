package rules

import (
	"slices"
	"strings"
	"testing"
)

// G-fix.18: lines of config.toml the reader skipped are surfaced as a warning with a count, never with their text.
func TestSkippedConfigLinesAreWarned(t *testing.T) {
	config := "sandbox_mode = \"read-only\"\nthis line is not toml " + canary + "\n= alone\napproval_policy = \"never\"\n"
	c := codexOf(t, &config, nil)
	if c.SkippedLines != 2 {
		t.Fatalf("skipped lines %d, want 2", c.SkippedLines)
	}
	if len(c.Warnings) != 1 || c.Warnings[0] != "2 lines of Codex config.toml could not be understood and were skipped, so some settings may be missing." {
		t.Errorf("warnings %v", c.Warnings)
	}
	if strings.Contains(strings.Join(c.Warnings, "|"), canary) {
		t.Error("a warning quotes the file")
	}
	if c.SandboxMode == nil || *c.SandboxMode != "read-only" || c.ApprovalPolicy == nil || c.ApprovalPolicy.Mode != "never" {
		t.Errorf("the readable lines are still read: %+v", c)
	}

	one := "model = \nsandbox_mode = \"read-only\"\n"
	if c := codexOf(t, &one, nil); c.SkippedLines != 1 || len(c.Warnings) != 1 || !strings.HasPrefix(c.Warnings[0], "1 line of Codex config.toml could not be understood and was skipped") {
		t.Errorf("one skipped line: %d %v", c.SkippedLines, c.Warnings)
	}
	clean := "sandbox_mode = \"read-only\"\n"
	if c := codexOf(t, &clean, nil); c.SkippedLines != 0 || len(c.Warnings) != 0 || c.NotReadable {
		t.Errorf("a clean file warns: %+v", c)
	}
}

// A config.toml or .rules file longer than its read cap is not reported as complete.
func TestTooLargeCodexFilesAreWarned(t *testing.T) {
	const configWarning = "Codex config.toml is too large to read completely, so some settings may be missing."
	pad := func(head string, size int) string { return head + "# " + strings.Repeat("x", size-len(head)-3) + "\n" }

	config := pad("sandbox_mode = \"read-only\"\n", maxJSONBytes+1)
	c := codexOf(t, &config, nil)
	if !slices.Contains(c.Warnings, configWarning) || c.NotReadable {
		t.Errorf("a config past the cap: %v notReadable %v", c.Warnings, c.NotReadable)
	}
	if c.SandboxMode == nil || *c.SandboxMode != "read-only" {
		t.Errorf("the part that was read is still used: %+v", c.SandboxMode)
	}
	exact := pad("sandbox_mode = \"read-only\"\n", maxJSONBytes)
	if c := codexOf(t, &exact, nil); slices.Contains(c.Warnings, configWarning) || len(c.Warnings) != 0 {
		t.Errorf("a config exactly at the cap warns: %v", c.Warnings)
	}

	rule := "prefix_rule(pattern=[\"ls\"], decision=\"allow\")\n"
	over := map[string]string{"big.rules": pad(rule, maxRulesFileBytes+1), "small.rules": rule}
	c = codexOf(t, nil, over)
	want := "1 Codex .rules file is too large to read completely, so some rules are not counted."
	if !slices.Contains(c.Warnings, want) || c.Rules.Files != 2 || c.Rules.Allow != 2 {
		t.Errorf("a rules file past the cap: %v %+v", c.Warnings, c.Rules)
	}
	two := map[string]string{"a.rules": pad(rule, maxRulesFileBytes+1), "b.rules": pad(rule, maxRulesFileBytes+5)}
	if c := codexOf(t, nil, two); !slices.Contains(c.Warnings, "2 Codex .rules files are too large to read completely, so some rules are not counted.") {
		t.Errorf("two rules files past the cap: %v", c.Warnings)
	}
	atCap := map[string]string{"a.rules": pad(rule, maxRulesFileBytes)}
	if c := codexOf(t, nil, atCap); len(c.Warnings) != 0 {
		t.Errorf("a rules file exactly at the cap warns: %v", c.Warnings)
	}
}
