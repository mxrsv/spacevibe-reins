package mutate

import (
	"bytes"
	"path/filepath"
	"unicode"
	"unicode/utf8"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// The one way SpaceVibe changes a config file: atomic, undoable, content-safe (FileEdit.swift). Same job as editFile in
// Node mutate, plus a JSON layer that does what parseConfig and serialize do in Node rules.
//
//   - The previous bytes are copied to the app trash first; the returned op lets Undo put back exactly those bytes
//     (only if the file still holds what this edit wrote) or move a file this edit created to the trash.
//   - A symlinked file stays a symlink: the target is written.
//   - The mode is kept; a new file gets 0600.
//   - The temp file is re-read and validated before the rename, so a bad write never replaces the file.
//   - Errors never quote file content.
//
// The write guard (fsx.InstallWriteGuard) refuses a path under the real home in every primitive this uses, which
// is what FileEdit.refuseRealHomeUnderTest did at one call site.

// TextChange computes the next text of a file from the current one. current is nil when the file does not exist.
// Returning nil, or the same bytes, is a no-op.
type TextChange func(current *string) (*string, error)

// JSONChange edits a parsed JSON document and returns the edited one. Use the ojson edit methods, which keep key
// order, indent, line endings and every untouched byte.
type JSONChange func(doc *ojson.Document) (*ojson.Document, error)

// Apply edits a text file under the write lock. validate gets the text read back from the temp file; an error
// aborts before the rename. The result is the op to put in a journal entry, or nil for a no-op.
func Apply(r roots.Roots, file string, validate func(string) error, change TextChange) (*Op, error) {
	return locked(r, func(tx *Tx) (*Op, error) { return tx.Apply(file, validate, change) })
}

// ApplyJSON edits a JSON file whose top level is an object, under the write lock. A missing or blank file counts as
// {}. Invalid JSON or a non-object file is refused with a 409 that never quotes content. validate also runs on the
// document read back from the temp file.
func ApplyJSON(r roots.Roots, file string, validate func(*ojson.Document) error, change JSONChange) (*Op, error) {
	return locked(r, func(tx *Tx) (*Op, error) { return tx.ApplyJSON(file, validate, change) })
}

// Edit is Apply plus a journal entry named label. The entry is nil when nothing changed (no entry is recorded).
func Edit(r roots.Roots, file, label string, validate func(string) error, change TextChange) (*Entry, error) {
	return locked(r, func(tx *Tx) (*Entry, error) { return tx.Edit(file, label, validate, change) })
}

// EditJSON is ApplyJSON plus a journal entry named label. The entry is nil when nothing changed.
func EditJSON(r roots.Roots, file, label string, validate func(*ojson.Document) error, change JSONChange) (*Entry, error) {
	return locked(r, func(tx *Tx) (*Entry, error) { return tx.EditJSON(file, label, validate, change) })
}

// Apply is the package function Apply with the lock already held.
func (tx *Tx) Apply(file string, validate func(string) error, change TextChange) (*Op, error) {
	target, err := fsx.ResolveTarget(file)
	if err != nil {
		return nil, err
	}
	var before []byte
	var beforeText *string
	if target.Existed {
		before, err = readRegular(target.Real, -1)
		if err != nil {
			return nil, fail("Could not read "+target.Real+". Nothing was changed.", coreerr.StatusConflict)
		}
		if !utf8.Valid(before) {
			return nil, fail(target.Real+" is not UTF-8 text. Nothing was changed.", coreerr.StatusConflict)
		}
		text := string(before)
		beforeText = &text
	}

	nextText, err := change(beforeText)
	if err != nil {
		return nil, err
	}
	if nextText == nil {
		return nil, nil
	}
	next := []byte(*nextText)
	// Compare bytes. A new file is always written, even an empty one.
	if before != nil && bytes.Equal(next, before) {
		return nil, nil
	}

	backup := ""
	if target.Existed {
		backup, err = slot(tx.r, target.Real)
		if err != nil {
			return nil, err
		}
		if err := fsx.AtomicWrite(backup, before, 0o600, fsx.AtomicWriteOptions{}); err != nil {
			// The slot folder exists already; do not leave it behind.
			_ = fsx.RemoveTree(filepath.Dir(backup))
			return nil, err
		}
	} else if err := fsx.MkdirAll(filepath.Dir(target.Real), 0o755); err != nil {
		return nil, err // names the folder; a write-guard refusal keeps its own sentence
	}

	err = fsx.AtomicWrite(target.Real, next, target.Mode, fsx.AtomicWriteOptions{
		Validate: func(written []byte) error {
			if !utf8.Valid(written) {
				return fail("The new "+target.Real+" would not be valid text. Nothing was changed.", coreerr.StatusConflict)
			}
			if validate != nil {
				return validate(string(written))
			}
			return nil
		},
		// Another process (a CLI, a hand edit) may have written since the read above; never overwrite that.
		BeforeRename: func() error {
			if !fsx.UnchangedSince(target.Real, before) {
				return fail(target.Real+" changed while SpaceVibe was editing it, so it was left alone. Try again.", coreerr.StatusConflict)
			}
			return nil
		},
	})
	if err != nil {
		// The old file is untouched; do not leave an unused backup behind.
		if backup != "" {
			_ = fsx.RemoveTree(filepath.Dir(backup))
		}
		return nil, err
	}
	op := FileEdited(target.Real, target.Existed, backup, hashes.SHA256Hex(next))
	return &op, nil
}

// ApplyJSON is the package function ApplyJSON with the lock already held.
func (tx *Tx) ApplyJSON(file string, validate func(*ojson.Document) error, change JSONChange) (*Op, error) {
	return tx.Apply(file,
		func(text string) error {
			doc, err := ParseObject(text, file)
			if err != nil {
				return err
			}
			if validate != nil {
				return validate(doc)
			}
			return nil
		},
		func(text *string) (*string, error) {
			blank := text == nil || isBlank(*text)
			// A new file starts from a one-line object with a final newline, like a file written by hand.
			var start *ojson.Document
			var err error
			if blank {
				start, err = ojson.ParseString("{}\n")
			} else {
				start, err = ParseObject(*text, file)
			}
			if err != nil {
				return nil, err
			}
			next, err := change(start)
			if err != nil {
				return nil, err
			}
			if blank && bytes.Equal(next.Bytes(), start.Bytes()) {
				return text, nil
			}
			out := next.Text()
			return &out, nil
		})
}

// Edit is the package function Edit with the lock already held.
func (tx *Tx) Edit(file, label string, validate func(string) error, change TextChange) (*Entry, error) {
	if err := tx.PrepareMutation(); err != nil {
		return nil, err
	}
	op, err := tx.Apply(file, validate, change)
	if err != nil || op == nil {
		return nil, err
	}
	entry, err := tx.RecordMutation(label, []Op{*op})
	if err != nil {
		return nil, err
	}
	return &entry, nil
}

// EditJSON is the package function EditJSON with the lock already held.
func (tx *Tx) EditJSON(file, label string, validate func(*ojson.Document) error, change JSONChange) (*Entry, error) {
	if err := tx.PrepareMutation(); err != nil {
		return nil, err
	}
	op, err := tx.ApplyJSON(file, validate, change)
	if err != nil || op == nil {
		return nil, err
	}
	entry, err := tx.RecordMutation(label, []Op{*op})
	if err != nil {
		return nil, err
	}
	return &entry, nil
}

// isBlank is Foundation's whitespace check for a file with nothing but spaces and newlines.
func isBlank(text string) bool {
	for _, r := range text {
		if !unicode.IsSpace(r) {
			return false
		}
	}
	return true
}

// ParseObject parses a JSON file whose top level must be an object. A parse error is replaced by a fixed
// sentence: the parser's position and the text around it can hold a secret.
func ParseObject(text, file string) (*ojson.Document, error) {
	doc, err := ojson.ParseString(text)
	if err != nil {
		return nil, fail(file+" is not valid JSON. Nothing was changed.", coreerr.StatusConflict)
	}
	if _, ok := doc.Root().ObjectValue(); !ok {
		return nil, fail(file+" does not hold a JSON object. Nothing was changed.", coreerr.StatusConflict)
	}
	return doc, nil
}
