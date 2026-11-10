package activity

import (
	"strings"

	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/redact"
	"spacevibe.dev/core/internal/textjs"
)

// ActivityFold.swift: folds one session log (a Claude Code transcript or a Codex rollout) into a small state, one
// line at a time. Most lines are skipped by a byte search before any JSON parse; the search strings are the ones the
// Node code used, so both sides skip the same lines.

const (
	previewLen       = 160
	passesPerCommand = 50
)

// previewText is `s.replace(/\s+/g, ' ').trim().slice(0, n)`.
func previewText(value string) string { return textjs.Prefix(textjs.Squash(value), previewLen) }

func stripCd(cmd string) string { return stripLeadingCd(textjs.Trim(cmd)) }

func normalizeCommand(cmd string) string {
	return textjs.Prefix(textjs.Collapse(stripCd(cmd)), 400)
}

// isExploratory: grep, ls and diff exit non-zero by design, so they are not failures.
func isExploratory(cmd string) bool { return matchesExplore(stripCd(cmd)) }

// errorLine is the line a person would quote from a failure, not the runner's preamble.
func errorLine(output string) string {
	for _, raw := range splitLines(output) {
		line := textjs.Trim(raw)
		if line == "" || matchesExitLine(line) {
			continue
		}
		if matchesErrorLine(line) && !matchesZeroCount(line) {
			return textjs.Prefix(line, previewLen)
		}
	}
	return ""
}

// textOf is the text of a tool result `content`: a string, or the text blocks of an array joined by newlines.
func textOf(content jv) string {
	if s, ok := content.str(); ok {
		return s
	}
	items, ok := content.array()
	if !ok {
		return ""
	}
	var parts []string
	for _, b := range items {
		bj := present(b)
		text, isString := bj.str()
		if !isString {
			text, _ = bj.field("text").str()
			if text == "" {
				text, _ = bj.field("input_text").str()
			}
		}
		if text != "" {
			parts = append(parts, text)
		}
	}
	return strings.Join(parts, "\n")
}

// isQuestionTool is `(?:^|__|\.)(AskUserQuestion|request_user_input(?:_async)?)$`.
func isQuestionTool(name string) bool {
	for _, tool := range []string{"AskUserQuestion", "request_user_input", "request_user_input_async"} {
		if name == tool || strings.HasSuffix(name, "__"+tool) || strings.HasSuffix(name, "."+tool) {
			return true
		}
	}
	return false
}

func timestampOf(r jv) float64 {
	text, ok := r.field("timestamp").str()
	if !ok {
		return 0
	}
	ms, parsed := textjs.ParseTimestamp(text)
	if !parsed {
		return 0
	}
	return ms
}

func recordOutcome(st *logState, id, cmd string, at float64, exit int, output string) {
	command := normalizeCommand(cmd)
	if command == "" {
		return
	}
	key := hashes.Sha(command)
	if exit == 0 {
		list := append(st.passes[key], at)
		if len(list) > passesPerCommand {
			list = list[1:]
		}
		st.passes[key] = list
	} else if !isExploratory(cmd) {
		line := errorLine(output)
		reason := line
		if line == "" {
			reason = "Exit " + itoa(exit)
		}
		st.failures = append(st.failures, failureEvent{id: id, key: key, cmd: command, at: at, exit: exit, reason: reason})
	}
}

func addPrompt(st *logState, text string) {
	plain := textjs.Trim(text)
	if isJunk(plain) {
		return
	}
	st.pending.RemoveAll()
	st.clearQuestions()
	if st.firstPrompt == "" {
		st.firstPrompt = cleanTitle(plain)
	}
}

func addPending(st *logState, id string, hasID bool, name, target string, at float64, track bool) {
	if !hasID || id == "" {
		return
	}
	st.pending.Set(id, pendingCall{name: previewText(name), target: previewText(redact.Command(target)), at: at, track: track})
	if isQuestionTool(name) {
		st.questions[id] = true
	}
}

func finishPending(st *logState, id string, hasID, failed bool) {
	if !hasID || id == "" {
		return
	}
	pending, _ := st.pending.Get(id)
	st.pending.Delete(id)
	// request_user_input_async answers immediately; the wait ends at the next user message instead.
	if st.questions[id] && (failed || !strings.HasSuffix(pending.name, "request_user_input_async")) {
		delete(st.questions, id)
	}
}

// parseLine is OrderedJSON(data: line) with the root required to be an object.
func parseLine(line []byte) (jv, bool) {
	doc, err := ojson.Parse(line)
	if err != nil {
		return jv{}, false
	}
	root := doc.Root()
	if _, isObject := root.ObjectValue(); !isObject {
		return jv{}, false
	}
	return present(root), true
}

// editsOf is the edits of one log state, preferring FileChange items over the older tool-text patches.
func editsOf(st *logState) []editEvent {
	if st.cli != CLICodex || st.sawFileChange {
		return st.edits
	}
	base := st.cwd
	out := make([]editEvent, len(st.legacyEdits))
	for i, e := range st.legacyEdits {
		if strings.HasPrefix(e.path, "/") || base == "" {
			out[i] = e
			continue
		}
		out[i] = editEvent{id: e.id, path: strings.TrimSuffix(base, "/") + "/" + e.path, at: e.at}
	}
	return out
}

func fold(st *logState, line []byte) {
	if st.cli == CLIClaude {
		foldClaude(st, line)
	} else {
		foldCodex(st, line)
	}
}
