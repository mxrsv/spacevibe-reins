package methods

import (
	"context"
	"errors"
	"os"

	"spacevibe.dev/core/internal/activity"
	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/limits"
	"spacevibe.dev/core/internal/mutate"
)

// CLIList is the clis.list result: every CLI in the registry, in wire order (spec MC27). It is how the shell learns the
// per-CLI facts the core owns; the shell keeps only each CLI's look (mark, tone). Each fact is read from the adapter
// that implements it, never from a second table.
type CLIList struct {
	CLIs []CLIInfo `json:"clis"`
}

// CLIInfo is one CLI.
type CLIInfo struct {
	ID    clis.ID `json:"id"`
	Label string  `json:"label"`
	// Installed: its root folder exists, or a binary its registry entry names is on PATH (stat only, MC8).
	Installed bool           `json:"installed"`
	Concepts  []clis.Concept `json:"concepts"`
	// Kinds is the inventory declaration of every item kind, in inventory.ItemKinds order; all absent for a CLI
	// without the inventory concept.
	Kinds []KindInfo `json:"kinds"`
	// LimitsReading is where its limits come from (limits.ReadingKind); null without the limits concept.
	LimitsReading *limits.ReadingKind `json:"limitsReading"`
	// LogsHookRuns: its hook kind exists and its logs count hook runs.
	LogsHookRuns bool `json:"logsHookRuns"`
	// ReadsSessionLog: it has the activity concept, so Activity lists its sessions from its logs.
	ReadsSessionLog bool `json:"readsSessionLog"`
	// ApprovalLimitCode is the code of the Activity limit a session carries when a wait for approval cannot be told
	// from a busy tool run; null when it has none.
	ApprovalLimitCode *activity.Reason `json:"approvalLimitCode"`
	// SubagentWithoutToolsGetsEveryTool: an agent SpaceVibe copies into it, which names no tools, can use every tool.
	SubagentWithoutToolsGetsEveryTool bool `json:"subagentWithoutToolsGetsEveryTool"`
}

// KindInfo is one item kind of one CLI (inventory.KindSupport). Members that do not apply are null. The hook events
// are not repeated here: inventory.read and loadout.rows carry them in events.
type KindInfo struct {
	Kind            inventory.Kind        `json:"kind"`
	Support         inventory.Support     `json:"support"`
	Runs            *inventory.Runs       `json:"runs"`
	NotLoggedReason *string               `json:"notLoggedReason"`
	CopyFormat      *inventory.CopyFormat `json:"copyFormat"`
}

func (s *Services) clisList(_ context.Context, _ none) (CLIList, error) {
	out := CLIList{CLIs: []CLIInfo{}}
	for _, d := range clis.All() {
		info, err := s.describe(d)
		if err != nil {
			return CLIList{}, err
		}
		out.CLIs = append(out.CLIs, info)
	}
	return out, nil
}

// describe gathers the facts of one CLI from the registry and from each subsystem's adapter. A subsystem the CLI does
// not take part in gives the fact's empty reading (clis.ErrConceptAbsent), never another CLI's.
func (s *Services) describe(d clis.Descriptor) (CLIInfo, error) {
	folders, err := s.roots.CLI(d.ID)
	if err != nil {
		return CLIInfo{}, err
	}
	info := CLIInfo{
		ID: d.ID, Label: d.Label, Concepts: append([]clis.Concept{}, d.Concepts...),
		Installed:                         clis.Installed(d, folders.Root, s.cfg.SearchPath, os.Stat),
		ReadsSessionLog:                   d.Has(clis.Activity),
		SubagentWithoutToolsGetsEveryTool: mutate.AgentWithoutToolsGetsEveryTool(d.ID),
	}
	kinds, err := inventory.KindsOf(d.ID)
	if err != nil {
		return CLIInfo{}, err
	}
	for _, kind := range inventory.ItemKinds {
		info.Kinds = append(info.Kinds, kindInfo(kind, kinds.Of(kind)))
	}
	hooks := kinds.Of(inventory.KindHook)
	info.LogsHookRuns = hooks.Support != inventory.SupportAbsent && hooks.Runs == inventory.RunsCounted
	if kind, err := limits.KindOf(d.ID); err == nil {
		info.LimitsReading = &kind
	} else if !errors.Is(err, clis.ErrConceptAbsent) {
		return CLIInfo{}, err
	}
	if code, err := activity.ApprovalLimit(d.ID); err == nil && code != "" {
		info.ApprovalLimitCode = &code
	} else if err != nil && !errors.Is(err, clis.ErrConceptAbsent) {
		return CLIInfo{}, err
	}
	return info, nil
}

func kindInfo(kind inventory.Kind, k inventory.KindSupport) KindInfo {
	out := KindInfo{Kind: kind, Support: k.Support}
	if k.Runs != "" {
		runs := k.Runs
		out.Runs = &runs
	}
	if k.NotLoggedReason != "" {
		reason := k.NotLoggedReason
		out.NotLoggedReason = &reason
	}
	if k.CopyFormat != "" {
		format := k.CopyFormat
		out.CopyFormat = &format
	}
	return out
}
