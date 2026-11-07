package mutate

import (
	"errors"
	"os"
	"slices"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// undoable are the op kinds Undo can reverse. The two hook kinds are written by this package (see hooks.go).
var undoable = []string{"file-edited", "created", "moved", "link-removed", "hook-added", "hook-removed"}

// putBack puts back what an undone op had changed, when a later op refuses. A failure is reported, never
// dropped (G-fix.9; Swift ran these with try? and left a half-undone entry without a word).
type putBack func() error

// RecordMutation persists a completed mutation, restoring its ops when the journal cannot be saved. The caller holds
// the lock. If the restore itself fails, the error says so and keeps the original one behind it (G-fix.9).
func (tx *Tx) RecordMutation(label string, ops []Op) (Entry, error) {
	entry, err := tx.record(label, ops)
	if err != nil {
		return Entry{}, tx.afterRollback(ops, err)
	}
	return entry, nil
}

// afterRollback rolls the ops back and returns cause, or, when the rollback itself failed, the fixed
// RollbackFailureMessage error (500) with cause kept behind it (G-fix.9; Swift dropped the original error).
func (tx *Tx) afterRollback(ops []Op, cause error) error {
	if failures := tx.rollbackMutation(ops); failures != nil {
		return chain(coreerr.NewStatus(RollbackFailureMessage, coreerr.StatusInternalFailure), errors.Join(cause, failures))
	}
	return cause
}

// rollbackMutation rolls back every completed op even if one fails. Hooks use their exact backup, never the user
// Undo fallback: reversing a failed transaction must not silently keep a partial write or overwrite a concurrent
// change. A dead-hook batch shares one restore op; that file is restored once. It returns every step failure joined
// (nil when all steps worked), so the caller can keep them behind its fixed sentence.
func (tx *Tx) rollbackMutation(ops []Op) error {
	var restored []Op
	var failures []error
	for _, op := range slices.Backward(ops) {
		if err := tx.rollbackOp(op, &restored); err != nil {
			failures = append(failures, err)
		}
	}
	return errors.Join(failures...)
}

func (tx *Tx) rollbackOp(op Op, restored *[]Op) error {
	if op.Type() == "hook-added" || op.Type() == "hook-removed" {
		restore, ok := op.JSON.Member("restore")
		if !ok || restore.Kind() != ojson.KindObject {
			return fail(RollbackFailureMessage, coreerr.StatusInternalFailure)
		}
		restoreOp := Op{restore}
		if t, _ := restoreOp.str("type"); t != "file-edited" {
			return fail(RollbackFailureMessage, coreerr.StatusInternalFailure)
		}
		for _, done := range *restored {
			if done.JSON.Equal(restore) {
				return nil
			}
		}
		if _, err := tx.undoFileEdit(restoreOp); err != nil {
			return err
		}
		*restored = append(*restored, restoreOp)
		return nil
	}
	_, err := tx.undoOp(op)
	return err
}

// Undo reverses an entry's ops, last first, and marks it undone; it returns the entry's label. All or nothing: if one
// op refuses or fails, the ones already reversed are put back and the entry stays undoable. If a put-back itself fails,
// the error says the entry is partly undone (G-fix.9).
func Undo(r roots.Roots, id string) (string, error) {
	return locked(r, func(tx *Tx) (string, error) { return tx.Undo(id) })
}

// Undo is the package function Undo with the lock already held.
func (tx *Tx) Undo(id string) (string, error) {
	all, err := entriesForWriting(tx.r)
	if err != nil {
		return "", err
	}
	index := slices.IndexFunc(all, func(e Entry) bool { return e.ID == id })
	if index < 0 {
		return "", fail("That history entry is gone.", coreerr.StatusNotFound)
	}
	entry := all[index]
	if entry.Undone {
		return "", fail("This was already undone.", coreerr.StatusConflict)
	}
	for _, op := range entry.Ops {
		if !slices.Contains(undoable, op.Type()) {
			return "", fail("This history entry has changes this version cannot undo. Nothing was changed.", coreerr.StatusBadRequest)
		}
	}
	// G-fix.3: a journal.json is a file anyone can edit; nothing is touched before every path is checked.
	guard := newContainment(tx.r)
	for _, op := range entry.Ops {
		if err := guard.checkOp(op); err != nil {
			return "", err
		}
	}

	var rollbacks []putBack
	err = func() error {
		if isHookRemovalBatch(entry.Ops) {
			back, err := tx.undoHooks(entry.Ops)
			if err != nil {
				return err
			}
			rollbacks = append(rollbacks, back)
		} else {
			for _, op := range slices.Backward(entry.Ops) {
				back, err := tx.undoOp(op)
				if err != nil {
					return err
				}
				rollbacks = append(rollbacks, back)
			}
		}
		updated := slices.Clone(all)
		updated[index] = entry.markedUndone()
		return tx.writeJournal(updated)
	}()
	if err != nil {
		var failures []error
		for _, back := range slices.Backward(rollbacks) {
			if berr := back(); berr != nil {
				failures = append(failures, berr)
			}
		}
		if len(failures) > 0 {
			return "", chain(coreerr.NewStatus(PartlyUndoneMessage, coreerr.StatusInternalFailure), errors.Join(append([]error{err}, failures...)...))
		}
		return "", err
	}
	return entry.Label, nil
}

func opField(op Op, key string) (string, error) {
	value, ok := op.str(key)
	if !ok {
		return "", fail(unknownEntryMessage, coreerr.StatusBadRequest)
	}
	return value, nil
}

func nothingToPutBack() error { return nil }

// undoOp reverses one op and returns what puts things back, used when a later op refuses.
func (tx *Tx) undoOp(op Op) (putBack, error) {
	switch op.Type() {
	case "created":
		path, err := opField(op, "path")
		if err != nil {
			return nil, err
		}
		if !pathExists(path) {
			return nothingToPutBack, nil
		}
		moved, err := moveToTrash(tx.r, path)
		if err != nil {
			return nil, err
		}
		to, _ := moved.str("to")
		return func() error { return moveFile(to, path) }, nil

	case "moved":
		from, err := opField(op, "from")
		if err != nil {
			return nil, err
		}
		to, err := opField(op, "to")
		if err != nil {
			return nil, err
		}
		if pathExists(from) {
			return nil, fail(from+" already exists again, so it was left alone.", coreerr.StatusConflict)
		}
		if !pathExists(to) {
			return nil, fail("The saved copy of "+from+" is gone, so it was left alone.", coreerr.StatusConflict)
		}
		if err := moveFile(to, from); err != nil {
			return nil, err
		}
		return func() error { return moveFile(from, to) }, nil

	case "link-removed":
		path, err := opField(op, "path")
		if err != nil {
			return nil, err
		}
		target, err := opField(op, "target")
		if err != nil {
			return nil, err
		}
		if pathExists(path) {
			return nil, fail(path+" already exists again, so it was left alone.", coreerr.StatusConflict)
		}
		if err := fsx.Symlink(target, path); err != nil {
			if statusOf(err) == coreerr.StatusConflict {
				return nil, err
			}
			return nil, fail("Could not restore the link at "+path+".", coreerr.StatusInternalFailure)
		}
		return func() error { return fsx.RemoveFile(path) }, nil

	case "file-edited":
		return tx.undoFileEdit(op)

	case "hook-added", "hook-removed":
		return tx.undoHooks([]Op{op})
	}
	return nil, fail(unknownEntryMessage, coreerr.StatusBadRequest)
}

// undoFileEdit puts the old bytes of an edit back, only if the file still holds what the edit wrote.
func (tx *Tx) undoFileEdit(op Op) (putBack, error) {
	file, err := opField(op, "file")
	if err != nil {
		return nil, err
	}
	after, err := opField(op, "after")
	if err != nil {
		return nil, err
	}
	existed := false
	if v, ok := op.JSON.Member("existed"); ok {
		existed, _ = v.BoolValue()
	}
	// Only undo what this edit wrote: a hand edit made since then is not ours to overwrite.
	now, err := readRegular(file, -1)
	if err != nil || hashes.SHA256Hex(now) != after {
		return nil, fail(file+" changed since this edit, so it was left alone.", coreerr.StatusConflict)
	}
	if !existed {
		moved, err := moveToTrash(tx.r, file)
		if err != nil {
			return nil, err
		}
		to, _ := moved.str("to")
		return func() error { return moveFile(to, file) }, nil
	}
	backup, ok := op.str("backup")
	var old []byte
	if ok {
		old, err = readRegular(backup, -1)
	}
	if !ok || err != nil {
		return nil, fail("The saved copy of "+file+" is gone, so it was left alone.", coreerr.StatusConflict)
	}
	mode := os.FileMode(0o600)
	if info, err := os.Stat(file); err == nil {
		mode = info.Mode().Perm()
	}
	err = fsx.AtomicWrite(file, old, mode, fsx.AtomicWriteOptions{BeforeRename: func() error {
		if !fsx.UnchangedSince(file, now) {
			return fail(file+" changed while SpaceVibe was undoing, so it was left alone.", coreerr.StatusConflict)
		}
		return nil
	}})
	if err != nil {
		return nil, err
	}
	return func() error { return fsx.AtomicWrite(file, now, mode, fsx.AtomicWriteOptions{}) }, nil
}
