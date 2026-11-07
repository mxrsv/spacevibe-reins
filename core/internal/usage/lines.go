package usage

import (
	"bytes"
	"math"
	"regexp"
	"strconv"
	"strings"
	"time"

	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/ojson"
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
// classes are spelled out there as here.
var (
	timestampPattern = regexp.MustCompile(`"timestamp":"([0-9]{4}-[0-9]{2}-[0-9]{2})T`)
	skillToolPattern = regexp.MustCompile(`"name":"Skill","input":\{"skill":"([^"]+)"`)
	slashPattern     = regexp.MustCompile(`<command-name>/([A-Za-z0-9_:-]+)</command-name>`)
	subagentPattern  = regexp.MustCompile(`"subagent_type":"([^"]+)"`)
	codexSkillPat    = regexp.MustCompile(`skills/([A-Za-z0-9_-]+)/SKILL\.md`)
	codexAgentPat    = regexp.MustCompile(`\\?"agent_type\\?":` + jsSpace + `*\\?"([A-Za-z0-9_-]+)`)
	codexCallPattern = regexp.MustCompile(`"type":"(function_call|custom_tool_call)"|"CommandExecution"`)
)

var (
	needleTimestamp   = []byte(`"timestamp":"`)
	needleSkill       = []byte(`"name":"Skill"`)
	needleCommandName = []byte("<command-name>")
	needleUserType    = []byte(`"type":"user"`)
	needleSubagent    = []byte(`"subagent_type":"`)
	needleAttachment  = []byte(`"attachment"`)
	needleHook        = []byte(`"hook`)
	needleSkillMd     = []byte("SKILL.md")
	needleAgentType   = []byte("agent_type")
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

// claudeLine folds one line of a Claude log into rec. The cheap byte checks come first so most lines are
// never turned into a string.
func claudeLine(line []byte, rec *fileRecord, fallbackDay string) {
	hasSkill := bytes.Contains(line, needleSkill)
	hasSlash := bytes.Contains(line, needleCommandName) && bytes.Contains(line, needleUserType)
	hasAgent := bytes.Contains(line, needleSubagent)
	hasHook := bytes.Contains(line, needleAttachment) && bytes.Contains(line, needleHook)
	if !hasSkill && !hasSlash && !hasAgent && !hasHook {
		return
	}
	text := textjs.Repair(string(line))
	seen, ok := dayInText(text)
	if !ok {
		seen = fallbackDay
	}
	if hasSkill {
		noteAll(skillToolPattern, text, rec.Skill, seen, true)
	}
	if hasSlash {
		noteAll(slashPattern, text, rec.Skill, seen, true)
	}
	if hasAgent {
		noteAll(subagentPattern, text, rec.Agent, seen, true)
	}
	if hasHook {
		hookRecord(text, rec, seen)
	}
}

// hookRecord counts a `hook_*` attachment. hook_blocking_error nests the command under blockingError; the
// other types carry it at the top level.
func hookRecord(text string, rec *fileRecord, day string) {
	doc, err := ojson.ParseString(text)
	if err != nil {
		return
	}
	attachment, ok := doc.Root().Member("attachment")
	if !ok || attachment.Kind() != ojson.KindObject {
		return
	}
	typeValue, ok := stringMember(attachment, "type")
	if !ok || !strings.HasPrefix(typeValue, "hook_") {
		return
	}
	command, ok := stringMember(attachment, "command")
	if !ok {
		nested, found := attachment.Member("blockingError")
		if !found {
			return
		}
		if command, ok = stringMember(nested, "command"); !ok {
			return
		}
	}
	event, present := attachment.Member("hookEvent")
	hash := hashes.HookHash(jsString(event, present), command)
	h := rec.Hook[hash]
	h.Runs++
	if ms, ok := finiteMember(attachment, "durationMs"); ok {
		h.Ms += ms
		h.Timed++
	}
	if code, ok := finiteMember(attachment, "exitCode"); strings.Contains(typeValue, "error") || (ok && code != 0) {
		h.Errors++
	}
	if h.Last == nil || day > *h.Last {
		d := day
		h.Last = &d
	}
	rec.Hook[hash] = h
}

func stringMember(v ojson.Value, key string) (string, bool) {
	m, ok := v.Member(key)
	if !ok {
		return "", false
	}
	return m.StringValue()
}

// finiteMember is Number.isFinite: a JSON number only (not a boolean or a string).
func finiteMember(v ojson.Value, key string) (float64, bool) {
	m, ok := v.Member(key)
	if !ok {
		return 0, false
	}
	text, ok := m.NumberText()
	if !ok {
		return 0, false
	}
	f, err := strconv.ParseFloat(text, 64)
	if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
		return 0, false
	}
	return f, true
}

// jsString is `${value}` of a JSON value, for the hook identity: "undefined" when the field is missing
// (present false). A number keeps its source text and any array or object reads "[object Object]", as the
// Swift port has it.
func jsString(v ojson.Value, present bool) string {
	if !present {
		return "undefined"
	}
	switch v.Kind() {
	case ojson.KindNull:
		return "null"
	case ojson.KindString:
		s, _ := v.StringValue()
		return s
	case ojson.KindBool:
		if b, _ := v.BoolValue(); b {
			return "true"
		}
		return "false"
	case ojson.KindNumber:
		n, _ := v.NumberText()
		return n
	default:
		return "[object Object]"
	}
}

// codexLine folds one line of a Codex rollout into rec. Skills and agents count only inside tool calls.
func codexLine(line []byte, rec *fileRecord, fallbackDay string) {
	hasSkill := bytes.Contains(line, needleSkillMd)
	hasAgent := bytes.Contains(line, needleAgentType)
	if !hasSkill && !hasAgent {
		return
	}
	text := textjs.Repair(string(line))
	if !codexCallPattern.MatchString(text) {
		return
	}
	seen, ok := dayInText(text)
	if !ok {
		seen = fallbackDay
	}
	if hasSkill {
		noteAll(codexSkillPat, text, rec.Skill, seen, false)
	}
	if hasAgent {
		noteAll(codexAgentPat, text, rec.Agent, seen, false)
	}
}
