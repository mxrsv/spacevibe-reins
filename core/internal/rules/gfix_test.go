package rules

import (
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
