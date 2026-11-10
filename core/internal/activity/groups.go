package activity

import (
	"math"
	"sort"
	"strings"

	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/redact"
	"spacevibe.dev/core/internal/textjs"
)

// ActivityGroups.swift: turns per-log states into the two cross-session lists of the Activity tab.

const failureTitleMax = 120

// logEntry is one folded log with the session name and project it belongs to.
type logEntry struct {
	state      *logState
	session    string
	project    string
	hasProject bool
}

// isoOrNil is the ISO text of a positive finite timestamp.
func isoOrNil(ms float64) *string {
	if math.IsInf(ms, 0) || math.IsNaN(ms) || ms <= 0 {
		return nil
	}
	s := textjs.IsoString(ms)
	return &s
}

// failureTitle is the command as shown: credentials masked first, so a cut cannot leave half of one. The failure key
// and the hook hash are made from the raw command and never from this text.
func failureTitle(cmd string) string {
	cmd = redact.Command(cmd)
	if textjs.UTF16Length(cmd) > failureTitleMax {
		return textjs.Prefix(cmd, failureTitleMax-1) + "…"
	}
	return cmd
}

type failureGroup struct {
	kind     FailureKind
	cli      CLI
	key      string
	title    string
	hook     *HookRef
	count    int
	exit     *int
	reason   string
	projects map[string]bool
	sessions map[string]bool
	firstAt  float64
	lastAt   float64
}

// groupFailures groups failures by CLI plus command (hooks by CLI plus hook hash).
func groupFailures(logs []logEntry, limit int) []Failure {
	var order []string
	groups := map[string]*failureGroup{}
	seen := map[string]bool{}
	add := func(cli CLI, gkey string, base failureGroup, id string, at float64, exit *int, reason, session string, project string, hasProject bool) {
		dedupe := string(cli) + "|" + id
		if seen[dedupe] {
			return // forked or resumed logs repeat earlier events
		}
		seen[dedupe] = true
		g, ok := groups[gkey]
		if !ok {
			base.projects, base.sessions, base.firstAt = map[string]bool{}, map[string]bool{}, math.Inf(1)
			g = &base
			groups[gkey] = g
			order = append(order, gkey)
		}
		g.count++
		g.sessions[session] = true
		if hasProject {
			g.projects[project] = true
		}
		g.firstAt = math.Min(g.firstAt, at)
		if at >= g.lastAt {
			g.lastAt, g.exit, g.reason = at, exit, reason
		}
	}
	for _, entry := range logs {
		st := entry.state
		for _, f := range st.failures {
			exit := f.exit
			add(st.cli, string(st.cli)+"|cmd|"+f.key, failureGroup{kind: KindCommand, cli: st.cli, key: f.key, title: failureTitle(f.cmd)},
				f.id, f.at, &exit, f.reason, entry.session, entry.project, entry.hasProject)
		}
		for _, h := range st.hookFailures {
			hash := hashes.HookHash(h.event, h.command)
			add(st.cli, string(st.cli)+"|hook|"+hash, failureGroup{kind: KindHook, cli: st.cli, key: hash, title: failureTitle(h.command), hook: &HookRef{Hash: hash, Event: h.event}},
				h.id, h.at, h.exit, h.reason, entry.session, entry.project, entry.hasProject)
		}
	}
	passes := map[string][]float64{}
	for _, entry := range logs {
		for key, list := range entry.state.passes {
			k := string(entry.state.cli) + "|cmd|" + key
			if groups[k] != nil {
				passes[k] = append(passes[k], list...)
			}
		}
	}
	rows := make([]Failure, 0, len(order))
	for _, gkey := range order {
		g := groups[gkey]
		var later *float64
		for _, p := range passes[gkey] {
			if p > g.lastAt && (later == nil || p < *later) {
				p := p
				later = &p
			}
		}
		var laterPass *string
		if later != nil {
			laterPass = isoOrNil(*later)
		}
		rows = append(rows, Failure{
			Kind: g.kind, CLI: g.cli, Key: g.key, Title: g.title, Count: g.count, Exit: g.exit, Reason: redact.Command(g.reason),
			Projects: sortedKeys(g.projects), Sessions: len(g.sessions),
			First: isoOrNil(g.firstAt), Last: isoOrNil(g.lastAt), LaterPass: laterPass, Hook: g.hook,
		})
	}
	// Newest first, then most repeated; ties keep the order the groups were first seen (a stable sort).
	sort.SliceStable(rows, func(i, j int) bool {
		li, lj := derefOrEmpty(rows[i].Last), derefOrEmpty(rows[j].Last)
		if li != lj {
			return li > lj
		}
		return rows[i].Count > rows[j].Count
	})
	if len(rows) > limit {
		rows = rows[:limit]
	}
	return rows
}

func derefOrEmpty(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func sortedKeys(set map[string]bool) []string {
	keys := make([]string, 0, len(set))
	for k := range set {
		keys = append(keys, k)
	}
	sorted := textjs.SortedStrings(keys)
	if sorted == nil {
		return []string{}
	}
	return sorted
}

// shortestLabels gives each path the shortest suffix that no other path in the list shares. A path with no unique
// suffix keeps its whole text.
func shortestLabels(paths []string) []string {
	segments := make([][]string, len(paths))
	for i, p := range paths {
		segments[i] = strings.FieldsFunc(p, func(r rune) bool { return r == '/' || r == '\\' })
	}
	suffix := func(parts []string, k int) string { return strings.Join(parts[len(parts)-k:], "/") }
	counts := map[int]map[string]int{}
	countsFor := func(k int) map[string]int {
		if m, ok := counts[k]; ok {
			return m
		}
		m := map[string]int{}
		for _, parts := range segments {
			if len(parts) >= k {
				m[suffix(parts, k)]++
			}
		}
		counts[k] = m
		return m
	}
	labels := make([]string, len(paths))
	for i, parts := range segments {
		labels[i] = paths[i]
		for k := 1; k <= len(parts); k++ {
			if countsFor(k)[suffix(parts, k)] == 1 {
				labels[i] = suffix(parts, k)
				break
			}
		}
	}
	return labels
}

type fileGroup struct {
	path     string
	edits    int
	sessions map[string]bool
	clis     map[string]bool
	projects map[string]bool
	lastAt   float64
}

// groupFiles is the file history across logs; Label is the shortest suffix that still tells two files apart.
func groupFiles(logs []logEntry, limit int) []FileRow {
	var order []string
	files := map[string]*fileGroup{}
	seen := map[string]bool{}
	for _, entry := range logs {
		for _, e := range editsOf(entry.state) {
			if seen[e.id] {
				continue
			}
			seen[e.id] = true
			f, ok := files[e.path]
			if !ok {
				f = &fileGroup{path: e.path, sessions: map[string]bool{}, clis: map[string]bool{}, projects: map[string]bool{}}
				files[e.path] = f
				order = append(order, e.path)
			}
			f.edits++
			f.sessions[entry.session] = true
			f.clis[string(entry.state.cli)] = true
			if entry.hasProject {
				f.projects[entry.project] = true
			}
			f.lastAt = math.Max(f.lastAt, e.at)
		}
	}
	ordered := make([]*fileGroup, len(order))
	for i, path := range order {
		ordered[i] = files[path]
	}
	sort.SliceStable(ordered, func(i, j int) bool { return ordered[i].lastAt > ordered[j].lastAt })
	if len(ordered) > limit {
		ordered = ordered[:limit]
	}
	paths := make([]string, len(ordered))
	for i, f := range ordered {
		paths[i] = f.path
	}
	labels := shortestLabels(paths)
	rows := make([]FileRow, len(ordered))
	for i, f := range ordered {
		clis := []CLI{}
		for _, name := range textjs.SortedStrings(keysOf(f.clis)) {
			if name == string(CLIClaude) || name == string(CLICodex) {
				clis = append(clis, CLI(name))
			}
		}
		rows[i] = FileRow{Path: f.path, Label: labels[i], Edits: f.edits, Sessions: len(f.sessions), Last: isoOrNil(f.lastAt), CLIs: clis, Projects: sortedKeys(f.projects)}
	}
	return rows
}

func keysOf(set map[string]bool) []string {
	keys := make([]string, 0, len(set))
	for k := range set {
		keys = append(keys, k)
	}
	return keys
}
