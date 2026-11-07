// Package usage counts real usage of skills, subagents and hooks from the session logs (Claude
// projects/**.jsonl, Codex sessions/**.jsonl and .jsonl.zst). Logs are only read; the one file written is
// the scan cache under the data folder. Per-file results are cached by size and mtime and stamped with
// ScanVersion; the cache format is shared with the Swift engine while both exist.
//
// Ported from Sources/ReinsCore/UsageScanner.swift, UsageScanTypes.swift, UsageScanLines.swift,
// UsageScanAggregate.swift and UsageScanCache.swift. The package sits below internal/inventory (which
// attaches the result to its rows), so it names the two CLIs itself.
package usage

// CLI is one of the two CLIs whose logs are read. The wire value is "claude" or "codex".
type CLI string

// The CLIs.
const (
	Claude CLI = "claude"
	Codex  CLI = "codex"
)

// CLIs lists both CLIs in wire order.
var CLIs = [...]CLI{Claude, Codex}

// Other is the other CLI.
func (c CLI) Other() CLI {
	if c == Claude {
		return Codex
	}
	return Claude
}

// NameUsage is what the logs say about one skill or agent name: in how many sessions it was used, and on
// which days (YYYY-MM-DD, sorted).
type NameUsage struct {
	Sessions int      `json:"sessions"`
	Days     []string `json:"days"`
	Last     *string  `json:"last"`
}

// HookTotals are the totals of one hook, keyed by hashes.HookHash. Ms is the sum of the durations that
// were recorded; Timed counts the runs that had one.
type HookTotals struct {
	Runs   int     `json:"runs"`
	Ms     float64 `json:"ms"`
	Timed  int     `json:"timed"`
	Errors int     `json:"errors"`
	Last   *string `json:"last"`
}

// CLITotals are the totals of one CLI. Skill and Agent are keyed by the bare name; Hook by the hook hash.
// The maps are never nil.
type CLITotals struct {
	Skill map[string]NameUsage  `json:"skill"`
	Agent map[string]NameUsage  `json:"agent"`
	Hook  map[string]HookTotals `json:"hook"`
}

func emptyTotals() CLITotals {
	return CLITotals{Skill: map[string]NameUsage{}, Agent: map[string]NameUsage{}, Hook: map[string]HookTotals{}}
}

// Totals holds the totals of both CLIs.
type Totals struct {
	Claude CLITotals `json:"claude"`
	Codex  CLITotals `json:"codex"`
}

// For returns the totals of one CLI.
func (t Totals) For(cli CLI) CLITotals {
	if cli == Claude {
		return t.Claude
	}
	return t.Codex
}

// LogWindow is the span of logs scanned for one CLI. Oldest is the first timestamp's day; Newest is the
// newest log's mtime in ms since 1970.
type LogWindow struct {
	Files  int     `json:"files"`
	Oldest *string `json:"oldest"`
	Newest *int64  `json:"newest"`
}

// Windows holds the log window of both CLIs.
type Windows struct {
	Claude LogWindow `json:"claude"`
	Codex  LogWindow `json:"codex"`
}

// For returns the window of one CLI.
func (w Windows) For(cli CLI) LogWindow {
	if cli == Claude {
		return w.Claude
	}
	return w.Codex
}

// Sessions counts the distinct sessions per CLI.
type Sessions struct {
	Claude int `json:"claude"`
	Codex  int `json:"codex"`
}

// Result is the result of one scan: the shape scan() returns in Node usage.
type Result struct {
	Totals   Totals   `json:"totals"`
	Sessions Sessions `json:"sessions"`
	Windows  Windows  `json:"windows"`
	// Files counts the log files found, including any that could not be read.
	Files int `json:"files"`
}

// Input is the usage state inventory.AttachUsage reads. State is "ready" once Totals and Windows exist.
// While scanning they are nil and every zero-run cell shows pending.
type Input struct {
	State   string   `json:"state"`
	Totals  *Totals  `json:"totals"`
	Windows *Windows `json:"windows"`
}

// Scanning is the state before the first scan of the process has finished.
var Scanning = Input{State: "scanning"}

// Ready is the state after a scan.
func Ready(r Result) Input {
	totals, windows := r.Totals, r.Windows
	return Input{State: "ready", Totals: &totals, Windows: &windows}
}

// Progress is the progress of a running scan. It is passed to the callback of Scan; the usage/progress
// notification adds the request id.
type Progress struct {
	Done  int `json:"done"`
	Total int `json:"total"`
}
