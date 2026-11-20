package activity

import (
	"path/filepath"

	"spacevibe.dev/core/internal/textjs"
)

// The session rows of Activity.swift, shared by every CLI: states and their sentences. Each CLI builds its rows in
// its own file (claude-sessions.go, codex-sessions.go) behind its sessionSource (adapters.go).

// stateInfo is a session state with the sentence that explains it.
type stateInfo struct {
	state  SessionState
	reason *Reason
	text   string
	tool   *Tool
}

func unmeasurable(code Reason, tool *Tool) stateInfo {
	return stateInfo{state: StateUnmeasurable, reason: &code, text: code.Text(), tool: tool}
}

func lastPending(st *logState) *Tool {
	if st == nil {
		return nil
	}
	p, ok := st.pending.Last()
	if !ok {
		return nil
	}
	return &Tool{Name: p.name, Target: p.target}
}

func hasQuestions(st *logState) bool { return st != nil && len(st.questions) > 0 }

func toolText(tool *Tool) string {
	if tool != nil {
		return "A tool call is open."
	}
	return "Turn in progress."
}

// truthyNumber is a JSON number that is non-zero and inside the date range (a JavaScript `||` chain).
func truthyNumber(v jv) (float64, bool) {
	d, ok := v.number()
	if !ok {
		return 0, false
	}
	return truthy(d, true)
}

func truthy(d float64, ok bool) (float64, bool) {
	if !ok {
		return 0, false
	}
	bounded, ok := textjs.BoundedTimestamp(d)
	if !ok || bounded == 0 {
		return 0, false
	}
	return bounded, true
}

func truthyPtr(p *float64) (float64, bool) {
	if p == nil {
		return 0, false
	}
	return truthy(*p, true)
}

func isCompressedLog(path string) bool {
	return filepath.Ext(path) == ".zst" || filepath.Ext(path) == ".zstd"
}
