package proc

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
)

var ctx = context.Background()

func writeFixture(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "activity-proc.json")
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestLoadFixtureShape(t *testing.T) {
	flat := `{"alive":[41001,41002],"starts":{"52003":"Mon Nov  2 11:58:00 2026","x":"skip"},"threads":[{"pid":52001,"threadId":"a0000000-0000-4000-8000-000000000001"},{"pid":52003,"threadId":null},{"threadId":"nopid"},"junk"]}`
	for name, body := range map[string]string{"flat": flat, "shared wrapper": `{"shared":` + flat + `,"extra":{"alive":[1]}}`} {
		t.Run(name, func(t *testing.T) {
			f, err := LoadFixture(writeFixture(t, body))
			if err != nil {
				t.Fatal(err)
			}
			if !f.IsAlive(ctx, 41001) || !f.IsAlive(ctx, 41002) || f.IsAlive(ctx, 1) {
				t.Fatal("alive list wrong")
			}
			if s, ok := f.StartTime(ctx, 52003); !ok || s != "Mon Nov  2 11:58:00 2026" {
				t.Fatalf("StartTime = %q, %v", s, ok)
			}
			if _, ok := f.StartTime(ctx, 41001); ok {
				t.Fatal("unknown start reported")
			}
			want := []Thread{{Pid: 52001, ThreadID: "a0000000-0000-4000-8000-000000000001"}, {Pid: 52003}}
			if got, err := f.CodexThreads(ctx); err != nil || !reflect.DeepEqual(got, want) {
				t.Fatalf("threads = %v, want %v", got, want)
			}
		})
	}
}

func TestLoadFixtureWrongTypesCountAsAbsent(t *testing.T) {
	f, err := LoadFixture(writeFixture(t, `{"alive":[1,"2"],"starts":{"5":7},"threads":"no","delayMs":"soon"}`))
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := f.CodexThreads(ctx); f.IsAlive(ctx, 1) || len(got) != 0 {
		t.Fatal("a mistyped field must read as absent")
	}
	if _, ok := f.StartTime(ctx, 5); ok {
		t.Fatal("a mistyped starts map must read as absent")
	}
}

func TestLoadFixtureUnreadable(t *testing.T) {
	dir := t.TempDir()
	for name, path := range map[string]string{
		"missing":     filepath.Join(dir, "none.json"),
		"directory":   dir,
		"not json":    writeFixture(t, "{nope"),
		"array":       writeFixture(t, "[1]"),
		"empty file":  writeFixture(t, ""),
		"top-level 1": writeFixture(t, "1"),
	} {
		t.Run(name, func(t *testing.T) {
			_, err := LoadFixture(path)
			ce, ok := coreerr.As(err)
			if !ok || ce.Status != 400 || ce.Message != "SPACEVIBE_PROC_FIXTURE does not point at a readable process list file." {
				t.Fatalf("err = %v", err)
			}
		})
	}
}

func TestLoadFixtureGoldenFiles(t *testing.T) {
	for _, rel := range []string{"golden/activity-proc.json", "home/.reins/activity-proc.json"} {
		f, err := LoadFixture(filepath.Join("..", "..", "testdata", "fixtures", rel))
		if err != nil {
			t.Fatalf("%s: %v", rel, err)
		}
		if got, _ := f.CodexThreads(ctx); !f.IsAlive(ctx, 41001) || len(got) != 3 {
			t.Fatalf("%s: unexpected content", rel)
		}
	}
}

func TestFixtureTerminate(t *testing.T) {
	f := NewFixture([]int{11}, nil, []Thread{{Pid: 21, ThreadID: "t"}, {Pid: 22}}, 0)
	if err := f.Terminate(ctx, 99); !errors.Is(err, ErrNoSuchProcess) {
		t.Fatalf("unknown pid: %v", err)
	}
	if err := f.Terminate(ctx, 11); err != nil || f.IsAlive(ctx, 11) {
		t.Fatalf("alive pid: %v", err)
	}
	if err := f.Terminate(ctx, 11); !errors.Is(err, ErrNoSuchProcess) {
		t.Fatalf("second terminate: %v", err)
	}
	if err := f.Terminate(ctx, 21); err != nil {
		t.Fatal(err)
	}
	if got, _ := f.CodexThreads(ctx); !reflect.DeepEqual(got, []Thread{{Pid: 22}}) {
		t.Fatalf("threads = %v", got)
	}
}

func TestFixtureThreadsAreCopies(t *testing.T) {
	f := NewFixture(nil, nil, []Thread{{Pid: 1, ThreadID: "a"}}, 0)
	first, _ := f.CodexThreads(ctx)
	first[0].ThreadID = "changed"
	if again, _ := f.CodexThreads(ctx); again[0].ThreadID != "a" {
		t.Fatal("caller mutated the fixture list")
	}
}

func TestFixtureDelayOnlyFirstQuestion(t *testing.T) {
	f, err := LoadFixture(writeFixture(t, `{"alive":[1],"delayMs":80}`))
	if err != nil {
		t.Fatal(err)
	}
	t0 := time.Now()
	f.IsAlive(ctx, 1)
	if d := time.Since(t0); d < 70*time.Millisecond {
		t.Fatalf("first question took %v", d)
	}
	t1 := time.Now()
	f.IsAlive(ctx, 1)
	if d := time.Since(t1); d > 40*time.Millisecond {
		t.Fatalf("second question took %v", d)
	}
}

func TestFixtureDelayEndsWithContext(t *testing.T) {
	f := NewFixture([]int{1}, nil, nil, time.Hour)
	c, cancel := context.WithTimeout(ctx, 30*time.Millisecond)
	defer cancel()
	t0 := time.Now()
	if !f.IsAlive(c, 1) || time.Since(t0) > time.Second {
		t.Fatal("a canceled context must cut the delay short")
	}
}

// Gating, as AppEnvironment.live: the fixture exists only under SPACEVIBE_TEST=1.
func TestNewGating(t *testing.T) {
	path := writeFixture(t, `{"alive":[41001]}`)
	a, err := New(config.Config{Test: true}, path)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := a.(*Fixture); !ok || !a.IsAlive(ctx, 41001) {
		t.Fatalf("test mode with a file: %T", a)
	}
	empty, err := New(config.Config{Test: true}, "")
	if f, ok := empty.(*Fixture); err != nil || !ok || f.IsAlive(ctx, os.Getpid()) {
		t.Fatalf("test mode without a file must be the empty fixture: %T %v", empty, err)
	}
	bad, err := New(config.Config{Test: true}, filepath.Join(t.TempDir(), "none.json"))
	if f, ok := bad.(*Fixture); err == nil || !ok || f.IsAlive(ctx, os.Getpid()) {
		t.Fatalf("test mode with a bad file: error and the empty fixture, got %T %v", bad, err)
	}
	for _, p := range []string{path, ""} {
		sys, err := New(config.Config{}, p)
		if _, ok := sys.(System); err != nil || !ok {
			t.Fatalf("outside test mode the fixture path %q must be ignored: %T %v", p, sys, err)
		}
	}
}

func TestFixtureIdentify(t *testing.T) {
	f := NewFixture([]int{11}, map[int]string{11: "Mon Nov  2 11:58:00 2026"}, []Thread{{Pid: 21, ThreadID: "t"}}, 0)
	if id, err := f.Identify(ctx, 11); err != nil || id.Start != "Mon Nov  2 11:58:00 2026" || id.Name == "" {
		t.Fatalf("listed start: %+v %v", id, err)
	}
	if id, err := f.Identify(ctx, 21); err != nil || id.Start != fixtureStart {
		t.Fatalf("thread holder without a start gets the stand-in: %+v %v", id, err)
	}
	if _, err := f.Identify(ctx, 99); !errors.Is(err, ErrNoSuchProcess) {
		t.Fatalf("unknown pid: %v", err)
	}
}
