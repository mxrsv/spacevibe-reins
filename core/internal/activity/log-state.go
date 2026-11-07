package activity

import "spacevibe.dev/core/internal/textjs"

type failureEvent struct {
	id     string
	key    string
	cmd    string
	at     float64
	exit   int
	reason string
}

type hookEvent struct {
	id      string
	event   string
	command string
	at      float64
	exit    *int
	reason  string
}

type editEvent struct {
	id   string
	path string
	at   float64
}

type pendingCall struct {
	name   string
	target string
	at     float64
	track  bool
}

type pendingEdit struct {
	paths []string
	at    float64
}

type codexTokens struct{ input, output, cacheRead float64 }

// logState is the folded state of one session log. A pointer on purpose: logs reach hundreds of MB.
type logState struct {
	cli              CLI
	invalid          int
	cwd              string
	cwdSet           bool
	startedAt        float64
	startedAtSet     bool
	parent           bool
	worktreeOriginal string
	customTitle      string
	aiTitle          string
	firstPrompt      string
	model            string
	metrics          textjs.OrderedMap[usage]
	claudeUsageSeen  map[string]usage
	codexTotalsSeen  map[string]bool
	cumulative       *codexTokens
	// status is Codex only: "busy" after task_started, "idle" after task_complete or turn_aborted.
	status        string
	pending       textjs.OrderedMap[pendingCall]
	questions     map[string]bool
	bash          map[string]string
	editsPending  map[string]pendingEdit
	failures      []failureEvent
	hookFailures  []hookEvent
	passes        map[string][]float64
	edits         []editEvent
	legacyEdits   []editEvent
	sawFileChange bool
}

func newLogState(cli CLI) *logState {
	return &logState{
		cli: cli, model: "unknown", claudeUsageSeen: map[string]usage{}, codexTotalsSeen: map[string]bool{},
		questions: map[string]bool{}, bash: map[string]string{}, editsPending: map[string]pendingEdit{}, passes: map[string][]float64{},
	}
}

func (st *logState) clearQuestions() { clear(st.questions) }
