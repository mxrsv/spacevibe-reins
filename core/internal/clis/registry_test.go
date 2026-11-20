package clis

import (
	"errors"
	"slices"
	"testing"
)

func TestRegistryIDsAreUniqueAndLabelled(t *testing.T) {
	seen := map[ID]bool{}
	for _, d := range All() {
		if seen[d.ID] {
			t.Errorf("%s is listed twice", d.ID)
		}
		seen[d.ID] = true
		if d.Label == "" || d.Layout.Folder == "" {
			t.Errorf("%s has no label or folder", d.ID)
		}
	}
}

// The wire order is the order every report lists CLIs in; reordering the registry changes the goldens.
func TestWireOrder(t *testing.T) {
	var ids []ID
	for _, d := range All() {
		ids = append(ids, d.ID)
	}
	if want := []ID{Claude, Codex, Gemini}; !slices.Equal(ids, want) {
		t.Fatalf("order = %v, want %v", ids, want)
	}
	if got := IDsWith(Inventory); !slices.Equal(got, []ID{Claude, Codex}) {
		t.Fatalf("inventory CLIs = %v", got)
	}
	if got := IDsWith(Limits); !slices.Equal(got, []ID{Claude, Codex, Gemini}) {
		t.Fatalf("limits CLIs = %v", got)
	}
}

func TestLookupAndRequire(t *testing.T) {
	if _, err := Lookup("nope"); !errors.Is(err, ErrUnknownCLI) {
		t.Fatalf("Lookup(nope) = %v, want ErrUnknownCLI", err)
	}
	if _, err := Require(Gemini, Inventory); !errors.Is(err, ErrConceptAbsent) {
		t.Fatalf("Require(gemini, inventory) = %v, want ErrConceptAbsent", err)
	}
	if _, err := Require("nope", Inventory); !errors.Is(err, ErrUnknownCLI) {
		t.Fatalf("Require(nope, inventory) = %v, want ErrUnknownCLI", err)
	}
	if d, err := Require(Codex, Mutate); err != nil || d.Label != "Codex" {
		t.Fatalf("Require(codex, mutate) = %+v, %v", d, err)
	}
}

func TestAdaptersNeverFallBack(t *testing.T) {
	table := NewAdapters(Limits, map[ID]string{Claude: "claude", Codex: "codex"})
	if err := table.Check(); err == nil {
		t.Fatal("Check passed with gemini's limits adapter missing")
	}
	if _, err := table.For(Gemini); !errors.Is(err, ErrConceptAbsent) {
		t.Fatalf("For(gemini) = %v, want ErrConceptAbsent", err)
	}
	if _, err := table.For("nope"); !errors.Is(err, ErrUnknownCLI) {
		t.Fatalf("For(nope) = %v, want ErrUnknownCLI", err)
	}
	if got := table.InOrder(); len(got) != 2 || got[0].ID != Claude || got[1].ID != Codex {
		t.Fatalf("InOrder = %+v", got)
	}
	extra := NewAdapters(Inventory, map[ID]string{Claude: "", Codex: "", Gemini: ""})
	if err := extra.Check(); err == nil {
		t.Fatal("Check passed with an adapter for a CLI that has no inventory")
	}
}
