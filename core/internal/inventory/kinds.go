package inventory

import (
	"errors"

	"spacevibe.dev/core/internal/clis"
)

// Per-kind support (spec MC-R5, MC29). Each inventory adapter declares, for every item kind, what SpaceVibe does
// with it in that CLI. Three readings stay apart and are never shown as 0:
//
//   - absent: the CLI has no such kind (Support absent). Its cell is absent, never missing, and it is no copy target.
//   - not measurable: the CLI has the kind but its logs do not record runs (Runs notLogged, with the reason).
//   - unsupported format: the CLI has the kind but SpaceVibe cannot write it (Support readOnly), or the copy formats
//     differ, so a copy into it is refused.

// Support says what SpaceVibe does with one item kind of one CLI.
type Support string

const (
	// SupportFull: read, shown, and written (add, remove, copy, each with Undo). Needs the CLI's mutate concept.
	SupportFull Support = "full"
	// SupportReadOnly: read and shown, never written.
	SupportReadOnly Support = "readOnly"
	// SupportAbsent: the CLI has no such kind.
	SupportAbsent Support = "absent"
)

// Runs says whether the CLI's logs record runs of the kind.
type Runs string

const (
	// RunsCounted: the usage scan counts them.
	RunsCounted Runs = "counted"
	// RunsNotLogged: the CLI does not log them; the cell is unmeasurable with KindSupport.NotLoggedReason.
	RunsNotLogged Runs = "notLogged"
)

// CopyFormat names what a copy of the kind carries and what the target writes. Two CLIs whose formats are equal can
// copy the kind between them; different formats are refused, never converted (spec MC-R8, MC5). The name says what is
// copied, not the file syntax: an agent copy carries name, description and instructions, which each CLI's writer
// puts in its own agent file.
type CopyFormat string

const (
	// CopySkillFolder: the skill's folder with its SKILL.md, file by file.
	CopySkillFolder CopyFormat = "skillFolder"
	// CopyAgentFields: an agent's name, description and instructions; not its model or tools.
	CopyAgentFields CopyFormat = "agentFields"
	// CopyCommandHook: a command hook's event, matcher, command and timeout.
	CopyCommandHook CopyFormat = "commandHook"
)

// KindSupport is one CLI's declaration for one item kind.
type KindSupport struct {
	Support Support
	// Runs is empty when Support is absent.
	Runs Runs
	// NotLoggedReason is why runs are not counted; set exactly when Runs is RunsNotLogged.
	NotLoggedReason string
	// CopyFormat is empty when the kind is never copied into or out of this CLI.
	CopyFormat CopyFormat
	// Events are the hook events the CLI documents, in its own order; hooks only. Hook rows of two CLIs share a row
	// only when the event names are identical (Hook.Key hashes event plus command; spec MC28): there is no mapping
	// between CLIs' event vocabularies.
	Events []string
}

// Kinds is one CLI's declaration per item kind. A kind it does not list is absent.
type Kinds map[Kind]KindSupport

// ItemKinds are the kinds an adapter declares, in wire order. Rules, MCP servers and permissions join this list when
// an adapter first reads them (spec MC-R5).
var ItemKinds = []Kind{KindSkill, KindAgent, KindHook}

// Of is the declaration for kind; a kind the CLI does not list is absent.
func (k Kinds) Of(kind Kind) KindSupport {
	if s, ok := k[kind]; ok {
		return s
	}
	return KindSupport{Support: SupportAbsent}
}

// KindsOf is the per-kind declaration of cli. A known CLI without the inventory concept has every kind absent; an id
// with no registry entry is an error wrapping clis.ErrUnknownCLI.
func KindsOf(cli clis.ID) (Kinds, error) {
	a, err := adapters.For(cli)
	if errors.Is(err, clis.ErrConceptAbsent) {
		return Kinds{}, nil
	}
	if err != nil {
		return nil, err
	}
	return a.kinds(), nil
}

// EventsOf is the hook events of one CLI, or an error wrapping clis.ErrUnknownCLI or clis.ErrConceptAbsent.
func EventsOf(cli clis.ID) ([]string, error) {
	a, err := adapters.For(cli)
	if err != nil {
		return nil, err
	}
	return a.kinds().Of(KindHook).Events, nil
}

// UnloggedHooks is why the hook runs of cli cannot be counted, "" when its logs record them, or an error wrapping
// clis.ErrUnknownCLI or clis.ErrConceptAbsent.
func UnloggedHooks(cli clis.ID) (string, error) {
	a, err := adapters.For(cli)
	if err != nil {
		return "", err
	}
	return a.kinds().Of(KindHook).NotLoggedReason, nil
}
