package usage

import (
	"bytes"
	"math"
	"regexp"
	"strconv"
	"strings"

	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/textjs"
)

// claudeParser reads Claude Code transcripts: skills from the Skill tool and slash commands, subagents from
// subagent_type, and hook runs from hook_* attachments.
type claudeParser struct{}

func (claudeParser) parseLine(line []byte, rec *fileRecord, fallbackDay string) {
	claudeLine(line, rec, fallbackDay)
}

var (
	skillToolPattern = regexp.MustCompile(`"name":"Skill","input":\{"skill":"([^"]+)"`)
	slashPattern     = regexp.MustCompile(`<command-name>/([A-Za-z0-9_:-]+)</command-name>`)
	subagentPattern  = regexp.MustCompile(`"subagent_type":"([^"]+)"`)
)

var (
	needleSkill       = []byte(`"name":"Skill"`)
	needleCommandName = []byte("<command-name>")
	needleUserType    = []byte(`"type":"user"`)
	needleSubagent    = []byte(`"subagent_type":"`)
	needleAttachment  = []byte(`"attachment"`)
	needleHook        = []byte(`"hook`)
)

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
