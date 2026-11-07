package mutate

import (
	"context"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
	"spacevibe.dev/core/internal/usage"
)

// Every Loadout write: add, remove and copy skills, agents and hooks (Mutate.swift, MutateItems.swift). Port of the
// item half of Node mutate (git b58269d).
//
// Each call records one journal entry so Undo can reverse it. Removed files go to the app trash, never away for good;
// a removed link keeps its target text. Items are found again by inventory.Read, so an id that no longer exists is a
// 404. Nothing here runs a hook or a command: hook commands are only copied as text.

const (
	nameLimit = 64
	// maxAgentBytes is the largest agent file a copy reads (G-fix.5).
	maxAgentBytes = 1 << 20

	msgRefreshList = "This item no longer exists. Refresh the list."
)

var cliLabels = map[usage.CLI]string{inventory.Claude: "Claude Code", inventory.Codex: "Codex"}

func label(cli usage.CLI) string {
	if l, ok := cliLabels[cli]; ok {
		return l
	}
	return string(cli)
}

func labels(clis []usage.CLI) string {
	parts := make([]string, len(clis))
	for i, cli := range clis {
		parts[i] = label(cli)
	}
	return strings.Join(parts, " and ")
}

func events(cli usage.CLI) []string { return inventory.Events()[string(cli)] }

func (tx *Tx) cliRoots(cli usage.CLI) roots.CLIRoots {
	if cli == inventory.Claude {
		return tx.r.Claude
	}
	return tx.r.Codex
}

func itoa(n int) string { return strconv.Itoa(n) }

// dedupe drops a repeated CLI, keeping the first of each: a list like [claude, claude] would otherwise create the same
// path twice and word the label wrong (G-fix.7).
func dedupe(clis []usage.CLI) []usage.CLI {
	out := make([]usage.CLI, 0, len(clis))
	for _, cli := range clis {
		if !slices.Contains(out, cli) {
			out = append(out, cli)
		}
	}
	return out
}

func requireCLIs(clis []usage.CLI) error { return need(len(clis) > 0, "Pick at least one CLI.") }

// validName is NAME_RE of the Node core: ^[a-z0-9][a-z0-9-]{0,63}$.
func validName(name string) error {
	runes := []rune(name)
	valid := len(runes) >= 1 && len(runes) <= nameLimit
	for i, r := range runes {
		if !(r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || i > 0 && r == '-') {
			valid = false
		}
	}
	return need(valid, "Use lowercase letters, numbers and dashes for the name.")
}

type found struct {
	item *inventory.Item
	hook *inventory.Hook
}

// find looks the id up in a fresh inventory read (ids are stable hashes of what the item is).
func (tx *Tx) find(id string) (found, error) {
	snapshot := inventory.Read(tx.r)
	for i := range snapshot.Items {
		if snapshot.Items[i].ID == id {
			return found{item: &snapshot.Items[i]}, nil
		}
	}
	for i := range snapshot.Hooks {
		if snapshot.Hooks[i].ID == id {
			return found{hook: &snapshot.Hooks[i]}, nil
		}
	}
	return found{}, fail(msgRefreshList, coreerr.StatusNotFound)
}

// requireRemovable: the Node core words every refusal as "belongs to a plugin"; a project item gets its own sentence
// (same 403).
func requireRemovable(removable bool, scope inventory.Scope) error {
	if removable {
		return nil
	}
	if scope == inventory.ScopeProject {
		return fail("This one belongs to a project folder, so SpaceVibe only shows it. Change it in the project.", coreerr.StatusForbidden)
	}
	return fail("This one belongs to a plugin. Remove the plugin instead.", coreerr.StatusForbidden)
}

// RemoveItem removes a skill, an agent or a hook. Plugin-owned and project-scoped items are read-only (403).
func RemoveItem(r roots.Roots, id string) (Entry, error) {
	return removeItem(context.Background(), r, id)
}

func removeItem(ctx context.Context, r roots.Roots, id string) (Entry, error) {
	return lockedContext(ctx, r, func(tx *Tx) (Entry, error) {
		f, err := tx.find(id)
		if err != nil {
			return Entry{}, err
		}
		if f.hook != nil {
			if err := requireRemovable(f.hook.Removable, f.hook.Scope); err != nil {
				return Entry{}, err
			}
			return tx.removeHook(*f.hook)
		}
		if err := requireRemovable(f.item.Removable, f.item.Scope); err != nil {
			return Entry{}, err
		}
		return tx.removeFile(*f.item)
	})
}

// CopyToOther copies a skill, an agent or a hook to the other CLI. A plugin or project item may be copied; only
// removal is refused. A hook is copied into Claude Code when it knows the event, never into Codex: Codex loading a hook
// SpaceVibe wrote is unverified (spec, "To verify"), and the approved Loadout mock offers no such copy. The Node core throws
// a TypeError for every hook copy, so there is nothing to mirror.
func CopyToOther(r roots.Roots, id string) (Entry, error) {
	return copyToOther(context.Background(), r, id)
}

func copyToOther(ctx context.Context, r roots.Roots, id string) (Entry, error) {
	return lockedContext(ctx, r, func(tx *Tx) (Entry, error) {
		f, err := tx.find(id)
		if err != nil {
			return Entry{}, err
		}
		if f.hook != nil {
			target := f.hook.CLI.Other()
			if err := need(target == inventory.Claude, "SpaceVibe does not copy hooks into Codex."); err != nil {
				return Entry{}, err
			}
			if err := need(slices.Contains(events(target), f.hook.Event), label(target)+" has no "+f.hook.Event+" event."); err != nil {
				return Entry{}, err
			}
			return tx.addHook([]usage.CLI{target}, f.hook.Event, f.hook.Matcher, f.hook.Command, f.hook.Timeout)
		}
		return tx.copyItem(*f.item)
	})
}

// AddSkill writes <skills>/<name>/SKILL.md in each CLI. It refuses a name that exists in any of them before writing
// anything. Go API only (see the package comment).
func AddSkill(r roots.Roots, clis []usage.CLI, name, description, body string) (Entry, error) {
	return locked(r, func(tx *Tx) (Entry, error) { return tx.addSkill(clis, name, description, body) })
}

func (tx *Tx) addSkill(clis []usage.CLI, name, description, body string) (Entry, error) {
	if err := tx.PrepareMutation(); err != nil {
		return Entry{}, err
	}
	if err := validName(name); err != nil {
		return Entry{}, err
	}
	if err := need(textjs.Trim(description) != "", "Say when the agent should use this skill."); err != nil {
		return Entry{}, err
	}
	if err := requireCLIs(clis); err != nil {
		return Entry{}, err
	}
	clis = dedupe(clis)
	text := skillText(name, description, body)
	ops, err := tx.createAll(clis, func(cli usage.CLI) (createPlan, error) {
		dir := filepath.Join(tx.cliRoots(cli).Skills, name)
		if err := need(!pathExists(dir), label(cli)+" already has a skill named "+name+".", coreerr.StatusConflict); err != nil {
			return createPlan{}, err
		}
		return createPlan{path: dir, write: func() (bool, error) { return writeSkill(dir, text) }}, nil
	})
	if err != nil {
		return Entry{}, err
	}
	return tx.RecordMutation("Added skill "+name+" to "+labels(clis), ops)
}

// AddAgent writes <agents>/<name>.md (Claude Code) or <name>.toml (Codex) in each CLI. Go API only.
func AddAgent(r roots.Roots, clis []usage.CLI, name, description, instructions string) (Entry, error) {
	return locked(r, func(tx *Tx) (Entry, error) { return tx.addAgent(clis, name, description, instructions) })
}

func (tx *Tx) addAgent(clis []usage.CLI, name, description, instructions string) (Entry, error) {
	if err := tx.PrepareMutation(); err != nil {
		return Entry{}, err
	}
	if err := validName(name); err != nil {
		return Entry{}, err
	}
	if err := need(textjs.Trim(description) != "", "Say when this agent should be used."); err != nil {
		return Entry{}, err
	}
	if err := requireCLIs(clis); err != nil {
		return Entry{}, err
	}
	clis = dedupe(clis)
	ops, err := tx.createAll(clis, func(cli usage.CLI) (createPlan, error) {
		return tx.agentPlan(cli, name, description, instructions, false)
	})
	if err != nil {
		return Entry{}, err
	}
	return tx.RecordMutation("Added agent "+name+" to "+labels(clis), ops)
}

func (tx *Tx) removeFile(item inventory.Item) (Entry, error) {
	if err := tx.PrepareMutation(); err != nil {
		return Entry{}, err
	}
	cli := tx.cliRoots(item.CLI)
	base := cli.Agents
	if item.Kind == inventory.KindSkill {
		base = cli.Skills
	}
	outside := fail("Refusing a path outside the CLI folder.", coreerr.StatusForbidden)
	if !strings.HasPrefix(normalize(item.Path), normalize(base)+"/") {
		return Entry{}, outside
	}
	// The check above is lexical. The item's parent must also be the CLI folder itself once links are followed, so a
	// link in the middle of the path cannot send the removal to some other folder. The CLI folder may be a link (a
	// dotfiles setup); the item itself may be one too, which is why only its parent is resolved.
	if roots.ResolvedPath(filepath.Dir(normalize(item.Path))) != roots.ResolvedPath(base) {
		return Entry{}, outside
	}
	op, err := removePath(tx.r, item.Path)
	if err != nil {
		return Entry{}, err
	}
	return tx.RecordMutation("Removed "+string(item.Kind)+" "+item.Name+" from "+label(item.CLI), []Op{op})
}

func (tx *Tx) copyItem(item inventory.Item) (Entry, error) {
	target := item.CLI.Other()
	name := hashes.Bare(item.Name)
	if err := tx.PrepareMutation(); err != nil {
		return Entry{}, err
	}
	if err := validName(name); err != nil {
		return Entry{}, err
	}
	if item.Kind == inventory.KindSkill {
		dir := filepath.Join(tx.cliRoots(target).Skills, name)
		if err := need(!pathExists(dir), label(target)+" already has a skill named "+name+".", coreerr.StatusConflict); err != nil {
			return Entry{}, err
		}
		source := realPath(item.Path)
		ops, err := tx.createAll([]usage.CLI{target}, func(usage.CLI) (createPlan, error) {
			tree, err := listSkillFolder(source)
			if err != nil {
				return createPlan{}, err
			}
			return createPlan{path: dir, write: func() (bool, error) { return tree.copyTo(dir) }}, nil
		})
		if err != nil {
			return Entry{}, err
		}
		return tx.RecordMutation("Copied skill "+name+" to "+label(target), ops)
	}
	data, err := readRegular(item.Path, maxAgentBytes)
	if err != nil {
		if err == errTooLarge {
			return Entry{}, fail("This agent file is larger than 1 MiB, so it was not copied. Nothing was changed.", coreerr.StatusTooLarge)
		}
		return Entry{}, fail("Could not read "+item.Path+". Nothing was changed.", coreerr.StatusConflict)
	}
	description, instructions := agentFields(strings.HasSuffix(item.Path, ".toml"), textjs.Repair(string(data)))
	ops, err := tx.createAll([]usage.CLI{target}, func(cli usage.CLI) (createPlan, error) {
		return tx.agentPlan(cli, name, description, instructions, true)
	})
	if err != nil {
		return Entry{}, err
	}
	return tx.RecordMutation("Copied agent "+name+" to "+label(target), ops)
}

// createPlan is one path a change creates and the write that creates it. write reports whether the path now exists
// because of this call (created), even when a later step of the write failed, so a rollback removes exactly what this
// change made and never a path somebody else made (G-fix.7).
type createPlan struct {
	path  string
	write func() (created bool, err error)
}

// agentPlan says where a new agent goes and how it is written. It is a 409 when the file exists. copying refuses an
// agent with no instructions: an empty developer_instructions is a Codex file Codex rejects (G-fix.17).
func (tx *Tx) agentPlan(cli usage.CLI, name, description, instructions string, copying bool) (createPlan, error) {
	ext := "toml"
	if cli == inventory.Claude {
		ext = "md"
	}
	file := filepath.Join(tx.cliRoots(cli).Agents, name+"."+ext)
	if err := need(!pathExists(file), label(cli)+" already has an agent named "+name+".", coreerr.StatusConflict); err != nil {
		return createPlan{}, err
	}
	if copying {
		if err := need(textjs.Trim(instructions) != "", "This agent has no instructions to copy, so nothing was copied.", coreerr.StatusConflict); err != nil {
			return createPlan{}, err
		}
	}
	text := agentText(cli, name, description, instructions)
	return createPlan{path: file, write: func() (bool, error) { return writeNewFile(file, text) }}, nil
}

// createAll runs plan for each CLI (every check before the first write), then the writes. A failed write sends what
// was created to the trash, so nothing is left unrecorded.
func (tx *Tx) createAll(clis []usage.CLI, plan func(usage.CLI) (createPlan, error)) ([]Op, error) {
	plans := make([]createPlan, 0, len(clis))
	for _, cli := range clis {
		p, err := plan(cli)
		if err != nil {
			return nil, err
		}
		plans = append(plans, p)
	}
	var ops []Op
	for _, p := range plans {
		created, err := p.write()
		if created {
			ops = append(ops, Created(p.path))
		}
		if err != nil {
			return nil, tx.afterRollback(ops, err)
		}
	}
	return ops, nil
}

// writeNewFile creates a file that must not exist yet, with the parent folder when it is missing.
func writeNewFile(path, text string) (bool, error) {
	if err := fsx.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false, err
	}
	if err := fsx.CreateFileExclusive(path, []byte(text), fsx.NewFileMode); err != nil {
		return false, err
	}
	return true, nil
}

// writeSkill creates <dir>/SKILL.md. The folder is created exclusively, so a folder that appeared since the check is
// never taken for ours.
func writeSkill(dir, text string) (bool, error) {
	if err := fsx.MkdirAll(filepath.Dir(dir), 0o755); err != nil {
		return false, err
	}
	if err := fsx.MkdirExclusive(dir, 0o700); err != nil {
		return false, err
	}
	return true, fsx.CreateFileExclusive(filepath.Join(dir, "SKILL.md"), []byte(text), fsx.NewFileMode)
}

// normalize is path.resolve for an absolute path: "." and ".." folded, no trailing slash. Links are not followed
// (InventoryFileIO.normalize).
func normalize(path string) string {
	var stack []string
	for _, part := range strings.Split(path, "/") {
		switch part {
		case "", ".":
		case "..":
			if len(stack) > 0 {
				stack = stack[:len(stack)-1]
			}
		default:
			stack = append(stack, part)
		}
	}
	return "/" + strings.Join(stack, "/")
}

// realPath is the path with links followed, or the normalized path when it does not exist.
func realPath(path string) string {
	abs := normalize(path)
	if resolved, err := filepath.EvalSymlinks(abs); err == nil {
		return resolved
	}
	return abs
}
