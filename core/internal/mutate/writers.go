package mutate

import (
	"strings"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/roots"
)

// cliWriter is how SpaceVibe writes one CLI's files, beyond the folders its registry layout names (skills, agents,
// hook file), which every write uses the same way.
type cliWriter interface {
	// agentFile is the file extension and text of a new agent in the CLI's own format.
	agentFile(name, description, instructions string) (ext, text string)
	// takesCopiedHooks is true when a hook copied from another CLI may be written into this CLI's hook file.
	takesCopiedHooks() bool
	// agentWithoutToolsGetsEveryTool is true when the CLI gives a subagent whose file names no tools every tool. agentFile
	// never writes a tools line, so this is what a copied agent can do in that CLI.
	agentWithoutToolsGetsEveryTool() bool
	// configFiles are the CLI's configuration files an Undo may edit. They are matched by real path, so a file that
	// is a link out of the CLI folder (a dotfiles setup) is still accepted.
	configFiles(cli roots.CLIRoots) []string
}

// writers is the mutate adapter of every CLI with the mutate concept. A CLI without one is never written: a write
// naming it is refused with an error wrapping clis.ErrUnknownCLI or clis.ErrConceptAbsent, never sent to another
// CLI's folders.
var writers = clis.NewAdapters(clis.Mutate, map[clis.ID]cliWriter{
	clis.Claude: claudeWriter{},
	clis.Codex:  codexWriter{},
})

// writerOf is the writer and folders of a CLI SpaceVibe writes.
func (tx *Tx) writerOf(cli clis.ID) (cliWriter, roots.CLIRoots, error) {
	w, err := writers.For(cli)
	if err != nil {
		return nil, roots.CLIRoots{}, err
	}
	folders, err := tx.r.CLI(cli)
	if err != nil {
		return nil, roots.CLIRoots{}, err
	}
	return w, folders, nil
}

// cliRoots is the folders of a CLI SpaceVibe writes; see writerOf.
func (tx *Tx) cliRoots(cli clis.ID) (roots.CLIRoots, error) {
	_, folders, err := tx.writerOf(cli)
	return folders, err
}

// label is the CLI's product name from the registry; an id with no entry is shown as it is.
func label(cli clis.ID) string {
	if d, err := clis.Lookup(cli); err == nil {
		return d.Label
	}
	return string(cli)
}

func labels(targets []clis.ID) string {
	parts := make([]string, len(targets))
	for i, cli := range targets {
		parts[i] = label(cli)
	}
	return strings.Join(parts, " and ")
}

// AgentWithoutToolsGetsEveryTool is true when an agent SpaceVibe writes into cli (which names no tools) can use every
// tool there. False for a CLI SpaceVibe does not write.
func AgentWithoutToolsGetsEveryTool(cli clis.ID) bool {
	w, err := writers.For(cli)
	return err == nil && w.agentWithoutToolsGetsEveryTool()
}

// kindsOf is each CLI's per-kind declaration, from its inventory adapter. Tests swap it to try a declaration no shipped
// CLI has.
var kindsOf = inventory.KindsOf

// writableKind refuses a write of kind into cli unless the CLI's inventory adapter declares the kind full: an absent
// kind is never a target, and a read-only one is never written (spec MC-R5, MC11).
func writableKind(cli clis.ID, kind inventory.Kind) error {
	kinds, err := kindsOf(cli)
	if err != nil {
		return err
	}
	switch kinds.Of(kind).Support {
	case inventory.SupportFull:
		return nil
	case inventory.SupportReadOnly:
		return fail("SpaceVibe only shows the "+string(kind)+"s of "+label(cli)+", so nothing was changed.", coreerr.StatusForbidden)
	}
	return fail(label(cli)+" has no "+string(kind)+"s, so nothing was changed.", coreerr.StatusConflict)
}

// requireCopyTarget refuses a target id SpaceVibe does not write: an unknown id (wrapping clis.ErrUnknownCLI) or a
// CLI without the mutate concept (wrapping clis.ErrConceptAbsent). It looks at no file.
func requireCopyTarget(target clis.ID) error {
	if _, err := writers.For(target); err != nil {
		if d, lookup := clis.Lookup(target); lookup == nil {
			return chain(coreerr.New("SpaceVibe does not write "+d.Label+", so nothing was copied."), err)
		}
		return chain(coreerr.New("target must be "+writableIDs()+"."), err)
	}
	return nil
}

// copyAllowed refuses a copy of kind from source into target unless target is another CLI that writes the kind and
// reads the same copy format (spec MC-R8). Different formats are refused, never converted (MC5).
func copyAllowed(source, target clis.ID, kind inventory.Kind) error {
	if source == target {
		return coreerr.New("This " + string(kind) + " is already in " + label(target) + ". Pick another CLI to copy it to.")
	}
	if err := writableKind(target, kind); err != nil {
		return err
	}
	from, err := kindsOf(source)
	if err != nil {
		return err
	}
	to, err := kindsOf(target)
	if err != nil {
		return err
	}
	format := from.Of(kind).CopyFormat
	if format == "" || format != to.Of(kind).CopyFormat {
		return fail(label(target)+" reads another "+string(kind)+" format, so this "+string(kind)+" cannot be copied to it.", coreerr.StatusConflict)
	}
	return nil
}

// writableIDs is "claude or codex": the ids of the CLIs SpaceVibe writes, for the refusal of any other id.
func writableIDs() string {
	var ids []string
	for _, w := range writers.InOrder() {
		ids = append(ids, string(w.ID))
	}
	return strings.Join(ids, " or ")
}
