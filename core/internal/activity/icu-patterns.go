package activity

import (
	"regexp"
	"strconv"
	"unicode"
	"unicode/utf8"

	"spacevibe.dev/core/internal/textjs"
)

// The patterns of ActivityFold.swift and SessionTitles.swift ran on ICU (NSRegularExpression). Go's RE2 differs in
// four ways that matter for log text, so each pattern is written here with the ICU meaning spelled out:
//
//   - \s is the Unicode White_Space set (it has \v and U+0085 but not U+FEFF), not [\t\n\f\r ].
//   - \d is \p{Nd}. A capture of such digits that Int() cannot read leaves the value nil, as in Swift.
//   - . and $ know the line terminators \n \v \f \r U+0085 U+2028 U+2029 (and \r\n as one). $ also matches before
//     a final terminator.
//   - \b is built on the Unicode word set and ignores combining and format characters; (?i) uses full case folding.
//     Both are replaced by a hand-written check (icuWordBoundary) where a pattern needs them.
//
// icu-patterns_test.go runs every pattern against the recorded output of NSRegularExpression (testdata/icu-oracle.json).
const (
	icuSpaceSet = textjs.ICUSpaceSet
	icuSpace    = `[` + icuSpaceSet + `]`
	icuNotSpace = `[^` + icuSpaceSet + `]`
	icuTermSet  = textjs.ICUTermSet
	icuDot      = `[^` + icuTermSet + `]`
	// icuEnd is $ without the multiline flag: the end, or before one final line terminator.
	icuEnd = `(?:\r\n|[` + icuTermSet + `])?\z`
)

var (
	exploreRE = regexp.MustCompile(`^(?:cat|ls|rg|grep|find|sed|head|tail|wc|echo|pwd|which|stat|file|du|diff|` +
		`git` + icuSpace + `+(?:status|log|diff|show|branch|rev-parse|ls-files|grep|check-ignore)|` +
		`gh` + icuSpace + `+` + icuNotSpace + `+` + icuSpace + `+(?:view|list)|test` + icuSpace + `|\[)`)
	// errorLinePlainRE is the alternatives of Swift's errorLineRE that need no \b. ICU folds case in full, so the
	// ligature U+FB01 reads as "fi" inside "undefined is"; no other expansion (ss, ff, fl, st) occurs in a pattern.
	errorLinePlainRE = regexp.MustCompile(`(?i)exception|cannot|could not|couldn't|not found|denied|panic|fatal|unexpected|undefined is|unde\x{FB01}ned is|is not a function|✗|×`)
	// The three \b words are found case-insensitively and then checked for word boundaries on both sides.
	errorWordREs = []*regexp.Regexp{regexp.MustCompile(`(?i)error`), regexp.MustCompile(`(?i)failed`), regexp.MustCompile(`(?i)fail`)}
	zeroCountREs = []*regexp.Regexp{regexp.MustCompile(`(?i)0 failed`), regexp.MustCompile(`(?i)0 errors`), regexp.MustCompile(`(?i)0 error`)}
	exitLineRE   = regexp.MustCompile(`^Exit code \p{Nd}+` + icuEnd)
	exitCodeRE   = regexp.MustCompile(`^Exit code (\p{Nd}+)`)
	stripCdRE    = regexp.MustCompile(`^cd` + icuSpace + `+` + icuNotSpace + `+` + icuSpace + `*(?:&&|;)` + icuSpace + `*`)
	patchFileRE  = regexp.MustCompile(`\*\*\* (?:Update|Add|Delete) File: ([^\n\\"]+)`)

	worktreeClaudeRE = regexp.MustCompile(`^(` + icuDot + `*)[\\/]\.claude[\\/]worktrees[\\/][^\\/]+(?:[\\/]` + icuDot + `*)?` + icuEnd)
	worktreeCodexRE  = regexp.MustCompile(`[\\/]\.codex[\\/]worktrees[\\/][^\\/]+[\\/]([^\\/]+)(?:[\\/]` + icuDot + `*)?` + icuEnd)
	gitdirWorktreeRE = regexp.MustCompile(`^(` + icuDot + `*)[\\/]\.git[\\/]worktrees[\\/][^\\/]+` + icuEnd)
	// gitdirLineRE is tried at each line start by gitdirLine. The trailing $ of the ICU pattern holds by itself:
	// the greedy dot run stops only at a terminator or the end.
	gitdirLineRE = regexp.MustCompile(`^gitdir:` + icuSpace + `*(` + icuDot + `+)`)
)

// matchesExplore is isExploratory's test on a command with its leading cd removed.
func matchesExplore(cmd string) bool { return exploreRE.MatchString(cmd) }

// matchesExitLine is `^Exit code \d+$`.
func matchesExitLine(line string) bool { return exitLineRE.MatchString(line) }

// exitCodeOf is the `Exit code N` of a failed Claude tool result. It is false when there is no such line or when N
// is not an ASCII-digit number that fits an Int, which is what Swift's Int(String) gave (nil).
func exitCodeOf(output string) (int, bool) {
	m := exitCodeRE.FindStringSubmatch(output)
	if m == nil {
		return 0, false
	}
	n, err := strconv.ParseInt(m[1], 10, 64)
	if err != nil {
		return 0, false
	}
	return int(n), true
}

// stripLeadingCd removes a leading `cd <dir> &&` or `cd <dir> ;` from an already trimmed command.
func stripLeadingCd(trimmed string) string {
	loc := stripCdRE.FindStringIndex(trimmed)
	if loc == nil {
		return trimmed
	}
	return trimmed[loc[1]:]
}

// matchesErrorLine is errorLineRE.
func matchesErrorLine(line string) bool {
	return errorLinePlainRE.MatchString(line) || anyBounded(errorWordREs, line)
}

// matchesZeroCount is `\b0 (failed|errors?)\b`, case-insensitive. "errors?" is greedy and backs off, so both
// spellings are tried on their own.
func matchesZeroCount(line string) bool { return anyBounded(zeroCountREs, line) }

// anyBounded reports whether some match of some pattern sits between two word boundaries. ICU backtracks over every
// start and alternative, so one such match is enough.
func anyBounded(res []*regexp.Regexp, line string) bool {
	for _, re := range res {
		for _, loc := range re.FindAllStringIndex(line, -1) {
			if icuWordBoundary(line, loc[0]) && icuWordBoundary(line, loc[1]) {
				return true
			}
		}
	}
	return false
}

// patchFilePaths are the `*** Update|Add|Delete File: <path>` captures of a tool call's text, in order.
func patchFilePaths(raw string) []string {
	var out []string
	for _, m := range patchFileRE.FindAllStringSubmatch(raw, -1) {
		out = append(out, m[1])
	}
	return out
}

// firstGroupWorktreeClaude, firstGroupWorktreeCodex and firstGroupGitdirWorktree return capture 1 of the patterns
// of SessionTitles.swift, or false when the pattern does not match.
func worktreeClaudeRepo(cwd string) (string, bool) { return firstCapture(worktreeClaudeRE, cwd) }
func worktreeCodexRepo(cwd string) (string, bool)  { return firstCapture(worktreeCodexRE, cwd) }
func gitdirWorktreeMain(path string) (string, bool) {
	return firstCapture(gitdirWorktreeRE, path)
}

func firstCapture(re *regexp.Regexp, text string) (string, bool) {
	m := re.FindStringSubmatch(text)
	if m == nil {
		return "", false
	}
	return m[1], true
}

// gitdirPath is `^gitdir:\s*(.+)$` with anchorsMatchLines: the first line, in the whole text, that starts with
// "gitdir:". \s may run over line breaks, so the capture can come from a later line.
func gitdirPath(text string) (string, bool) {
	for pos := 0; pos <= len(text); {
		if m := gitdirLineRE.FindStringSubmatch(text[pos:]); m != nil {
			return m[1], true
		}
		next := nextLineStart(text, pos)
		if next < 0 {
			return "", false
		}
		pos = next
	}
	return "", false
}

// nextLineStart is the first position after pos where an ICU multiline ^ matches: right after a line terminator,
// but not between the \r and \n of a pair. It is -1 when there is none.
func nextLineStart(text string, pos int) int {
	for i := pos; i < len(text); {
		r, size := utf8.DecodeRuneInString(text[i:])
		i += size
		switch r {
		case '\n', '\v', '\f', 0x85, 0x2028, 0x2029:
			return i
		case '\r':
			if i < len(text) && text[i] == '\n' {
				continue
			}
			return i
		}
	}
	return -1
}

// splitLines is Swift's `split(separator: "\n", omittingEmptySubsequences: false)` on a String. Swift compares
// Characters, and "\r\n" is one Character that is not "\n", so an LF right after a CR does not split.
func splitLines(s string) []string {
	var parts []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' && (i == 0 || s[i-1] != '\r') {
			parts = append(parts, s[start:i])
			start = i + 1
		}
	}
	return append(parts, s[start:])
}

// icuWordBoundary is ICU's \b at byte offset pos of s (RegexMatcher::isWordBoundary): the position is a boundary when
// the character before it and the character at it differ in being word characters, where combining and format
// characters are skipped backwards and make a position inside a cluster never a boundary.
func icuWordBoundary(s string, pos int) bool {
	curWord := false
	if pos < len(s) {
		c, _ := utf8.DecodeRuneInString(s[pos:])
		if isGraphemeExtendOrFormat(c) {
			return false
		}
		curWord = isICUWord(c)
	}
	prevWord := false
	for i := pos; i > 0; {
		c, size := utf8.DecodeLastRuneInString(s[:i])
		i -= size
		if isGraphemeExtendOrFormat(c) {
			continue
		}
		prevWord = isICUWord(c)
		break
	}
	return curWord != prevWord
}

func isGraphemeExtendOrFormat(r rune) bool {
	return unicode.In(r, unicode.Mn, unicode.Me, unicode.Other_Grapheme_Extend, unicode.Cf)
}

// isICUWord is [\p{Alphabetic}\p{M}\p{Nd}\p{Pc}‌‍].
func isICUWord(r rune) bool {
	return unicode.IsLetter(r) || unicode.In(r, unicode.Nl, unicode.Other_Alphabetic, unicode.M, unicode.Nd, unicode.Pc) || r == 0x200c || r == 0x200d
}
