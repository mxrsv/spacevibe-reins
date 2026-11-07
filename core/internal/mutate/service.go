package mutate

import (
	"context"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/usage"
)

// Service holds the five write methods of the RPC surface: loadout.copyToOther, loadout.removeItem,
// loadout.removeDeadHooks, journal.undo and journal.history (docs/internals/core-protocol.md). A later wiring step
// registers them. AddSkill, AddAgent and AddHook are not methods (see the package comment).
//
// A write is short and ends in a journal entry, so ctx is looked at twice and never in between: before the write lock
// is queued for, and again as the first step inside the lock. A cancelled request never starts, even when it waited
// for the lock; one that has started is never stopped half way.
type Service struct {
	roots roots.Roots
}

// NewService returns a service over the roots.
func NewService(r roots.Roots) *Service { return &Service{roots: r} }

// IDParams is the params of loadout.copyToOther, loadout.removeItem and journal.undo.
type IDParams struct {
	ID string `json:"id"`
}

// CLIParams is the params of loadout.removeDeadHooks.
type CLIParams struct {
	CLI usage.CLI `json:"cli"`
}

// EntryResult is the result of a write: the entry it recorded, without its ops.
type EntryResult struct {
	Entry EntryRef `json:"entry"`
}

// UndoResult is the result of journal.undo.
type UndoResult struct {
	Label string `json:"label"`
}

// HistoryResult is the result of journal.history, newest first, at most JournalLimit entries.
type HistoryResult struct {
	Entries []EntryRef `json:"entries"`
}

// CopyToOther is loadout.copyToOther.
func (s *Service) CopyToOther(ctx context.Context, p IDParams) (EntryResult, error) {
	if err := ctx.Err(); err != nil {
		return EntryResult{}, err
	}
	entry, err := copyToOther(ctx, s.roots, p.ID)
	return EntryResult{Entry: entry.Ref()}, err
}

// RemoveItem is loadout.removeItem.
func (s *Service) RemoveItem(ctx context.Context, p IDParams) (EntryResult, error) {
	if err := ctx.Err(); err != nil {
		return EntryResult{}, err
	}
	entry, err := removeItem(ctx, s.roots, p.ID)
	return EntryResult{Entry: entry.Ref()}, err
}

// RemoveDeadHooks is loadout.removeDeadHooks.
func (s *Service) RemoveDeadHooks(ctx context.Context, p CLIParams) (EntryResult, error) {
	if err := ctx.Err(); err != nil {
		return EntryResult{}, err
	}
	if p.CLI != inventory.Claude && p.CLI != inventory.Codex {
		return EntryResult{}, coreerr.New("cli must be claude or codex.")
	}
	entry, err := removeDeadHooks(ctx, s.roots, p.CLI)
	return EntryResult{Entry: entry.Ref()}, err
}

// Undo is journal.undo.
func (s *Service) Undo(ctx context.Context, p IDParams) (UndoResult, error) {
	if err := ctx.Err(); err != nil {
		return UndoResult{}, err
	}
	label, err := undo(ctx, s.roots, p.ID)
	return UndoResult{Label: label}, err
}

// History is journal.history. A journal that is not a JSON array is a 409, not an empty list (G-fix.8).
func (s *Service) History(ctx context.Context) (HistoryResult, error) {
	if err := ctx.Err(); err != nil {
		return HistoryResult{}, err
	}
	entries, err := History(s.roots)
	if entries == nil {
		entries = []EntryRef{}
	}
	return HistoryResult{Entries: entries}, err
}
