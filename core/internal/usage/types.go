// Package usage counts real usage of skills, subagents and hooks from the session logs (Claude
// projects/**.jsonl, Codex sessions/**.jsonl and .jsonl.zst). Logs are only read; the one file written is
// the scan cache under the data folder. Per-file results are cached by size and mtime and stamped with
// ScanVersion; the cache format is shared with the Swift engine while both exist.
//
// Ported from Sources/ReinsCore/UsageScanner.swift, UsageScanTypes.swift, UsageScanLines.swift,
// UsageScanAggregate.swift and UsageScanCache.swift. The package sits below internal/inventory (which
// attaches the result to its rows). Which CLIs are scanned comes from the registry (clis.Usage); each one's log
// lines are read by its parser (adapters.go).
package usage

import (
	"fmt"

	"spacevibe.dev/core/internal/clis"
)

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
	CLI   clis.ID               `json:"cli"`
	Skill map[string]NameUsage  `json:"skill"`
	Agent map[string]NameUsage  `json:"agent"`
	Hook  map[string]HookTotals `json:"hook"`
}

// CLIID is the CLI the totals belong to.
func (t CLITotals) CLIID() clis.ID { return t.CLI }

func emptyTotals(cli clis.ID) CLITotals {
	return CLITotals{CLI: cli, Skill: map[string]NameUsage{}, Agent: map[string]NameUsage{}, Hook: map[string]HookTotals{}}
}

// Totals holds the totals of every CLI the scan reads, one element per CLI in wire order.
type Totals []CLITotals

// For is the totals of one CLI; see errNotScanned for a CLI the result holds none of.
func (t Totals) For(cli clis.ID) (CLITotals, error) {
	if e, ok := clis.Find(t, cli); ok {
		return e, nil
	}
	return CLITotals{}, errNotScanned(cli)
}

// LogWindow is the span of logs scanned for one CLI. Oldest is the first timestamp's day; Newest is the
// newest log's mtime in ms since 1970.
type LogWindow struct {
	CLI    clis.ID `json:"cli"`
	Files  int     `json:"files"`
	Oldest *string `json:"oldest"`
	Newest *int64  `json:"newest"`
}

// CLIID is the CLI the window belongs to.
func (w LogWindow) CLIID() clis.ID { return w.CLI }

// Windows holds the log window of every CLI the scan reads, one element per CLI in wire order.
type Windows []LogWindow

// For is the window of one CLI; see errNotScanned for a CLI the result holds none of.
func (w Windows) For(cli clis.ID) (LogWindow, error) {
	if e, ok := clis.Find(w, cli); ok {
		return e, nil
	}
	return LogWindow{}, errNotScanned(cli)
}

// SessionCount is the number of distinct sessions of one CLI.
type SessionCount struct {
	CLI   clis.ID `json:"cli"`
	Count int     `json:"count"`
}

// CLIID is the CLI the count belongs to.
func (s SessionCount) CLIID() clis.ID { return s.CLI }

// Sessions counts the distinct sessions of every CLI the scan reads, one element per CLI in wire order.
type Sessions []SessionCount

// errNotScanned is why a result holds nothing for cli: an error wrapping clis.ErrUnknownCLI for an id with no entry,
// clis.ErrConceptAbsent for a CLI whose logs the scan does not read, and a plain error for a result that was built
// without it. It is never another CLI's value.
func errNotScanned(cli clis.ID) error {
	if _, err := parsers.For(cli); err != nil {
		return err
	}
	return fmt.Errorf("usage: the result holds no entry for %s", cli)
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
