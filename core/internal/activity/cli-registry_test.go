package activity

import (
	"context"
	"errors"
	"slices"
	"testing"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
)

func TestActivityAdaptersMatchRegistry(t *testing.T) {
	if err := adapters.Check(); err != nil {
		t.Fatal(err)
	}
}

// MC-T3: a log of a CLI with no Activity adapter is an error. The old fold folded every id that was not Claude Code
// as a Codex rollout, and the old file grouping dropped it without a word.
func TestFoldRefusesACLIWithoutAdapter(t *testing.T) {
	sb := newSandbox(t)
	path := sb.put(".gemini/tmp/chat.jsonl", "{}\n", 0)
	cases := []struct {
		id   clis.ID
		want error
	}{{clis.Gemini, clis.ErrConceptAbsent}, {"nope", clis.ErrUnknownCLI}}
	for _, c := range cases {
		e := NewEngine()
		if _, _, err := e.advance(logFile{path: path, cli: c.id}, 1<<20); !errors.Is(err, c.want) {
			t.Errorf("advance(%s) = %v, want %v", c.id, err, c.want)
		}
		if len(e.cache) != 0 {
			t.Errorf("advance(%s) cached a log it could not fold", c.id)
		}
		if _, err := editsOf(newLogState(c.id)); !errors.Is(err, c.want) {
			t.Errorf("editsOf(%s) = %v, want %v", c.id, err, c.want)
		}
	}
}

func TestFileGroupingRefusesACLIWithoutAdapter(t *testing.T) {
	st := newLogState("nope")
	st.edits = []editEvent{{id: "e1", path: "/work/app/a.go", at: activityNowMs}}
	rows, err := groupFiles([]logEntry{{state: st, session: "nope:s1"}}, 10)
	if !errors.Is(err, clis.ErrUnknownCLI) || rows != nil {
		t.Fatalf("groupFiles = %v, %v; want ErrUnknownCLI", rows, err)
	}
}

// Stop of a session whose CLI has no Activity adapter signals nothing. The old livePid looked every id that was not
// Codex up as a Claude Code session, so Stop("gemini", <a Claude session id>) stopped that Claude session.
func TestStopRefusesACLIWithoutAdapter(t *testing.T) {
	sb := newSandbox(t)
	sb.status(11, obj{"procStart": stopStart})
	p := newFakeProc([]int{11}, map[int]string{11: stopStart}, nil)
	for _, c := range []struct {
		id   clis.ID
		want error
	}{{clis.Gemini, clis.ErrConceptAbsent}, {"nope", clis.ErrUnknownCLI}} {
		if _, err := stopSession(t, sb, c.id, activitySid(11), p, fastStop); !errors.Is(err, c.want) {
			t.Errorf("Stop(%s) = %v, want %v", c.id, err, c.want)
		}
	}
	if got := p.killedPids(); len(got) != 0 {
		t.Fatalf("signalled %v", got)
	}
}

// Every report lists each CLI's fixed limits in wire order, as the old fixed table did.
func TestFixedLimitsInWireOrder(t *testing.T) {
	want := []Limit{
		{CLI: clis.Claude, Code: ReasonClaudePromptVsBusy}, {CLI: clis.Codex, Code: ReasonCodexToolSilent},
		{CLI: clis.Codex, Code: ReasonCodexNoRollout}, {CLI: clis.Codex, Code: ReasonCodexHookRuns},
	}
	got := fixedLimits()
	if len(got) != len(want) {
		t.Fatalf("limits = %+v", got)
	}
	for i := range want {
		if got[i].CLI != want[i].CLI || got[i].Code != want[i].Code || got[i].Text != want[i].Code.Text() {
			t.Errorf("limit %d = %+v, want %+v", i, got[i], want[i])
		}
	}
}

// The approval limit the shell words a waiting session with comes from the adapter's state function and is one of the
// limits every report lists, so the shell finds its text there.
func TestApprovalLimitIsAFixedLimit(t *testing.T) {
	for _, a := range adapters.InOrder() {
		code, err := ApprovalLimit(a.ID)
		if err != nil {
			t.Fatal(err)
		}
		if code != "" && !slices.Contains(a.Adapter.limits(), code) {
			t.Errorf("%s: approval limit %s is not in its fixed limits %v", a.ID, code, a.Adapter.limits())
		}
	}
	if got, _ := ApprovalLimit(clis.Claude); got != ReasonClaudePromptVsBusy {
		t.Errorf("claude = %q", got)
	}
	if got, _ := ApprovalLimit(clis.Codex); got != ReasonCodexToolSilent {
		t.Errorf("codex = %q", got)
	}
	if _, err := ApprovalLimit(clis.Gemini); !errors.Is(err, clis.ErrConceptAbsent) {
		t.Errorf("gemini = %v", err)
	}
	quiet := newLogState(clis.Codex)
	quiet.status = "busy"
	quiet.pending.Set("t", pendingCall{name: "Bash"})
	for name, got := range map[string]stateInfo{
		"claude": claudeState(true, "busy", quiet, 60_000, 1_000),
		"codex":  codexState(quiet, 60_000, 1_000),
	} {
		want, _ := ApprovalLimit(clis.ID(name))
		if got.reason == nil || *got.reason != want {
			t.Errorf("%s state of a quiet tool run = %+v, want the approval limit %s", name, got, want)
		}
	}
}

// processesOnly embeds the Adapter interface, so it hides every CLI's process match: the shape of an adapter that
// lacks Codex's match.
type processesOnly struct{ proc.Adapter }

// The Codex match is not part of proc.Adapter; an adapter without it is the concept absent, read as an unknown
// process list (the Codex rows cannot be listed, Stop cannot verify), never as "no Codex sessions".
func TestCodexWithoutProcessMatchIsAbsentNotEmpty(t *testing.T) {
	ctx := context.Background()
	fake := newFakeProc([]int{26}, map[int]string{26: stopStart}, []proc.Thread{{Pid: 26, ThreadID: activityUUID(26)}})
	if _, err := codexMatcher(fake); err != nil {
		t.Fatalf("codexMatcher(fake) = %v", err)
	}
	bare := processesOnly{fake}
	if _, err := codexMatcher(bare); !errors.Is(err, clis.ErrConceptAbsent) {
		t.Fatalf("codexMatcher(bare) = %v, want ErrConceptAbsent", err)
	}
	read := &codexRead{byID: map[string]logFile{}}
	read.findLive(ctx, bare)
	if limits := read.extraLimits(); !read.unknown || len(limits) != 1 || limits[0].Code != ReasonCodexProcessUnknown {
		t.Errorf("findLive without a match: unknown = %v, limits = %+v", read.unknown, limits)
	}
	if got := (codexActivity{}).livePid(ctx, roots.CLIRoots{}, activityUUID(26), bare); got.found || !got.unverified {
		t.Errorf("livePid without a match = %+v, want unverified", got)
	}
}
