package mutate

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"time"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// The undo journal: <data>/journal.json, a JSON array, newest first, at most JournalLimit entries (Journal.swift).
// Same file and entry shape as the Node core and the Swift engine, so any of them can read what another wrote.
//
// One deliberate break from the Node core: a journal.json that exists but is not a JSON array of entries makes every
// write path refuse (409) instead of reading it as empty or dropping elements, so a corrupt undo history is never
// replaced by a fresh one.
//
// An entry and its trash copy end together (trash.go, pruneTrash): writeJournal drops the entries past the limit or
// older than JournalMaxAge and deletes the trash slots only they referenced.
//
// Labels are written verbatim: callers pass a sentence about what changed (a rule name, an item name), never file
// content.

const (
	// JournalLimit is the most entries the journal keeps.
	JournalLimit = 200
	// JournalMaxAge is how long an entry and its trash copy are kept: 200 changes or this long, whichever ends first.
	JournalMaxAge = 30 * 24 * time.Hour
	journalName   = "journal.json"
	// maxJournalBytes bounds the read of journal.json; a larger file is refused like a corrupt one.
	maxJournalBytes = 64 << 20
)

func journalPath(r roots.Roots) string { return filepath.Join(r.Data, journalName) }

func unreadable() error { return fail(UnreadableMessage, coreerr.StatusConflict) }

// entriesForWriting reads the journal for a write. A missing file is empty. A file that exists but cannot be read,
// or is not a JSON array of entries (an element without a string id counts as corrupt; Swift dropped it), is refused,
// so a corrupt journal is never replaced by a fresh one. Any lookup failure
// other than "absent" also refuses (fail closed).
func entriesForWriting(r roots.Roots) ([]Entry, error) {
	path := journalPath(r)
	if _, err := os.Lstat(path); err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil, nil
		}
		return nil, unreadable()
	}
	data, err := readRegular(path, maxJournalBytes)
	if err != nil {
		return nil, unreadable()
	}
	doc, err := ojson.Parse(data)
	if err != nil {
		return nil, unreadable()
	}
	items, ok := doc.Root().ArrayValue()
	if !ok {
		return nil, unreadable()
	}
	entries := make([]Entry, 0, len(items))
	for _, item := range items {
		e, ok := entryFromValue(item)
		if !ok {
			return nil, unreadable() // an element that is not an entry is never dropped by the next write
		}
		entries = append(entries, e)
	}
	return entries, nil
}

// History is every entry, newest first, for display. A journal that exists but is not a JSON array is a 409 with
// UnreadableMessage, not an empty list (G-fix.8; Swift swallowed it, and the app then showed "nothing to undo").
func History(r roots.Roots) ([]EntryRef, error) {
	entries, err := entriesForWriting(r)
	if err != nil {
		return nil, err
	}
	out := make([]EntryRef, len(entries))
	for i, e := range entries {
		out[i] = e.Ref()
	}
	return out, nil
}

// Record adds an entry at the front and returns it, under the write lock.
func Record(r roots.Roots, label string, ops []Op) (Entry, error) {
	return locked(r, func(tx *Tx) (Entry, error) { return tx.record(label, ops) })
}

// record is Record with the lock held. The read, the new list and the write all happen under it (G-fix.4).
func (tx *Tx) record(label string, ops []Op) (Entry, error) {
	id, err := newID()
	if err != nil {
		return Entry{}, fail("Could not create a history id.", coreerr.StatusInternalFailure)
	}
	entry := Entry{ID: id, At: timestamp(), Label: label, Ops: ops}
	existing, err := entriesForWriting(tx.r)
	if err != nil {
		return Entry{}, err
	}
	if err := tx.writeJournal(append([]Entry{entry}, existing...)); err != nil {
		return Entry{}, err
	}
	return entry, nil
}

// PrepareMutation is called under the lock before a config mutation, so an unreadable journal refuses before any
// change.
func (tx *Tx) PrepareMutation() error {
	_, err := entriesForWriting(tx.r)
	return err
}

func (tx *Tx) writeJournal(entries []Entry) error {
	if err := ensureDataFolders(tx.r); err != nil {
		return err
	}
	entries, cut := retained(entries, time.Now())
	values := make([]ojson.Value, len(entries))
	for i, e := range entries {
		values[i] = e.value()
	}
	// Two-space JSON.stringify layout without a trailing newline, as the Node core writes it.
	text, err := ojson.PrettyStyled(ojson.Array(values...), "  ", "\n", false)
	if err != nil {
		return fail("Could not write the undo history.", coreerr.StatusInternalFailure)
	}
	if err := fsx.AtomicWrite(journalPath(tx.r), []byte(text), 0o600, fsx.AtomicWriteOptions{}); err != nil {
		return err
	}
	// After the journal is on disk: a crash before this point leaves slots no entry needs, never an entry whose
	// copy is gone. Pruning is best effort; what it misses the next write sweeps.
	pruneTrash(tx.r, entries, cut, time.Now())
	return nil
}

// retained splits entries (newest first) into the ones the journal keeps and the ones it drops: the first
// JournalLimit that are not older than JournalMaxAge. An entry whose time cannot be read is not dropped for age.
func retained(entries []Entry, now time.Time) (kept, cut []Entry) {
	for _, e := range entries {
		at, err := time.Parse(time.RFC3339Nano, e.At)
		if len(kept) >= JournalLimit || (err == nil && now.Sub(at) > JournalMaxAge) {
			cut = append(cut, e)
		} else {
			kept = append(kept, e)
		}
	}
	return kept, cut
}

// timestamp is ISO 8601 UTC with milliseconds, like Date.toISOString().
func timestamp() string { return time.Now().UTC().Format("2006-01-02T15:04:05.000Z") }

// newID is a random (version 4) UUID in lowercase.
func newID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	h := hex.EncodeToString(b[:])
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:], nil
}
