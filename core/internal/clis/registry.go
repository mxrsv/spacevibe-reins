// Package clis is the registry of the CLIs SpaceVibe reads: one descriptor per CLI, pure data. It says which CLIs
// exist, where each keeps its files, and which concepts (subsystems) each takes part in. It imports no subsystem
// package; each subsystem keeps its own per-CLI adapters and checks them against this registry (see Adapters). The
// only behaviour here is the lookups, Find over wire arrays and Installed, a stat-only check. Adding a CLI is one
// entry here plus one adapter in each subsystem whose concept it lists.
package clis

import (
	"errors"
	"fmt"
	"slices"
)

// ID is the wire value of a CLI ("claude", "codex").
type ID string

// The CLIs in the registry.
const (
	Claude ID = "claude"
	Codex  ID = "codex"
	Gemini ID = "gemini"
)

// Concept is a subsystem a CLI takes part in. A CLI that does not list a concept has no adapter for it, and the
// concept reads as absent for that CLI: never as another CLI's, never as zero.
type Concept string

// The concepts.
const (
	// Inventory: skills, subagents and hooks read from the CLI's folders.
	Inventory Concept = "inventory"
	// Mutate: SpaceVibe writes those folders (add, remove, copy, with Undo).
	Mutate Concept = "mutate"
	// Usage: the session logs are scanned for skill, subagent and hook runs.
	Usage Concept = "usage"
	// Activity: running sessions are listed from the logs and the process table, and can be stopped.
	Activity Concept = "activity"
	// Limits: the usage-limit windows the CLI leaves on disk.
	Limits Concept = "limits"
)

// Layout is where a CLI keeps its files. Names are relative to the root folder; an empty name means the CLI has no
// such file, and the resolved path is empty too.
type Layout struct {
	// Folder is the root folder's name under HOME (".claude").
	Folder string
	// RootEnv names the environment variable that replaces the whole root folder (CLAUDE_CONFIG_DIR). Empty when
	// the CLI documents none.
	RootEnv string
	// Skills and Agents are the folders of user-level skills and subagents.
	Skills string
	Agents string
	// HookFile is the file that holds user-level hooks (Claude Code's settings.json, Codex's hooks.json).
	HookFile string
	// Logs is the folder of session logs (Claude Code's projects, Codex's sessions).
	Logs string
	// StateFile is a file kept beside the root, not inside it: in the RootEnv folder when that is set, otherwise in
	// HOME (Claude Code's .claude.json).
	StateFile string
}

// Descriptor is one CLI.
type Descriptor struct {
	ID ID
	// Label is the product name shown to the user ("Claude Code").
	Label  string
	Layout Layout
	// Binaries are the executable names the CLI puts on PATH. Installed looks for them with stat only. Empty when the
	// root folder is enough to tell (every CLI today).
	Binaries []string
	Concepts []Concept
}

// Has reports whether the CLI takes part in the concept.
func (d Descriptor) Has(c Concept) bool { return slices.Contains(d.Concepts, c) }

// registry is every CLI, in wire order: the order reports list CLIs in.
var registry = []Descriptor{
	{
		ID: Claude, Label: "Claude Code",
		Layout: Layout{
			Folder: ".claude", RootEnv: "CLAUDE_CONFIG_DIR",
			Skills: "skills", Agents: "agents", HookFile: "settings.json", Logs: "projects", StateFile: ".claude.json",
		},
		Concepts: []Concept{Inventory, Mutate, Usage, Activity, Limits},
	},
	{
		ID: Codex, Label: "Codex",
		Layout: Layout{
			Folder: ".codex", RootEnv: "CODEX_HOME",
			Skills: "skills", Agents: "agents", HookFile: "hooks.json", Logs: "sessions",
		},
		Concepts: []Concept{Inventory, Mutate, Usage, Activity, Limits},
	},
	{
		// Gemini CLI appears on the Limits surface only, and only its folder's existence is checked.
		ID: Gemini, Label: "Gemini CLI",
		Layout:   Layout{Folder: ".gemini"},
		Concepts: []Concept{Limits},
	},
}

// ErrUnknownCLI is an id with no registry entry. It is never read as another CLI.
var ErrUnknownCLI = errors.New("unknown CLI")

// ErrConceptAbsent is a known CLI asked for a concept it does not take part in.
var ErrConceptAbsent = errors.New("concept absent for this CLI")

// Registry is a list of CLIs in wire order. Default is SpaceVibe's; the package functions below read it. A test that
// needs a CLI the real registry lacks extends a copy with Plus and builds its adapter table over it (NewAdaptersIn),
// so the real registry is never changed.
type Registry struct{ entries []Descriptor }

// Default is the registry SpaceVibe ships.
func Default() Registry { return Registry{entries: registry} }

// Plus is a copy of the registry with d appended after every other CLI.
func (r Registry) Plus(d Descriptor) Registry {
	return Registry{entries: append(slices.Clone(r.entries), d)}
}

// All lists every CLI in wire order. The slice is a copy.
func (r Registry) All() []Descriptor { return slices.Clone(r.entries) }

// With lists the CLIs that take part in the concept, in wire order.
func (r Registry) With(c Concept) []Descriptor {
	var out []Descriptor
	for _, d := range r.entries {
		if d.Has(c) {
			out = append(out, d)
		}
	}
	return out
}

// Lookup is the descriptor of id, or an error wrapping ErrUnknownCLI.
func (r Registry) Lookup(id ID) (Descriptor, error) {
	for _, d := range r.entries {
		if d.ID == id {
			return d, nil
		}
	}
	return Descriptor{}, fmt.Errorf("%w %q", ErrUnknownCLI, id)
}

// Require is Lookup for a CLI that must take part in the concept: an unknown id wraps ErrUnknownCLI, a known CLI
// without the concept wraps ErrConceptAbsent.
func (r Registry) Require(id ID, c Concept) (Descriptor, error) {
	d, err := r.Lookup(id)
	if err != nil {
		return Descriptor{}, err
	}
	if !d.Has(c) {
		return Descriptor{}, fmt.Errorf("%w: %s has no %s", ErrConceptAbsent, id, c)
	}
	return d, nil
}

// All lists every CLI of the default registry in wire order. The slice is a copy.
func All() []Descriptor { return Default().All() }

// With lists the CLIs of the default registry that take part in the concept, in wire order.
func With(c Concept) []Descriptor { return Default().With(c) }

// IDsWith is With as ids.
func IDsWith(c Concept) []ID {
	var out []ID
	for _, d := range With(c) {
		out = append(out, d.ID)
	}
	return out
}

// Lookup is Registry.Lookup on the default registry.
func Lookup(id ID) (Descriptor, error) { return Default().Lookup(id) }

// Require is Registry.Require on the default registry.
func Require(id ID, c Concept) (Descriptor, error) { return Default().Require(id, c) }
