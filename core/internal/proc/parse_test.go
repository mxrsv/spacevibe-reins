package proc

import (
	"fmt"
	"reflect"
	"strings"
	"testing"
)

// activityUuid mirrors the Swift test helper: a fixed-shape uuid per n.
func activityUuid(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012x", n) }

func TestParsersReadPsAndLsof(t *testing.T) { // Swift: ActivityTests.swift "process adapter parsers read ps and lsof output"
	ps := strings.Join([]string{
		"  100 /Users/me/.local/bin/codex --no-daemon -c tui.animations=false",
		"  101 /Applications/Codex.app/codex app-server --listen stdio",
		"  104 /Applications/Codex.app/codex mcp-server",
		"  102 /usr/bin/node /x/not-codex.js",
		"  103 codex",
	}, "\n")
	if got, want := CodexPids(ps), []int{100, 103}; !reflect.DeepEqual(got, want) {
		t.Fatalf("CodexPids = %v, want %v", got, want)
	}
	lsof := strings.Join([]string{"p100", "n/Users/me/.codex/.sqlite-maintenance.lock", "n/Users/me/.codex/thread-writer-locks/" + activityUuid(1) + ".lock", "p103", "n/etc/hosts"}, "\n")
	want := []Thread{{Pid: 100, ThreadID: activityUuid(1)}}
	if got := LockFds(lsof); !reflect.DeepEqual(got, want) {
		t.Fatalf("LockFds = %v, want %v", got, want)
	}
}

func TestMergeThreads(t *testing.T) { // Swift: ReadHardeningTests.swift "merge: a pid without a lock has no thread, and a pid with locks is not repeated"
	locks := []Thread{{Pid: 10, ThreadID: activityUuid(1)}, {Pid: 10, ThreadID: activityUuid(2)}, {Pid: 12, ThreadID: activityUuid(3)}}
	merged := MergeThreads([]int{10, 11, 12, 13}, locks)
	want := append(append([]Thread{}, locks...), Thread{Pid: 11}, Thread{Pid: 13})
	if !reflect.DeepEqual(merged, want) {
		t.Fatalf("merged = %v, want %v", merged, want)
	}
	n := 0
	for _, m := range merged {
		if m.Pid == 10 {
			n++
		}
	}
	if n != 2 {
		t.Fatalf("pid 10 appears %d times, want 2", n)
	}
	if got := MergeThreads(nil, nil); len(got) != 0 {
		t.Fatalf("empty merge = %v", got)
	}
	if got := MergeThreads([]int{5}, nil); !reflect.DeepEqual(got, []Thread{{Pid: 5}}) {
		t.Fatalf("bare pid = %v", got)
	}
}

// Extra vectors for psLine (the ICU-to-RE2 port, plan H12).
func TestPsLineVectors(t *testing.T) {
	cases := []struct {
		name, line string
		want       []int
	}{
		{"bare name", "1 codex", []int{1}},
		{"leading spaces and path", "   77   /opt/bin/codex", []int{77}},
		{"tab separated", "5\tcodex\t--flag", []int{5}},
		{"helper word as a later argument", "8 codex --x app-server", nil},
		{"helper word needs a whole word", "8 codex --app-server-x", []int{8}},
		{"helper word inside quotes is still a word", "8 codex mcp-server\t--y", nil},
		{"name must end at a boundary", "9 codexx", nil},
		{"name must start after a slash", "9 /bin/mycodex", nil},
		{"upper case is another program", "9 Codex", nil},
		{"no pid", "codex --x", nil},
		{"non digit pid", "x9 codex", nil},
		{"pid overflows Int", "99999999999999999999 codex", nil},
		{"trailing CR is ICU's $", "12 codex\r", []int{12}},
		{"trailing CR before args", "12 codex --a\r", []int{12}},
		{"trailing NEL", "12 codex\u0085", []int{12}},
		{"trailing U+2028", "12 codex ", []int{12}},
		{"CR in the middle ends the match (ICU dot)", "12 codex a\rb", nil},
		{"unicode space between pid and name", "12 codex", []int{12}},
		{"vertical tab is a space", "12\vcodex", []int{12}},
		{"empty input", "", nil},
		{"CRLF output is split on LF", "1 codex\r\n2 codex app-server\r\n3 codex\r\n", []int{1, 3}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := CodexPids(c.line); !reflect.DeepEqual(got, c.want) {
				t.Fatalf("CodexPids(%q) = %v, want %v", c.line, got, c.want)
			}
		})
	}
}

// Extra vectors for lockPath and the lsof field parser.
func TestLockFdsVectors(t *testing.T) {
	u := activityUuid(7)
	lock := "/h/.codex/thread-writer-locks/" + u + ".lock"
	cases := []struct {
		name, out string
		want      []Thread
	}{
		{"two locks of one pid", "p10\nn" + lock + "\nn/h/.codex/thread-writer-locks/" + activityUuid(8) + ".lock", []Thread{{Pid: 10, ThreadID: u}, {Pid: 10, ThreadID: activityUuid(8)}}},
		{"fd lines are ignored", "p10\nf5\nn" + lock + "\nf6\nn/dev/null", []Thread{{Pid: 10, ThreadID: u}}},
		{"windows separators", `p10` + "\n" + `nC:\h\thread-writer-locks\` + u + ".lock", []Thread{{Pid: 10, ThreadID: u}}},
		{"upper case hex is rejected", "p10\nn/h/thread-writer-locks/ABCDEF01-0000-4000-8000-00000000000A.lock", nil},
		{"wrong folder", "p10\nn/h/other-locks/" + u + ".lock", nil},
		{"wrong extension", "p10\nn/h/thread-writer-locks/" + u + ".lockx", nil},
		{"short uuid", "p10\nn/h/thread-writer-locks/0000-4000.lock", nil},
		{"folder must be a whole segment", "p10\nn/h/xthread-writer-locks/" + u + ".lock", []Thread{}},
		{"name line before any pid is dropped", "n" + lock, nil},
		{"unparsable pid drops its names", "p10\nn" + lock + "\npabc\nn" + lock, []Thread{{Pid: 10, ThreadID: u}}},
		{"pid line resets the pid", "p10\npxyz\nn" + lock, nil},
		{"trailing CR", "p10\nn" + lock + "\r", []Thread{{Pid: 10, ThreadID: u}}},
		{"empty", "", nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := LockFds(c.out)
			if len(got) == 0 && len(c.want) == 0 {
				return
			}
			if !reflect.DeepEqual(got, c.want) {
				t.Fatalf("LockFds = %v, want %v", got, c.want)
			}
		})
	}
}

// G-fix.10: one ps reading gives the start time and the executable basename.
func TestParseIdentity(t *testing.T) {
	for _, c := range []struct {
		name string
		in   string
		want Identity
		ok   bool
	}{
		{"full path", "Mon Nov  2 11:58:00 2026 /Users/a/.local/share/claude/versions/2.1.0\n", Identity{"Mon Nov 2 11:58:00 2026", "2.1.0"}, true},
		{"bare name", "Mon Nov  2 11:58:00 2026 codex", Identity{"Mon Nov 2 11:58:00 2026", "codex"}, true},
		{"path with spaces", "Mon Nov  2 11:58:00 2026 /Applications/My App/bin/codex", Identity{"Mon Nov 2 11:58:00 2026", "codex"}, true},
		{"no command", "Mon Nov  2 11:58:00 2026", Identity{}, false},
		{"trailing slash", "Mon Nov  2 11:58:00 2026 /usr/bin/", Identity{}, false},
		{"empty", "", Identity{}, false},
	} {
		got, ok := ParseIdentity(c.in)
		if ok != c.ok || got != c.want {
			t.Errorf("%s: ParseIdentity = %+v, %v; want %+v, %v", c.name, got, ok, c.want, c.ok)
		}
	}
}

func TestLsofUsable(t *testing.T) {
	for _, c := range []struct {
		status int
		out    string
		want   bool
	}{
		{0, "p1\nn/x", true},
		{1, "p1\nn/x", true}, // some pids already gone, the rest listed
		{1, "", false},       // nothing listed: not provably "no threads"
		{0, "  \n", false},
		{-1, "p1\n", false}, // killed by timeout
		{2, "p1\n", false},
	} {
		if got := LsofUsable(c.status, c.out); got != c.want {
			t.Errorf("LsofUsable(%d, %q) = %v, want %v", c.status, c.out, got, c.want)
		}
	}
}

// ICU line terminators include \v (U+000B) and \f (U+000C): `.` stops at them and `$` accepts one before the end.
// Confirmed against NSRegularExpression (finding 9).
func TestPsLineVerticalTabAndFormFeed(t *testing.T) {
	cases := []struct {
		name, line string
		want       []int
	}{
		{"FF in the arguments ends the match", "123 codex a\f b", nil},
		{"FF between two arguments", "123 codex a\fb", nil},
		{"VT in the arguments ends the match", "123 codex a\v b", nil},
		{"VT between two arguments", "123 codex a\vb", nil},
		{"trailing FF is ICU's $", "123 codex a\f", []int{123}},
		{"trailing VT is ICU's $", "123 codex --flag\v", []int{123}},
		{"trailing VT after the bare name", "123 codex\v", []int{123}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := CodexPids(c.line); !reflect.DeepEqual(got, c.want) {
				t.Fatalf("CodexPids(%q) = %v, want %v", c.line, got, c.want)
			}
		})
	}
}
