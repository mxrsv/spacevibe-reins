package methods

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"spacevibe.dev/core/internal/activity"
	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
)

// activity.stop accepts exactly the CLIs with the activity concept and words the refusal from the registry; Gemini
// CLI, which the registry knows, is refused like an unknown id.
func TestActivityStopAcceptsOnlyActivityCLIs(t *testing.T) {
	dir := t.TempDir()
	cfg := config.Config{Test: true, UserHome: dir, Home: filepath.Join(dir, ".spacevibe")}
	r, err := roots.Resolve(cfg, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s := New(cfg, r, proc.NewFixture(nil, nil, nil, 0), nil)
	defer s.Close()
	for _, id := range []clis.ID{clis.Gemini, "nope", ""} {
		_, err := s.activityStop(context.Background(), StopParams{CLI: id, ID: "s1"})
		if e, ok := coreerr.As(err); !ok || e.Message != "cli must be claude or codex." {
			t.Errorf("%q: err = %v", id, err)
		}
	}
	for _, id := range clis.IDsWith(clis.Activity) {
		_, err := s.activityStop(context.Background(), StopParams{CLI: id, ID: "s1"})
		if e, ok := coreerr.As(err); ok && e.Message == "cli must be claude or codex." {
			t.Errorf("%s was refused as a CLI", id)
		}
	}
}

// clis.list describes every registry CLI in wire order, each fact taken from the adapter that implements it, and
// detects a CLI by its folder alone (Codex's folder is missing here).
func TestClisListDescribesEveryCLI(t *testing.T) {
	dir := t.TempDir()
	if err := os.Mkdir(filepath.Join(dir, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := config.Config{Test: true, UserHome: dir, Home: filepath.Join(dir, ".spacevibe")}
	r, err := roots.Resolve(cfg, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s := New(cfg, r, proc.NewFixture(nil, nil, nil, 0), nil)
	defer s.Close()
	got, err := s.clisList(context.Background(), none{})
	if err != nil {
		t.Fatal(err)
	}
	var ids []clis.ID
	for _, c := range got.CLIs {
		ids = append(ids, c.ID)
	}
	if want := []clis.ID{clis.Claude, clis.Codex, clis.Gemini}; !slices.Equal(ids, want) {
		t.Fatalf("ids = %v, want %v", ids, want)
	}
	claude, codex, gemini := got.CLIs[0], got.CLIs[1], got.CLIs[2]
	if !claude.Installed || codex.Installed || gemini.Installed {
		t.Errorf("installed = %v %v %v, want only Claude Code (its folder alone exists)", claude.Installed, codex.Installed, gemini.Installed)
	}
	if !claude.LogsHookRuns || codex.LogsHookRuns || gemini.LogsHookRuns {
		t.Error("logsHookRuns: want Claude Code only")
	}
	if !claude.ReadsSessionLog || !codex.ReadsSessionLog || gemini.ReadsSessionLog {
		t.Error("readsSessionLog: want Claude Code and Codex")
	}
	if !claude.SubagentWithoutToolsGetsEveryTool || codex.SubagentWithoutToolsGetsEveryTool || gemini.SubagentWithoutToolsGetsEveryTool {
		t.Error("subagentWithoutToolsGetsEveryTool: want Claude Code only")
	}
	if gemini.ApprovalLimitCode != nil || claude.ApprovalLimitCode == nil || *claude.ApprovalLimitCode != activity.ReasonClaudePromptVsBusy {
		t.Errorf("approvalLimitCode = %v / %v", claude.ApprovalLimitCode, gemini.ApprovalLimitCode)
	}
	for _, c := range got.CLIs {
		if c.LimitsReading == nil {
			t.Errorf("%s has the limits concept but no limits reading", c.ID)
		}
		for _, k := range c.Kinds {
			if c.ID == clis.Gemini && k.Support != inventory.SupportAbsent {
				t.Errorf("gemini %s = %s, want absent: it has no inventory", k.Kind, k.Support)
			}
			if c.ID != clis.Gemini && k.Support != inventory.SupportFull {
				t.Errorf("%s %s = %s, want full", c.ID, k.Kind, k.Support)
			}
		}
	}
}
