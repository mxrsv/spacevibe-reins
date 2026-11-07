package inventory

import (
	"encoding/json"
	"errors"
)

var errBadCell = errors.New("the usage cell has an unknown shape")

// itemWire is Item as written: the override member is present only for a Claude global skill, and key is
// computed. The field order is InventoryItem.encode's.
type itemWire struct {
	ID          string          `json:"id"`
	CLI         CLI             `json:"cli"`
	Kind        Kind            `json:"kind"`
	Name        string          `json:"name"`
	Entry       string          `json:"entry"`
	Description string          `json:"description"`
	Owner       string          `json:"owner"`
	Path        string          `json:"path"`
	File        string          `json:"file"`
	Removable   bool            `json:"removable"`
	Scope       Scope           `json:"scope"`
	Project     *string         `json:"project"`
	InOther     bool            `json:"inOther"`
	Override    json.RawMessage `json:"override,omitempty"`
	Key         string          `json:"key"`
	Cells       *Cells          `json:"cells,omitempty"`
}

// MarshalJSON adds key, and override when HasSkillOverride (null when the value is nil).
func (i Item) MarshalJSON() ([]byte, error) {
	w := itemWire{i.ID, i.CLI, i.Kind, i.Name, i.Entry, i.Description, i.Owner, i.Path, i.File, i.Removable, i.Scope, i.Project, i.InOther, nil, i.Key(), i.Cells}
	if i.HasSkillOverride {
		w.Override = json.RawMessage("null")
		if i.SkillOverride != nil {
			text, err := json.Marshal(*i.SkillOverride)
			if err != nil {
				return nil, err
			}
			w.Override = text
		}
	}
	return json.Marshal(w)
}

// UnmarshalJSON is the inverse: a present override member (null or not) sets HasSkillOverride.
func (i *Item) UnmarshalJSON(data []byte) error {
	var w itemWire
	if err := json.Unmarshal(data, &w); err != nil {
		return err
	}
	*i = Item{ID: w.ID, CLI: w.CLI, Kind: w.Kind, Name: w.Name, Entry: w.Entry, Description: w.Description, Owner: w.Owner,
		Path: w.Path, File: w.File, Removable: w.Removable, Scope: w.Scope, Project: w.Project, InOther: w.InOther, Cells: w.Cells}
	if len(w.Override) > 0 {
		i.HasSkillOverride = true
		return json.Unmarshal(w.Override, &i.SkillOverride)
	}
	return nil
}

// hookWire is Hook as written: kind is always "hook" and key is computed.
type hookWire struct {
	ID        string     `json:"id"`
	CLI       CLI        `json:"cli"`
	Kind      Kind       `json:"kind"`
	Event     string     `json:"event"`
	Matcher   *string    `json:"matcher"`
	Command   string     `json:"command"`
	Timeout   *float64   `json:"timeout"`
	Async     bool       `json:"async"`
	Owner     string     `json:"owner"`
	Removable bool       `json:"removable"`
	Dead      bool       `json:"dead"`
	Paths     []string   `json:"paths"`
	Hash      string     `json:"hash"`
	File      string     `json:"file"`
	Scope     Scope      `json:"scope"`
	Project   *string    `json:"project"`
	Key       string     `json:"key"`
	Cells     *Cells     `json:"cells,omitempty"`
	Usage     *HookUsage `json:"usage"`
}

// MarshalJSON adds kind and key.
func (h Hook) MarshalJSON() ([]byte, error) {
	paths := h.Paths
	if paths == nil {
		paths = []string{}
	}
	return json.Marshal(hookWire{h.ID, h.CLI, KindHook, h.Event, h.Matcher, h.Command, h.Timeout, h.Async, h.Owner, h.Removable,
		h.Dead, paths, h.Hash, h.File, h.Scope, h.Project, h.Key(), h.Cells, h.Usage})
}

// UnmarshalJSON is the inverse; kind and key are derived, not stored.
func (h *Hook) UnmarshalJSON(data []byte) error {
	var w hookWire
	if err := json.Unmarshal(data, &w); err != nil {
		return err
	}
	*h = Hook{ID: w.ID, CLI: w.CLI, Event: w.Event, Matcher: w.Matcher, Command: w.Command, Timeout: w.Timeout, Async: w.Async,
		Owner: w.Owner, Removable: w.Removable, Dead: w.Dead, Paths: w.Paths, Hash: w.Hash, File: w.File, Scope: w.Scope,
		Project: w.Project, Cells: w.Cells, Usage: w.Usage}
	return nil
}
