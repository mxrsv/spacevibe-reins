package mutate

import (
	"path/filepath"
	"strings"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// G-fix.3: journal.json is a file a user, a sync tool or another program can edit, and Undo moves, writes and
// removes the paths it names. Before an undo changes anything, every path of the entry is checked:
//
//   - file, path and from must be inside a folder Reins manages: the Claude Code or Codex folder, the data folder, or
//     the .claude folder of a project that discovery found (rules edit a project's settings.json). A file-edited
//     file may also be the real file a configuration link points at (a dotfiles setup: the journal records the target).
//   - backup and to must be inside <data>/trash.
//   - a path with a ".." segment, or a relative path, is refused.
//
// The check is lexical or by real path, whichever matches: a skills folder that is a link into a dotfiles folder is
// still reached through its CLI folder. It is applied to entries read from the journal only; the in-memory rollback of
// a change that is failing right now needs no such check. Limit: a link planted inside a managed folder is not
// resolved again for the final component.

// containment answers "may Undo touch this path?" for one roots value. Project discovery is read once, on first need.
type containment struct {
	r        roots.Roots
	managed  []string // folders, lexical and real spelling
	trash    []string
	configs  []string // real paths of the known configuration files
	projects []string
	loaded   bool
}

func newContainment(r roots.Roots) *containment {
	c := &containment{r: r}
	for _, p := range []string{r.Claude.Root, r.Codex.Root, r.Data} {
		c.managed = append(c.managed, spellings(p)...)
	}
	c.trash = spellings(trashDir(r))
	for _, p := range []string{r.Claude.HookFile, r.Codex.HookFile, filepath.Join(r.Codex.Root, "config.toml")} {
		c.configs = append(c.configs, roots.ResolvedPath(p))
	}
	return c
}

// spellings is the folder as given and with every link followed.
func spellings(p string) []string {
	out := []string{filepath.Clean(p)}
	if real := roots.ResolvedPath(p); real != out[0] {
		out = append(out, real)
	}
	return out
}

// absoluteClean is the cleaned path, or false for a relative path or one with a ".." segment.
func absoluteClean(p string) (string, bool) {
	if p == "" || !filepath.IsAbs(p) {
		return "", false
	}
	for _, seg := range strings.FieldsFunc(p, func(r rune) bool { return r == '/' || r == filepath.Separator }) {
		if seg == ".." {
			return "", false
		}
	}
	return filepath.Clean(p), true
}

// inside is true when p is strictly below one of the folders.
func inside(folders []string, p string) bool {
	for _, f := range folders {
		rel, err := filepath.Rel(f, p)
		if err == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return true
		}
	}
	return false
}

func (c *containment) insideManaged(clean string) bool {
	if inside(c.managed, clean) || inside(c.managed, roots.ResolvedPath(clean)) {
		return true
	}
	if !c.loaded {
		c.loaded = true
		for _, project := range inventory.DiscoverProjects(c.r) {
			c.projects = append(c.projects, spellings(filepath.Join(project, ".claude"))...)
		}
	}
	return inside(c.projects, clean) || inside(c.projects, roots.ResolvedPath(clean))
}

// managedPath is the rule for file, path and from.
func (c *containment) managedPath(p string) bool {
	clean, ok := absoluteClean(p)
	return ok && c.insideManaged(clean)
}

// configFile is the rule for the file of an edit.
func (c *containment) configFile(p string) bool {
	clean, ok := absoluteClean(p)
	if !ok {
		return false
	}
	if c.insideManaged(clean) {
		return true
	}
	real := roots.ResolvedPath(clean)
	for _, known := range c.configs {
		if real == known {
			return true
		}
	}
	return false
}

// trashPath is the rule for backup and to.
func (c *containment) trashPath(p string) bool {
	clean, ok := absoluteClean(p)
	return ok && (inside(c.trash, clean) || inside(c.trash, roots.ResolvedPath(clean)))
}

// checkOp is nil when every path the op names is allowed. A field the op does not have is left to the undo itself,
// which refuses it as an unknown entry.
func (c *containment) checkOp(op Op) error {
	bad := func() error { return fail(outsideManagedMessage, coreerr.StatusBadRequest) }
	check := func(key string, ok func(string) bool) error {
		if s, has := op.str(key); has && !ok(s) {
			return bad()
		}
		return nil
	}
	switch op.Type() {
	case "file-edited":
		if err := check("file", c.configFile); err != nil {
			return err
		}
		return check("backup", c.trashPath)
	case "created", "link-removed":
		return check("path", c.managedPath)
	case "moved":
		if err := check("from", c.managedPath); err != nil {
			return err
		}
		return check("to", c.trashPath)
	case "hook-added", "hook-removed":
		if err := check("file", c.configFile); err != nil {
			return err
		}
		if restore, ok := op.JSON.Member("restore"); ok && restore.Kind() == ojson.KindObject {
			return c.checkOp(Op{restore})
		}
	}
	return nil
}
