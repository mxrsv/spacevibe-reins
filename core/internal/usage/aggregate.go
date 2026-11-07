package usage

import (
	"slices"
	"sort"
)

// aggregate folds the per-file records into totals, session counts and the log window of each CLI. Files
// are visited in path order, so the float sum of hook durations does not depend on map order.
func aggregate(files map[string]cachedFile, fileCount int) Result {
	type names struct{ sessions, days map[string]struct{} }
	type bucket struct {
		skill, agent map[string]*names
		hook         map[string]HookTotals
	}
	newBucket := func() *bucket {
		return &bucket{skill: map[string]*names{}, agent: map[string]*names{}, hook: map[string]HookTotals{}}
	}
	buckets := map[CLI]*bucket{Claude: newBucket(), Codex: newBucket()}
	sessions := map[CLI]map[string]struct{}{Claude: {}, Codex: {}}
	windows := map[CLI]*LogWindow{Claude: {}, Codex: {}}

	paths := make([]string, 0, len(files))
	for path := range files {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	fold := func(group map[string]*names, rec map[string][]string, session string) {
		for name, days := range rec {
			n := group[name]
			if n == nil {
				n = &names{sessions: map[string]struct{}{}, days: map[string]struct{}{}}
				group[name] = n
			}
			n.sessions[session] = struct{}{}
			for _, d := range days {
				n.days[d] = struct{}{}
			}
		}
	}
	for _, path := range paths {
		file := files[path]
		cli := file.CLI
		if buckets[cli] == nil { // a cache entry of an unknown CLI never gets here: load refuses it
			continue
		}
		sessions[cli][file.Session] = struct{}{}
		window := windows[cli]
		window.Files++
		if file.First != nil && (window.Oldest == nil || *file.First < *window.Oldest) {
			first := *file.First
			window.Oldest = &first
		}
		if mtime := file.mtimeMs(); window.Newest == nil || mtime > *window.Newest {
			window.Newest = &mtime
		}
		b := buckets[cli]
		fold(b.skill, file.Rec.Skill, file.Session)
		fold(b.agent, file.Rec.Agent, file.Session)
		for key, h := range file.Rec.Hook {
			u := b.hook[key]
			u.Runs += h.Runs
			u.Ms += h.Ms
			u.Timed += h.Timed
			u.Errors += h.Errors
			if h.Last != nil && (u.Last == nil || *h.Last > *u.Last) {
				last := *h.Last
				u.Last = &last
			}
			b.hook[key] = u
		}
	}

	totals := func(cli CLI) CLITotals {
		out := emptyTotals()
		toUsage := func(source map[string]*names, into map[string]NameUsage) {
			for name, n := range source {
				days := make([]string, 0, len(n.days))
				for d := range n.days {
					days = append(days, d)
				}
				slices.Sort(days)
				u := NameUsage{Sessions: len(n.sessions), Days: days}
				if len(days) > 0 {
					last := days[len(days)-1]
					u.Last = &last
				}
				into[name] = u
			}
		}
		b := buckets[cli]
		toUsage(b.skill, out.Skill)
		toUsage(b.agent, out.Agent)
		for key, h := range b.hook {
			out.Hook[key] = h
		}
		return out
	}
	return Result{
		Totals:   Totals{Claude: totals(Claude), Codex: totals(Codex)},
		Sessions: Sessions{Claude: len(sessions[Claude]), Codex: len(sessions[Codex])},
		Windows:  Windows{Claude: *windows[Claude], Codex: *windows[Codex]},
		Files:    fileCount,
	}
}
