package activity

import (
	"math"
	"strconv"

	"spacevibe.dev/core/internal/textjs"
)

func itoa(n int) string { return strconv.Itoa(n) }

var editTools = map[string]bool{"Edit": true, "MultiEdit": true, "Write": true, "NotebookEdit": true}

func claudeToolResult(st *logState, block jv, at float64) {
	id, hasID := block.field("tool_use_id").str()
	failedFlag, _ := block.field("is_error").boolean()
	failed := failedFlag
	finishPending(st, id, hasID, failed)
	if !hasID {
		return
	}
	if cmd, ok := st.bash[id]; ok {
		delete(st.bash, id)
		output := textOf(block.field("content"))
		exit, haveExit := 0, true
		if failed {
			exit, haveExit = exitCodeOf(output)
		}
		if haveExit {
			recordOutcome(st, id, cmd, at, exit, output)
		}
	}
	if edit, ok := st.editsPending[id]; ok {
		delete(st.editsPending, id)
		if !failed {
			for _, path := range edit.paths {
				st.edits = append(st.edits, editEvent{id: id + ":" + path, path: path, at: edit.at})
			}
		}
	}
}

func claudeHookFailure(st *logState, r, a jv) {
	blocking := false
	if t, _ := a.field("type").str(); t == "hook_blocking_error" {
		blocking = true
	}
	var command string
	var hasCommand bool
	if blocking {
		command, hasCommand = a.field("blockingError").field("command").str()
	} else {
		command, hasCommand = a.field("command").str()
	}
	event, hasEvent := a.field("hookEvent").str()
	if !hasCommand || !hasEvent {
		return
	}
	var raw string
	if blocking {
		raw, _ = a.field("blockingError").field("blockingError").str()
	} else if stderr := a.field("stderr"); stderr.truthy() {
		raw, _ = stderr.str()
	} else {
		raw, _ = a.field("stdout").str()
	}
	exitValue, hasExit := a.field("exitCode").integer()
	id, hasUUID := r.field("uuid").str()
	if !hasUUID {
		toolUseID, ok := a.field("toolUseID").str()
		if !ok {
			toolUseID = "undefined"
		}
		id = toolUseID + ":" + event + ":" + command
	}
	firstLine := ""
	for _, line := range splitLines(raw) {
		if textjs.Trim(line) != "" {
			firstLine = line
			break
		}
	}
	reason := previewText(firstLine)
	if reason == "" {
		if hasExit {
			reason = "Exit " + itoa(exitValue)
		} else {
			reason = "Hook failed"
		}
	}
	st.hookFailures = append(st.hookFailures, hookEvent{id: id, event: event, command: command, at: timestampOf(r), exit: optional(exitValue, hasExit), reason: reason})
}

func claudeAssistant(st *logState, r jv) {
	m := r.field("message")
	if model, ok := m.field("model").str(); ok && model != "<synthetic>" {
		st.model = model
	}
	at := timestampOf(r)
	if u := m.field("usage"); u.truthy() {
		// Streaming blocks repeat the message usage, so keep the maximum per message id.
		values := usage{
			Input: tokenCount(u.field("input_tokens")), Output: tokenCount(u.field("output_tokens")),
			CacheWrite:     tokenCount(u.field("cache_creation_input_tokens")),
			CacheWriteLong: tokenCount(u.field("cache_creation").field("ephemeral_1h_input_tokens")),
			CacheRead:      tokenCount(u.field("cache_read_input_tokens")),
		}
		messageID, ok := m.field("id").str()
		if !ok {
			if messageID, ok = r.field("uuid").str(); !ok {
				messageID = "undefined"
			}
		}
		key := st.model + ":" + messageID
		prev := st.claudeUsageSeen[key]
		metric, _ := st.metrics.Get(st.model)
		metric.Input += math.Max(0, values.Input-prev.Input)
		metric.Output += math.Max(0, values.Output-prev.Output)
		metric.CacheWrite += math.Max(0, values.CacheWrite-prev.CacheWrite)
		metric.CacheWriteLong += math.Max(0, values.CacheWriteLong-prev.CacheWriteLong)
		metric.CacheRead += math.Max(0, values.CacheRead-prev.CacheRead)
		st.metrics.Set(st.model, metric)
		st.claudeUsageSeen[key] = usage{
			Input: math.Max(values.Input, prev.Input), Output: math.Max(values.Output, prev.Output),
			CacheWrite: math.Max(values.CacheWrite, prev.CacheWrite), CacheWriteLong: math.Max(values.CacheWriteLong, prev.CacheWriteLong),
			CacheRead: math.Max(values.CacheRead, prev.CacheRead),
		}
	}
	blocks, _ := m.field("content").array()
	for _, bv := range blocks {
		b := present(bv)
		if t, _ := b.field("type").str(); t != "tool_use" {
			continue
		}
		input := b.field("input")
		name, _ := b.field("name").str()
		command, hasCommand := input.field("command").str()
		isBash := name == "Bash" && hasCommand
		file := firstPresent(input.field("file_path"), input.field("notebook_path"))
		targetValue := firstPresent(input.field("file_path"), input.field("command"), input.field("description"), input.field("pattern"))
		isEdit := editTools[name]
		id, hasID := b.field("id").str()
		target, _ := targetValue.str()
		addPending(st, id, hasID, name, target, at, isBash || isEdit || isQuestionTool(name))
		if !hasID || id == "" {
			continue
		}
		if isBash {
			st.bash[id] = command
		}
		if isEdit {
			if path, ok := file.str(); ok {
				st.editsPending[id] = pendingEdit{paths: []string{path}, at: at}
			}
		}
	}
}

// firstPresent is JavaScript's `a ?? b ?? c`: the first value that is not missing or null.
func firstPresent(values ...jv) jv {
	for _, v := range values {
		if v.ok {
			return v
		}
	}
	return jv{}
}

func foldClaude(st *logState, line []byte) {
	resultLine := textjs.Contains(line, `"tool_result"`)
	if resultLine && !textjs.Contains(line, `"type":"assistant"`) {
		// Most result lines are big file reads nobody needs: skip them unless a tracked tool owns them.
		ids := textjs.ToolUseIDs(line)
		if len(ids) > 0 {
			tracked := false
			for _, id := range ids {
				if p, ok := st.pending.Get(id); ok && p.track {
					tracked = true
					break
				}
			}
			if !tracked {
				for _, id := range ids {
					finishPending(st, id, true, false)
				}
				return
			}
		}
	}
	attachment := textjs.Contains(line, `"type":"attachment"`)
	wanted := resultLine || textjs.Contains(line, `"type":"user"`) || textjs.Contains(line, `"type":"assistant"`) ||
		textjs.Contains(line, `"type":"ai-title"`) || textjs.Contains(line, `"type":"custom-title"`) ||
		textjs.Contains(line, `"type":"worktree-state"`) ||
		(attachment && (textjs.Contains(line, "hook_non_blocking_error") || textjs.Contains(line, "hook_blocking_error")))
	if !wanted {
		return
	}
	r, ok := parseLine(line)
	if !ok {
		st.invalid++
		return
	}
	if cwd, ok := r.field("cwd").str(); ok && cwd != "" && st.cwd == "" {
		st.cwd = cwd
	}
	if !st.startedAtSet || st.startedAt == 0 {
		parsed := timestampOf(r)
		st.startedAt, st.startedAtSet = parsed, parsed != 0
	}
	kind, _ := r.field("type").str()
	switch kind {
	case "ai-title":
		if t, ok := r.field("aiTitle").str(); ok {
			st.aiTitle = t
		}
	case "custom-title":
		if t, ok := r.field("customTitle").str(); ok {
			st.customTitle = t
		}
	case "worktree-state":
		if o, ok := r.field("worktreeSession").field("originalCwd").str(); ok {
			st.worktreeOriginal = o
		}
	case "attachment":
		if a := r.field("attachment"); a.ok {
			if t, _ := a.field("type").str(); t == "hook_non_blocking_error" || t == "hook_blocking_error" {
				claudeHookFailure(st, r, a)
			}
		}
	case "assistant":
		claudeAssistant(st, r)
	case "user":
		content := r.field("message").field("content")
		at := timestampOf(r)
		text := ""
		if blocks, ok := content.array(); ok {
			for _, bv := range blocks {
				b := present(bv)
				t, _ := b.field("type").str()
				if t == "tool_result" {
					claudeToolResult(st, b, at)
				} else if t == "text" {
					if s, ok := b.field("text").str(); ok {
						text += s + "\n"
					}
				}
			}
		} else if s, ok := content.str(); ok {
			text += s + "\n"
		}
		if text != "" && !r.field("isMeta").truthy() && !r.field("isCompactSummary").truthy() && !r.field("isSidechain").truthy() {
			addPrompt(st, text)
		}
	}
}
