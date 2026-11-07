package activity

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"
)

// H12: every NSRegularExpression of ActivityFold.swift (7: explore, errorLine, zeroCount, exitLine, exitCode,
// stripCd, patchFile) and SessionTitles.swift (4: worktreeClaude, worktreeCodex, gitdirWorktree, gitdirLine) is
// ported to RE2 or to hand-written code (icu-patterns.go). testdata/icu-oracle/icu-oracle.json holds what ICU
// answered for 1558 inputs, including the edges the plan lists: \s with \v and U+0085 but not U+FEFF, \d on non-ASCII
// digits, $ before a final line terminator (\n \v \f \r U+0085 U+2028 U+2029, \r\n), . that stops at those
// terminators, Unicode \b with combining marks, full case folding, and Swift's CRLF-blind split on "\n".
// Swift: ActivityFold.swift:128-142 and SessionTitles.swift:61-64.

type oracleCase struct {
	Re    string `json:"re"`
	Input string `json:"input"`
	Out   any    `json:"out"`
}

func loadOracle(t *testing.T) []oracleCase {
	t.Helper()
	data, err := os.ReadFile("testdata/icu-oracle/icu-oracle.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []oracleCase
	if err := json.Unmarshal(data, &cases); err != nil {
		t.Fatal(err)
	}
	return cases
}

// oracleAnswer runs the Go port of the named pattern and returns the value in the oracle's shape.
func oracleAnswer(c oracleCase) any {
	capture := func(s string, ok bool) any {
		if !ok {
			return nil
		}
		return s
	}
	switch c.Re {
	case "explore":
		return matchesExplore(c.Input)
	case "errorLine":
		return matchesErrorLine(c.Input)
	case "zeroCount":
		return matchesZeroCount(c.Input)
	case "exitLine":
		return matchesExitLine(c.Input)
	case "exitCode":
		m := exitCodeRE.FindStringSubmatch(c.Input)
		if m == nil {
			return nil
		}
		return m[1]
	case "stripCd":
		if loc := stripCdRE.FindStringIndex(c.Input); loc != nil {
			return c.Input[loc[1]:]
		}
		return nil
	case "patchFile":
		out := []any{}
		for _, p := range patchFilePaths(c.Input) {
			out = append(out, p)
		}
		return out
	case "wtClaude":
		return capture(worktreeClaudeRepo(c.Input))
	case "wtCodex":
		return capture(worktreeCodexRepo(c.Input))
	case "gitdirWt":
		return capture(gitdirWorktreeMain(c.Input))
	case "gitdirLine":
		return capture(gitdirPath(c.Input))
	case "split":
		out := []any{}
		for _, line := range splitLines(c.Input) {
			out = append(out, line)
		}
		return out
	}
	return "unknown pattern " + c.Re
}

// icuKnownDifferences lists inputs where the Go port cannot match ICU exactly. It is empty: all 1558 agree.
var icuKnownDifferences = map[string]bool{}

func TestICUPatternsMatchOracle(t *testing.T) {
	cases := loadOracle(t)
	if len(cases) < 1500 {
		t.Fatalf("the oracle holds %d cases", len(cases))
	}
	perPattern := map[string]int{}
	for _, c := range cases {
		perPattern[c.Re]++
		if got := oracleAnswer(c); !reflect.DeepEqual(got, c.Out) && !icuKnownDifferences[c.Re+"\x00"+c.Input] {
			t.Errorf("%s %q: go %#v, ICU %#v", c.Re, c.Input, got, c.Out)
		}
	}
	for _, name := range []string{"explore", "errorLine", "zeroCount", "exitLine", "exitCode", "stripCd", "patchFile", "wtClaude", "wtCodex", "gitdirWt", "gitdirLine", "split"} {
		if perPattern[name] < 10 {
			t.Errorf("only %d oracle cases for %s", perPattern[name], name)
		}
	}
}

// The edges, named. Each expectation was read from NSRegularExpression (see the oracle), not assumed.
func TestICUPatternEdges(t *testing.T) {
	// \s: \v and U+0085 count, U+FEFF does not.
	eq(t, `git\vstatus`, matchesExplore("git\vstatus"), true)
	eq(t, "git\\u0085log", matchesExplore("git\u0085log"), true)
	eq(t, "git\\ufefflog", matchesExplore("git\xef\xbb\xbflog"), false)
	eq(t, "cd U+3000 dir", stripLeadingCd("cd　/x　&&　npm test"), "npm test")
	eq(t, "cd with U+FEFF is not a cd", stripLeadingCd("cd\xef\xbb\xbf/x && npm"), "cd\xef\xbb\xbf/x && npm")
	// $ also matches before a final line terminator; \d is any decimal digit.
	eq(t, "exit line, final LF", matchesExitLine("Exit code 1\n"), true)
	eq(t, "exit line, final CRLF", matchesExitLine("Exit code 1\r\n"), true)
	eq(t, "exit line, final U+0085", matchesExitLine("Exit code 1\u0085"), true)
	eq(t, "exit line, two LF", matchesExitLine("Exit code 1\n\n"), false)
	eq(t, "exit line, Arabic-Indic digit", matchesExitLine("Exit code ١٢"), true)
	if n, ok := exitCodeOf("Exit code ١"); ok {
		t.Errorf("a non-ASCII digit is not an Int: %d", n)
	}
	if n, ok := exitCodeOf("Exit code 99999999999999999999"); ok {
		t.Errorf("an overflowing code is not an Int: %d", n)
	}
	if n, ok := exitCodeOf("Exit code 007\nrest"); !ok || n != 7 {
		t.Errorf("exitCodeOf = %d, %v", n, ok)
	}
	// \b is Unicode: a letter next to "error" means no word boundary; a combining mark is skipped.
	eq(t, "error next to e-acute", matchesErrorLine("éerror"), false)
	eq(t, "error then underscore", matchesErrorLine("error_"), false)
	eq(t, "error then dash", matchesErrorLine("error-x"), true)
	eq(t, "0 errors then letter", matchesZeroCount("0 errorsx"), false)
	eq(t, "0 errors", matchesZeroCount("ok, 0 ERRORS."), true)
	// Full case folding: U+FB01 reads as "fi".
	eq(t, "undefined with the fi ligature", matchesErrorLine("undeﬁned is"), true)
	// . stops at \v \f U+0085 U+2028 as well as \n and \r.
	if _, ok := worktreeClaudeRepo("/a\vb/.claude/worktrees/x"); ok {
		t.Error("dot must not cross \\v")
	}
	if got, ok := worktreeCodexRepo("/h/.codex/worktrees/a/b\n"); !ok || got != "b\n" {
		t.Errorf("worktreeCodexRepo = %q %v", got, ok)
	}
	// gitdir: \s* runs over line breaks; the line start follows any terminator but not the middle of CRLF.
	if got, ok := gitdirPath("gitdir:\r\n/x"); !ok || got != "/x" {
		t.Errorf("gitdirPath = %q %v", got, ok)
	}
	if got, ok := gitdirPath("a gitdir: /x"); !ok || got != "/x" {
		t.Errorf("gitdirPath after U+2028 = %q %v", got, ok)
	}
	if _, ok := gitdirPath("x gitdir: /x"); ok {
		t.Error("gitdir must start a line")
	}
	// Swift split(separator: "\n") compares Characters: CRLF is one Character and does not split.
	if got := splitLines("a\r\nb\nc"); !reflect.DeepEqual(got, []string{"a\r\nb", "c"}) {
		t.Errorf("splitLines = %q", got)
	}
}
