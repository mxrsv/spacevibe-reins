package mutate

import (
	"context"
	"os"
	"slices"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
	"spacevibe.dev/core/internal/usage"
)

// Hook writes and their undo (MutateHooks.swift). A hook op keeps the shape the Node core writes (type, file, event,
// matcher, hook) plus restore: the file-edited op of the exact edit. Undo puts the old bytes back when the file still
// holds what that edit wrote, so the file comes back byte for byte; if the file changed since, it falls back to the
// logical reverse (remove or re-add the hook), which is all the Node core ever does. Node ignores the extra key.

// AddHook adds one hook to the hook file of each CLI. It is Go API only, never an RPC method (G-fix.16): a hook
// written for Codex is skipped by Codex until it is trusted.
func AddHook(r roots.Roots, clis []usage.CLI, event string, matcher *string, command string, timeout *float64) (Entry, error) {
	return locked(r, func(tx *Tx) (Entry, error) { return tx.addHook(clis, event, matcher, command, timeout) })
}

func (tx *Tx) addHook(clis []usage.CLI, event string, matcher *string, command string, timeout *float64) (Entry, error) {
	if err := tx.PrepareMutation(); err != nil {
		return Entry{}, err
	}
	command = textjs.Trim(command)
	if err := need(command != "", "Enter the command this hook runs."); err != nil {
		return Entry{}, err
	}
	if err := requireCLIs(clis); err != nil {
		return Entry{}, err
	}
	clis = dedupe(clis)
	for _, cli := range clis {
		if err := need(slices.Contains(events(cli), event), label(cli)+" has no "+event+" event."); err != nil {
			return Entry{}, err
		}
	}
	if matcher != nil {
		trimmed := textjs.Trim(*matcher)
		matcher = &trimmed
		if trimmed == "" {
			matcher = nil
		}
	}
	hook, err := hookValue(command, timeout)
	if err != nil {
		return Entry{}, err
	}

	var ops []Op
	for _, cli := range clis {
		file := tx.cliRoots(cli).HookFile
		edit, err := tx.ApplyJSON(file, nil, func(doc *ojson.Document) (*ojson.Document, error) {
			return hookAdding(doc, file, event, matcher, hook)
		})
		if err != nil {
			// A later CLI failed: put back the files already changed so no change is left without a journal entry.
			return Entry{}, tx.afterRollback(ops, err)
		}
		if edit == nil {
			continue
		}
		ops = append(ops, hookOp("hook-added", file, event, matcher, hook, *edit))
	}
	return tx.RecordMutation("Added "+event+" hook to "+labels(clis), ops)
}

func (tx *Tx) removeHook(hook inventory.Hook) (Entry, error) {
	if err := tx.PrepareMutation(); err != nil {
		return Entry{}, err
	}
	file := tx.cliRoots(hook.CLI).HookFile
	var removed ojson.Value
	var found bool
	edit, err := tx.ApplyJSON(file, nil, func(doc *ojson.Document) (*ojson.Document, error) {
		next, value, ok, err := hookRemoving(doc, file, hook.Event, hook.Matcher, hook.Command)
		if err != nil {
			return nil, err
		}
		if err := need(ok, "This hook has already changed. Refresh the list.", coreerr.StatusConflict); err != nil {
			return nil, err
		}
		removed, found = value, true
		return next, nil
	})
	if err != nil {
		return Entry{}, err
	}
	if edit == nil || !found {
		return Entry{}, fail("This hook has already changed. Refresh the list.", coreerr.StatusConflict)
	}
	op := hookOp("hook-removed", file, hook.Event, hook.Matcher, removed, *edit)
	return tx.RecordMutation("Removed "+hook.Event+" hook from "+label(hook.CLI), []Op{op})
}

// RemoveDeadHooks removes every dead, user-level hook of one CLI in one file write and one journal entry.
func RemoveDeadHooks(r roots.Roots, cli usage.CLI) (Entry, error) {
	return removeDeadHooks(context.Background(), r, cli)
}

func removeDeadHooks(ctx context.Context, r roots.Roots, cli usage.CLI) (Entry, error) {
	return lockedContext(ctx, r, func(tx *Tx) (Entry, error) { return tx.removeDeadHooks(cli) })
}

func (tx *Tx) removeDeadHooks(cli usage.CLI) (Entry, error) {
	if err := tx.PrepareMutation(); err != nil {
		return Entry{}, err
	}
	var dead []inventory.Hook
	for _, h := range inventory.Read(tx.r).Hooks {
		if h.CLI == cli && h.Dead && h.Removable {
			dead = append(dead, h)
		}
	}
	if err := need(len(dead) > 0, "No dead hooks to remove.", coreerr.StatusConflict); err != nil {
		return Entry{}, err
	}
	file := tx.cliRoots(cli).HookFile
	type removal struct {
		hook  inventory.Hook
		value ojson.Value
	}
	var removed []removal
	edit, err := tx.ApplyJSON(file, nil, func(doc *ojson.Document) (*ojson.Document, error) {
		for _, h := range dead {
			next, value, ok, err := hookRemoving(doc, file, h.Event, h.Matcher, h.Command)
			if err != nil {
				return nil, err
			}
			doc = next
			if ok {
				removed = append(removed, removal{h, value})
			}
		}
		return doc, nil
	})
	if err != nil {
		return Entry{}, err
	}
	if edit == nil || len(removed) == 0 {
		return Entry{}, fail("No dead hooks to remove.", coreerr.StatusConflict)
	}
	ops := make([]Op, len(removed))
	for i, rm := range removed {
		ops[i] = hookOp("hook-removed", file, rm.hook.Event, rm.hook.Matcher, rm.value, *edit)
	}
	return tx.RecordMutation("Removed "+itoa(len(ops))+" dead hooks from "+label(cli), ops)
}

func hookOp(kind, file, event string, matcher *string, hook ojson.Value, restore Op) Op {
	m := ojson.Null()
	if matcher != nil {
		m = ojson.String(*matcher)
	}
	return Op{ojson.Object(
		member("type", ojson.String(kind)), member("file", ojson.String(file)), member("event", ojson.String(event)),
		member("matcher", m), member("hook", hook), member("restore", restore.JSON),
	)}
}

// isHookRemovalBatch: several hook removals in one entry are one file write (RemoveDeadHooks), so undo reverses them
// together, not one by one.
func isHookRemovalBatch(ops []Op) bool {
	return len(ops) > 1 && !slices.ContainsFunc(ops, func(op Op) bool { return op.Type() != "hook-removed" })
}

// undoHooks reverses hook-added or hook-removed ops that share one file, and returns what puts things back.
func (tx *Tx) undoHooks(ops []Op) (putBack, error) {
	if len(ops) == 0 {
		return nil, fail(unknownEntryMessage, coreerr.StatusBadRequest)
	}
	file, ok := ops[0].str("file")
	if !ok {
		return nil, fail(unknownEntryMessage, coreerr.StatusBadRequest)
	}
	if restore, ok := ops[0].JSON.Member("restore"); ok {
		restoreOp := Op{restore}
		if kind, _ := restoreOp.str("type"); kind == "file-edited" {
			back, err := tx.undoFileEdit(restoreOp)
			if err == nil {
				return back, nil
			}
			// The file is not what that edit wrote any more (edited by hand, or by a later entry): reverse the hooks
			// only. Any other failure stops the undo.
			if statusOf(err) != coreerr.StatusConflict {
				return nil, err
			}
		}
	}
	return tx.undoByHooks(file, ops)
}

func (tx *Tx) undoByHooks(file string, ops []Op) (putBack, error) {
	realFile := roots.ResolvedPath(file)
	before, readErr := readRegular(realFile, -1)
	mode := os.FileMode(0o600)
	if info, err := os.Stat(realFile); err == nil {
		mode = info.Mode().Perm()
	}
	edit, err := tx.ApplyJSON(file, nil, func(doc *ojson.Document) (*ojson.Document, error) {
		for _, op := range ops {
			event, hasEvent := op.str("event")
			hook, hasHook := op.JSON.Member("hook")
			if !hasEvent || !hasHook {
				return nil, fail(unknownEntryMessage, coreerr.StatusBadRequest)
			}
			var matcher *string
			if s, ok := op.str("matcher"); ok {
				matcher = &s
			}
			switch op.Type() {
			case "hook-added":
				command, _ := commandOf(hook)
				next, _, _, err := hookRemoving(doc, file, event, matcher, command)
				if err != nil {
					return nil, err
				}
				doc = next
			case "hook-removed":
				next, err := hookAdding(doc, file, event, matcher, hook)
				if err != nil {
					return nil, err
				}
				doc = next
			default:
				return nil, fail(unknownEntryMessage, coreerr.StatusBadRequest)
			}
		}
		return doc, nil
	})
	if err != nil {
		return nil, err
	}
	if edit == nil {
		return nothingToPutBack, nil
	}
	return func() error {
		if readErr == nil {
			return fsx.AtomicWrite(realFile, before, mode, fsx.AtomicWriteOptions{})
		}
		return fsx.RemoveFile(realFile)
	}, nil
}
