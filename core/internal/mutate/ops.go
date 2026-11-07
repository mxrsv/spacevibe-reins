package mutate

import (
	"spacevibe.dev/core/internal/ojson"
)

// Op is one recorded change. It is held as raw JSON so a journal written by the Node core or the Swift
// engine (including op kinds this version cannot undo) is read and written back without losing a field.
//
// Op kinds:
//   - file-edited {file, existed, backup, after}: file is a real path, backup the old bytes in the trash (null
//     when the edit created the file), after the SHA-256 hex of the bytes written.
//   - created {path}: undo moves it to the trash.
//   - moved {from, to}: to is in the trash; undo moves it back.
//   - link-removed {path, target}: undo makes the link again.
//   - hook-added / hook-removed {file, event, matcher, hook, restore}: see hooks.go.
type Op struct {
	JSON ojson.Value
}

// Type is the op kind, or "" when the op has none.
func (o Op) Type() string {
	s, _ := o.str("type")
	return s
}

func (o Op) str(key string) (string, bool) {
	v, ok := o.JSON.Member(key)
	if !ok {
		return "", false
	}
	return v.StringValue()
}

func member(k string, v ojson.Value) ojson.Member { return ojson.Member{Key: k, Value: v} }

// FileEdited is the op of an atomic file edit. backup is "" when the edit created the file.
func FileEdited(file string, existed bool, backup, after string) Op {
	b := ojson.Null()
	if backup != "" {
		b = ojson.String(backup)
	}
	return Op{ojson.Object(
		member("type", ojson.String("file-edited")), member("file", ojson.String(file)), member("existed", ojson.Bool(existed)),
		member("backup", b), member("after", ojson.String(after)),
	)}
}

// Created is the op of a path this change created.
func Created(path string) Op {
	return Op{ojson.Object(member("type", ojson.String("created")), member("path", ojson.String(path)))}
}

// Moved is the op of a path moved into the trash.
func Moved(from, to string) Op {
	return Op{ojson.Object(member("type", ojson.String("moved")), member("from", ojson.String(from)), member("to", ojson.String(to)))}
}

// LinkRemoved is the op of a removed link; target is the link text.
func LinkRemoved(path, target string) Op {
	return Op{ojson.Object(member("type", ojson.String("link-removed")), member("path", ojson.String(path)), member("target", ojson.String(target)))}
}

// Entry is one journal entry.
type Entry struct {
	ID string
	// At is ISO 8601 UTC with milliseconds, like Date.toISOString().
	At     string
	Label  string
	Undone bool
	Ops    []Op
}

// EntryRef is what the RPC methods return for an entry (docs/internals/core-protocol.md, JournalEntryRef):
// ops hold absolute paths and trash names, so only their count leaves the core.
type EntryRef struct {
	ID     string `json:"id"`
	At     string `json:"at"`
	Label  string `json:"label"`
	Undone bool   `json:"undone"`
	Count  int    `json:"count"`
}

// Ref is the summary of the entry (Swift HistoryItem).
func (e Entry) Ref() EntryRef {
	return EntryRef{ID: e.ID, At: e.At, Label: e.Label, Undone: e.Undone, Count: len(e.Ops)}
}

func (e Entry) value() ojson.Value {
	ops := make([]ojson.Value, len(e.Ops))
	for i, op := range e.Ops {
		ops[i] = op.JSON
	}
	members := []ojson.Member{
		member("id", ojson.String(e.ID)), member("at", ojson.String(e.At)), member("label", ojson.String(e.Label)),
		member("ops", ojson.Array(ops...)),
	}
	if e.Undone {
		members = append(members, member("undone", ojson.Bool(true)))
	}
	return ojson.Object(members...)
}

// entryFromValue is false when the value is not an entry (no string id); the journal reader refuses such a journal (409).
func entryFromValue(v ojson.Value) (Entry, bool) {
	idv, _ := v.Member("id")
	id, ok := idv.StringValue()
	if !ok {
		return Entry{}, false
	}
	e := Entry{ID: id}
	if s, ok := stringMember(v, "at"); ok {
		e.At = s
	}
	if s, ok := stringMember(v, "label"); ok {
		e.Label = s
	}
	if u, ok := v.Member("undone"); ok {
		e.Undone, _ = u.BoolValue()
	}
	if ops, ok := v.Member("ops"); ok {
		if items, ok := ops.ArrayValue(); ok {
			for _, item := range items {
				e.Ops = append(e.Ops, Op{item})
			}
		}
	}
	return e, true
}

func stringMember(v ojson.Value, key string) (string, bool) {
	m, ok := v.Member(key)
	if !ok {
		return "", false
	}
	return m.StringValue()
}

func (e Entry) markedUndone() Entry {
	e.Undone = true
	return e
}
