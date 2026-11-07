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
	locks := []Thread{{10, activityUuid(1)}, {10, activityUuid(2)}, {12, activityUuid(3)}}
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
		{"two locks of one pid", "p10\nn" + lock + "\nn/h/.codex/thread-writer-locks/" + activityUuid(8) + ".lock", []Thread{{10, u}, {10, activityUuid(8)}}},
		{"fd lines are ignored", "p10\nf5\nn" + lock + "\nf6\nn/dev/null", []Thread{{10, u}}},
		{"windows separators", `p10` + "\n" + `nC:\h\thread-writer-locks\` + u + ".lock", []Thread{{10, u}}},
		{"upper case hex is rejected", "p10\nn/h/thread-writer-locks/ABCDEF01-0000-4000-8000-00000000000A.lock", nil},
		{"wrong folder", "p10\nn/h/other-locks/" + u + ".lock", nil},
		{"wrong extension", "p10\nn/h/thread-writer-locks/" + u + ".lockx", nil},
		{"short uuid", "p10\nn/h/thread-writer-locks/0000-4000.lock", nil},
		{"folder must be a whole segment", "p10\nn/h/xthread-writer-locks/" + u + ".lock", []Thread{}},
		{"name line before any pid is dropped", "n" + lock, nil},
		{"unparsable pid drops its names", "p10\nn" + lock + "\npabc\nn" + lock, []Thread{{10, u}}},
		{"pid line resets the pid", "p10\npxyz\nn" + lock, nil},
		{"trailing CR", "p10\nn" + lock + "\r", []Thread{{10, u}}},
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
