package methods

import (
	"context"
	"path/filepath"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
)

// After Close no watcher starts, and the refusal is a fixed error: the handler must never return (nil, nil), which
// the server would answer as a successful null result (finding 6).
func TestSubscribeAfterCloseIsRefused(t *testing.T) {
	dir := t.TempDir()
	cfg := config.Config{Test: true, UserHome: dir, ClaudeConfigDir: filepath.Join(dir, ".claude"),
		CodexHome: filepath.Join(dir, ".codex"), Home: filepath.Join(dir, ".spacevibe")}
	r, err := roots.Resolve(cfg, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s := New(cfg, r, proc.NewFixture(nil, nil, nil, 0), nil)
	s.Close()
	res, err := s.Run(context.Background(), "activity.subscribe", []byte("{}"))
	if res != nil {
		t.Errorf("result = %v", res)
	}
	got, ok := coreerr.As(err)
	if !ok || got != errClosed {
		t.Fatalf("err = %v, want the fixed closed error", err)
	}
}
