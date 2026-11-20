package usage

import (
	"bytes"
	"regexp"

	"spacevibe.dev/core/internal/textjs"
)

// codexParser reads Codex rollouts: skills and subagents named inside tool calls. Codex logs no hook runs.
type codexParser struct{}

func (codexParser) parseLine(line []byte, rec *fileRecord, fallbackDay string) {
	codexLine(line, rec, fallbackDay)
}

var (
	codexSkillPat    = regexp.MustCompile(`skills/([A-Za-z0-9_-]+)/SKILL\.md`)
	codexAgentPat    = regexp.MustCompile(`\\?"agent_type\\?":` + jsSpace + `*\\?"([A-Za-z0-9_-]+)`)
	codexCallPattern = regexp.MustCompile(`"type":"(function_call|custom_tool_call)"|"CommandExecution"`)
)

var (
	needleSkillMd   = []byte("SKILL.md")
	needleAgentType = []byte("agent_type")
)

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
