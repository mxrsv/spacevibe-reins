package inventory

import (
	"cmp"
	"context"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
	"spacevibe.dev/core/internal/toml"
)

// Project discovery. Claude Code keeps no list of projects, so SpaceVibe looks where a path is already recorded:
//   - the cwd in the head of the newest session logs of each folder under claude/projects (the folder name is a
//     lossy encoding of the path and cannot be decoded), and
//   - the [projects."<path>"] tables of Codex config.toml.
//
// A path counts only if it still exists (or cannot be checked: then it is listed and reported as not readable)
// and has a .claude folder of its own. The home folder is skipped (its .claude is the global one), and so are
// paths inside .claude/worktrees/ (copies of a project already listed). Bounded: at most 3 log files per
// folder, 64 KB each, at most MaxProjects folders, newest first. Trade-off: a project never opened with either
// CLI is not found, and one whose first records fall outside the first 64 KB of its 3 newest logs is missed.
const (
	projectHeadBytes     = 64 * 1024
	projectLogsPerFolder = 3
)

// lineBreak is ICU's line terminators, which its "." does not match: \n, \v, \f, \r, U+0085, U+2028, U+2029.
const lineBreak = `\n\x0B\x0C\r\x{85}\x{2028}\x{2029}`

var cwdPattern = regexp.MustCompile(`"cwd":"((?:[^"\\]|\\[^` + lineBreak + `])*)"`)

// DiscoverProjects lists the absolute paths of the projects that have their own .claude folder.
func DiscoverProjects(r roots.Roots) []string { return discoverProjects(context.Background(), r) }

// discoverProjects is DiscoverProjects that stops early when the context ends; the caller checks the
// context afterwards, so a partial list is never used.
func discoverProjects(ctx context.Context, r roots.Roots) []string {
	globalClaude := realPath(r.Claude.Root)
	seen := []string{}
	known := map[string]struct{}{}
	candidates := append(logCwds(ctx, r.Claude.Logs), codexProjectKeys(filepath.Join(r.Codex.Root, "config.toml"))...)
	for _, path := range candidates {
		if ctx.Err() != nil {
			return seen
		}
		if !strings.HasPrefix(path, "/") || strings.Contains(path, "/.claude/worktrees/") {
			continue
		}
		dir := join(path, ".claude")
		// A .claude that cannot be looked up (a denied parent) is kept: Read reports the project as not readable.
		there := isDirectory(dir) || pathPresence(dir) == unknown
		if !there || realPath(dir) == globalClaude {
			continue
		}
		resolved := normalize(path)
		if _, dup := known[resolved]; !dup {
			known[resolved] = struct{}{}
			seen = append(seen, resolved)
		}
		if len(seen) >= MaxProjects {
			break
		}
	}
	return seen
}

func logCwds(ctx context.Context, logsDir string) []string {
	type found struct {
		path, folder string
		mtime        float64
	}
	var all []found
	for _, folder := range listDir(logsDir) {
		if ctx.Err() != nil {
			return nil
		}
		base := join(logsDir, folder)
		type logFile struct {
			name  string
			mtime float64
		}
		var logs []logFile
		for _, name := range listDir(base) {
			if !strings.HasSuffix(name, ".jsonl") {
				continue
			}
			if m, ok := modifiedMs(join(base, name)); ok {
				logs = append(logs, logFile{name, m})
			}
		}
		slices.SortFunc(logs, func(a, b logFile) int {
			if a.mtime != b.mtime {
				return cmp.Compare(b.mtime, a.mtime)
			}
			return strings.Compare(a.name, b.name)
		})
		if len(logs) > projectLogsPerFolder {
			logs = logs[:projectLogsPerFolder]
		}
		for _, log := range logs {
			cwd, matched, valid := cwdInHead(join(base, log.name))
			if !matched {
				continue
			}
			if valid {
				all = append(all, found{cwd, folder, log.mtime})
			}
			break
		}
	}
	slices.SortFunc(all, func(a, b found) int {
		if a.mtime != b.mtime {
			return cmp.Compare(b.mtime, a.mtime)
		}
		return strings.Compare(a.folder, b.folder)
	})
	if len(all) > MaxProjects {
		all = all[:MaxProjects]
	}
	out := make([]string, len(all))
	for i, f := range all {
		out[i] = f.path
	}
	return out
}

// cwdInHead looks for a "cwd" in the head of a log. matched is false when there is none; valid is false when
// the match is not a valid JSON string.
func cwdInHead(path string) (cwd string, matched, valid bool) {
	data, _ := readData(path, projectHeadBytes)
	m := cwdPattern.FindStringSubmatch(textjs.Repair(string(data)))
	if m == nil {
		return "", false, false
	}
	doc, err := ojson.ParseString(`"` + m[1] + `"`)
	if err != nil {
		return "", true, false
	}
	s, ok := doc.Root().StringValue()
	return s, true, ok
}

func codexProjectKeys(configFile string) []string {
	data, ok := readData(configFile, maxTextBytes)
	if !ok {
		return nil
	}
	doc := toml.Read(textjs.Repair(string(data)))
	var out []string
	for _, p := range doc.TablePaths([]string{"projects"}) {
		if len(p) >= 2 {
			out = append(out, p[1])
		}
	}
	return out
}
