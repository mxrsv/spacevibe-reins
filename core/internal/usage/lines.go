package usage

import (
	"bytes"
	"regexp"
	"time"

	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/textjs"
)

// fileRecord is what one log file yields, and the only thing the cache keeps of it: names, days, hook
// hashes and durations. Never log text. Skill and Agent map a bare name to the days (YYYY-MM-DD) on
// which it appeared in this file.
type fileRecord struct {
	Skill map[string][]string   `json:"skill"`
	Agent map[string][]string   `json:"agent"`
	Hook  map[string]HookTotals `json:"hook"`
}

func newFileRecord() fileRecord {
	return fileRecord{Skill: map[string][]string{}, Agent: map[string][]string{}, Hook: map[string]HookTotals{}}
}

// jsSpace is ICU's \s (Unicode White_Space): RE2's \s lacks \v, U+0085 and the Unicode spaces.
const jsSpace = `[\t-\r \x{85}\x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}]`

// The patterns of UsageScanLines.swift. ICU's \w would be Unicode and JavaScript's is ASCII, so the
// classes are spelled out there as here. Each CLI's own patterns live in its parser file.
var (
	timestampPattern = regexp.MustCompile(`"timestamp":"([0-9]{4}-[0-9]{2}-[0-9]{2})T`)
	needleTimestamp  = []byte(`"timestamp":"`)
)

// dayOf is the day of the first `"timestamp":"YYYY-MM-DD` in the line, or "" and false.
func dayOf(line []byte) (string, bool) {
	if !bytes.Contains(line, needleTimestamp) {
		return "", false
	}
	return dayInText(textjs.Repair(string(line)))
}

func dayInText(text string) (string, bool) {
	m := timestampPattern.FindStringSubmatch(text)
	if m == nil {
		return "", false
	}
	return m[1], true
}

// isoDay is YYYY-MM-DD of a time in UTC, as toISOString().slice(0, 10).
func isoDay(ms int64) string { return time.UnixMilli(ms).UTC().Format("2006-01-02") }

func note(group map[string][]string, name, day string) {
	days := group[name]
	if !contains(days, day) {
		days = append(days, day)
	}
	group[name] = days
}

func contains(items []string, item string) bool {
	for _, s := range items {
		if s == item {
			return true
		}
	}
	return false
}

func noteAll(re *regexp.Regexp, text string, group map[string][]string, day string, bare bool) {
	for _, m := range re.FindAllStringSubmatch(text, -1) {
		name := m[1]
		if bare {
			name = hashes.Bare(name)
		}
		note(group, name, day)
	}
}
