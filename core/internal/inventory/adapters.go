package inventory

import (
	"context"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/roots"
)

// cliInventory is one CLI's side of an inventory read, beyond what its registry layout already says (the skills
// and agents folders and the hook file, which Read handles the same way for every CLI).
type cliInventory interface {
	// kinds is the CLI's declaration per item kind (kinds.go): support, run logging, copy format, hook events.
	kinds() Kinds
	// readExtras adds what the CLI keeps outside its root folders (Claude Code: plugins and skill overrides). Read
	// calls it after every CLI's root folders were read.
	readExtras(ctx context.Context, cli roots.CLIRoots, acc *readAcc)
}

// cliProjects is one CLI's side of project discovery.
type cliProjects interface {
	// projectCandidates are the project paths the CLI's own files record, newest first where it knows.
	projectCandidates(ctx context.Context, cli roots.CLIRoots) []string
	// projectFolder is the configuration folder the CLI reads inside a project; false when it reads none.
	projectFolder() (projectFolder, bool)
}

// inventoryAdapter is everything one CLI contributes to Read.
type inventoryAdapter interface {
	cliInventory
	cliProjects
}

// projectFolder is the per-project configuration of a CLI: <project>/<Name>/skills, <project>/<Name>/agents and the
// hook files listed. A path containing Worktrees is a copy of a project already listed and is skipped.
type projectFolder struct {
	Name      string
	HookFiles []string
	Worktrees string
}

// adapters is the inventory adapter of every CLI with the inventory concept. A CLI without one has no skills,
// agents or hooks to show: it is left out of Read, never read as another CLI.
var adapters = clis.NewAdapters(clis.Inventory, map[clis.ID]inventoryAdapter{
	clis.Claude: claudeInventory{},
	clis.Codex:  codexInventory{},
})

// boundAdapter is an adapter with its CLI's id and folders.
type boundAdapter struct {
	id      clis.ID
	adapter inventoryAdapter
	roots   roots.CLIRoots
}

// bind pairs every inventory adapter with its CLI's folders, in wire order. A CLI r has no folders for is an error
// wrapping clis.ErrUnknownCLI (a Roots not built by roots.Resolve).
func bind(r roots.Roots) ([]boundAdapter, error) {
	var out []boundAdapter
	for _, a := range adapters.InOrder() {
		cli, err := r.CLI(a.ID)
		if err != nil {
			return nil, err
		}
		out = append(out, boundAdapter{a.ID, a.Adapter, cli})
	}
	return out, nil
}

// Events are the hook events of each CLI with the inventory concept, in wire order.
func Events() []CLIEvents {
	out := []CLIEvents{}
	for _, a := range adapters.InOrder() {
		out = append(out, CLIEvents{CLI: a.ID, Events: a.Adapter.kinds().Of(KindHook).Events})
	}
	return out
}
