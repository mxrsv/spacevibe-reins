package activity

import (
	"math"
	"strconv"
	"strings"

	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/textjs"
)

func codexTokensOf(u jv) codexTokens {
	cached := firstPresent(u.field("cached_input_tokens"), u.field("cache_read_input_tokens"))
	return codexTokens{input: tokenCount(u.field("input_tokens")), output: tokenCount(u.field("output_tokens")), cacheRead: tokenCount(cached)}
}

// tokenText is a key for a token count: the integer text when it is whole, else the shortest float text.
func tokenText(d float64) string {
	if d == math.Round(d) && math.Abs(d) < 1e15 {
		return strconv.FormatInt(int64(d), 10)
	}
	return strconv.FormatFloat(d, 'g', -1, 64)
}

func codexUsage(st *logState, info jv, model string) {
	u := info.field("total_token_usage")
	if !u.truthy() {
		return
	}
	total := codexTokensOf(u)
	// A rollout can interleave streams (an embedded reviewer has its own running total) and repeat a total, so a
	// total already seen adds nothing, and the turn's own usage is trusted over the difference between two totals.
	seen := tokenText(total.input) + ":" + tokenText(total.output) + ":" + tokenText(total.cacheRead)
	if st.codexTotalsSeen[seen] {
		return
	}
	st.codexTotalsSeen[seen] = true
	var prior codexTokens
	if st.cumulative != nil {
		prior = *st.cumulative
	}
	var delta codexTokens
	if last := info.field("last_token_usage"); last.truthy() {
		delta = codexTokensOf(last)
	} else {
		delta = codexTokens{
			input:     difference(total.input, prior.input),
			output:    difference(total.output, prior.output),
			cacheRead: difference(total.cacheRead, prior.cacheRead),
		}
	}
	metric, _ := st.metrics.Get(model)
	// Codex input includes cached tokens and output includes reasoning tokens.
	metric.Input += math.Max(0, delta.input-delta.cacheRead)
	metric.CacheRead += delta.cacheRead
	metric.Output += delta.output
	st.metrics.Set(model, metric)
	st.cumulative = &total
}

// difference is the growth of a running total; a lower total is a restart and counts whole.
func difference(total, prior float64) float64 {
	if total >= prior {
		return total - prior
	}
	return total
}

func codexItem(st *logState, item jv, at float64) {
	kind, _ := item.field("type").str()
	switch kind {
	case "UserMessage":
		var blocks []ojson.Value
		items, _ := item.field("content").array()
		for _, b := range items {
			if t, _ := present(b).field("type").str(); t == "text" {
				blocks = append(blocks, b)
			}
		}
		text := textOf(present(ojson.Array(blocks...)))
		if text != "" {
			st.clearQuestions()
			if !isJunk(text) && st.firstPrompt == "" {
				st.firstPrompt = cleanTitle(text)
			}
		}
	case "CommandExecution":
		command := item.field("command")
		var cmd string
		var hasCmd bool
		if arr, ok := command.array(); ok {
			if len(arr) > 0 {
				cmd, hasCmd = present(arr[len(arr)-1]).str()
			}
		} else {
			cmd, hasCmd = command.str()
		}
		if exit, ok := item.field("exit_code").integer(); hasCmd && ok {
			id, hasID := item.field("id").str()
			if !hasID {
				id = "undefined"
			}
			output, _ := item.field("aggregated_output").str()
			recordOutcome(st, id, cmd, at, exit, output)
		}
	case "FileChange":
		st.sawFileChange = true
		if status := item.field("status"); status.truthy() {
			text, _ := status.str()
			lower := swiftLower(text)
			if !strings.Contains(lower, "complete") && !strings.Contains(lower, "success") {
				return
			}
		}
		id, hasID := item.field("id").str()
		if !hasID {
			id = "undefined"
		}
		members, _ := item.field("changes").object()
		for _, m := range members {
			st.edits = append(st.edits, editEvent{id: id + ":" + m.Key, path: m.Key, at: at})
		}
	}
}

func codexResponse(st *logState, p jv, at float64) {
	kind, _ := p.field("type").str()
	switch kind {
	case "function_call", "custom_tool_call":
		raw, hasRaw := firstPresent(p.field("arguments"), p.field("input")).str()
		target := ""
		if hasRaw {
			if doc, err := ojson.ParseString(raw); err == nil {
				a := present(doc.Root())
				if items, ok := a.field("command").array(); ok {
					if len(items) > 0 {
						target, _ = present(items[len(items)-1]).str()
					}
				} else {
					target, _ = firstPresent(a.field("cmd"), a.field("command")).str()
				}
			}
		}
		name, _ := p.field("name").str()
		callID, hasCallID := p.field("call_id").str()
		addPending(st, callID, hasCallID, name, target, at, isQuestionTool(name))
		// Older rollouts record patches only as tool text; used when no FileChange item exists in the file.
		if hasRaw && strings.Contains(raw, "*** ") {
			id := callID
			if !hasCallID {
				id = "undefined"
			}
			for n, path := range patchFilePaths(raw) {
				st.legacyEdits = append(st.legacyEdits, editEvent{id: id + ":" + strconv.Itoa(n), path: textjs.Trim(path), at: at})
			}
		}
	case "function_call_output", "custom_tool_call_output":
		id, ok := p.field("call_id").str()
		finishPending(st, id, ok, false)
	}
}

func foldCodex(st *logState, line []byte) {
	c := func(s string) bool { return textjs.Contains(line, s) }
	wanted := c(`"type":"session_meta"`) || c(`"type":"turn_context"`) ||
		(c(`"type":"event_msg"`) &&
			(c(`"type":"task_started"`) || c(`"type":"task_complete"`) || c(`"type":"turn_aborted"`) || c(`"type":"token_count"`) ||
				c(`"type":"item_completed"`) || c(`"type":"user_message"`)) &&
			(!c(`"type":"item_completed"`) || c(`"type":"UserMessage"`) || c(`"type":"CommandExecution"`) || c(`"type":"FileChange"`))) ||
		(c(`"type":"response_item"`) && (c(`"type":"function_call`) || c(`"type":"custom_tool_call`)))
	if !wanted {
		return
	}
	r, ok := parseLine(line)
	if !ok {
		st.invalid++
		return
	}
	p := r.field("payload")
	at := timestampOf(r)
	kind, _ := r.field("type").str()
	switch kind {
	case "session_meta":
		if !st.cwdSet {
			st.cwd, st.cwdSet = p.field("cwd").str()
		}
		if !st.startedAtSet {
			var fromPayload float64
			if text, ok := p.field("timestamp").str(); ok {
				fromPayload, _ = textjs.ParseTimestamp(text)
			}
			value := at
			if fromPayload != 0 {
				value = fromPayload
			}
			st.startedAt, st.startedAtSet = value, value != 0
		}
		st.parent = p.field("parent_thread_id").truthy() || p.field("source").field("subagent").truthy()
	case "turn_context":
		if model, ok := p.field("model").str(); ok {
			st.model = model
		}
		if !st.cwdSet {
			st.cwd, st.cwdSet = p.field("cwd").str()
		}
	case "event_msg":
		eventType, _ := p.field("type").str()
		switch eventType {
		case "task_started":
			st.status = "busy"
			st.clearQuestions()
		case "task_complete", "turn_aborted":
			st.status = "idle"
			st.pending.RemoveAll()
			st.clearQuestions()
		case "item_completed":
			if item := p.field("item"); item.truthy() {
				codexItem(st, item, at)
			}
		case "user_message":
			st.clearQuestions()
			if message, ok := p.field("message").str(); ok && !isJunk(message) && st.firstPrompt == "" {
				st.firstPrompt = cleanTitle(message)
			}
		case "token_count":
			codexUsage(st, p.field("info"), st.model)
		}
	case "response_item":
		codexResponse(st, p, at)
	}
}
