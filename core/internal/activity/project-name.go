package activity

import (
	"os"
	"path/filepath"
	"unicode/utf8"

	"spacevibe.dev/core/internal/textjs"
)

// projectMemo caches projectName answers within one read.
type projectMemo map[string]string

// worktreeRepo is the main repo name when cwd (or a parent) is a linked worktree, whose `.git` is a pointer file.
// A `.git` directory means a normal checkout: false, so the caller keeps the folder name.
func worktreeRepo(cwd string) (string, bool) {
	dir := cwd
	for range 12 {
		git := filepath.Join(dir, ".git")
		if info, err := os.Stat(git); err == nil {
			if info.IsDir() {
				return "", false
			}
			gitdir := ""
			if text, ok := readSmallText(git); ok {
				if p, found := gitdirPath(text); found {
					gitdir = textjs.Trim(p)
				}
			}
			main := ""
			if gitdir != "" {
				absolute := gitdir
				if !filepath.IsAbs(gitdir) {
					absolute = filepath.Join(dir, gitdir)
				}
				main, _ = gitdirWorktreeMain(absolute)
			}
			if main != "" {
				return textjs.Basename(main), true
			}
			return textjs.Basename(dir), true
		}
		up := textjs.Dirname(dir)
		if up == dir {
			return "", false
		}
		dir = up
	}
	return "", false
}

// readSmallText reads a regular file as UTF-8 text; a FIFO, a device or invalid UTF-8 is not text (Swift's
// String(contentsOfFile:encoding:) gave nil for invalid UTF-8).
func readSmallText(path string) (string, bool) {
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() {
		return "", false
	}
	data, err := os.ReadFile(path)
	if err != nil || !utf8.Valid(data) {
		return "", false
	}
	return string(data), true
}

// projectName is the repo name for a working directory; a git worktree slug is never returned. Order: hint (the
// original cwd Claude records for a worktree), the `.claude/worktrees/<slug>` and `.codex/worktrees/<id>/<repo>`
// layouts, the `.git` pointer file on disk, then the folder name. The result is false for an empty cwd.
func projectName(cwd, hint string, memo projectMemo) (string, bool) {
	if cwd == "" {
		return "", false
	}
	key := cwd + "\x00" + hint
	if cached, ok := memo[key]; ok {
		return cached, true
	}
	var name string
	found := false
	if hint != "" {
		name, found = projectName(hint, "", memo)
	}
	if !found {
		if claude, ok := worktreeClaudeRepo(cwd); ok && claude != "" {
			name, found = textjs.Basename(claude), true
		} else if codex, ok := worktreeCodexRepo(cwd); ok {
			name, found = codex, true
		}
	}
	if !found {
		name, found = worktreeRepo(cwd)
	}
	if !found {
		name = textjs.Basename(cwd)
		if name == "" {
			name = cwd
		}
	}
	if memo != nil {
		memo[key] = name
	}
	return name, true
}

// ProjectName is the repo name for a working directory, for callers outside a read.
func ProjectName(cwd, hint string) (string, bool) { return projectName(cwd, hint, nil) }
