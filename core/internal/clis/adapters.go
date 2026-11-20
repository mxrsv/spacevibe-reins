package clis

import (
	"fmt"
	"slices"
	"strings"
)

// Adapters is one subsystem's table of per-CLI adapters for one concept. Each subsystem builds its table in one
// place, from an explicit map (no init-time self-registration), and looks adapters up through For. The table and
// the registry must agree: Check, run by each subsystem's tests, fails when a CLI lists the concept and has no
// adapter, or an adapter exists for a CLI that does not list the concept.
type Adapters[T any] struct {
	registry Registry
	concept  Concept
	byID     map[ID]T
}

// NewAdapters is the table of concept over the default registry, keyed by CLI id. The map is copied.
func NewAdapters[T any](concept Concept, byID map[ID]T) Adapters[T] {
	return NewAdaptersIn(Default(), concept, byID)
}

// NewAdaptersIn is NewAdapters over another registry. Only tests pass one other than Default: a registry with an
// extra CLI (Registry.Plus) and a table with that CLI's adapter.
func NewAdaptersIn[T any](registry Registry, concept Concept, byID map[ID]T) Adapters[T] {
	copied := make(map[ID]T, len(byID))
	for id, a := range byID {
		copied[id] = a
	}
	return Adapters[T]{registry: registry, concept: concept, byID: copied}
}

// For is the adapter of id. An id with no registry entry wraps ErrUnknownCLI; a CLI without the concept, or one the
// table lacks, wraps ErrConceptAbsent. It never falls back to another CLI's adapter.
func (a Adapters[T]) For(id ID) (T, error) {
	var zero T
	if _, err := a.registry.Require(id, a.concept); err != nil {
		return zero, err
	}
	adapter, ok := a.byID[id]
	if !ok {
		return zero, fmt.Errorf("%w: no %s adapter for %s", ErrConceptAbsent, a.concept, id)
	}
	return adapter, nil
}

// Bound is an adapter with the CLI it belongs to.
type Bound[T any] struct {
	ID      ID
	Adapter T
}

// InOrder lists the adapters of every CLI that takes part in the concept, in wire order. A CLI the table lacks is
// left out; Check reports it.
func (a Adapters[T]) InOrder() []Bound[T] {
	var out []Bound[T]
	for _, d := range a.registry.With(a.concept) {
		if adapter, ok := a.byID[d.ID]; ok {
			out = append(out, Bound[T]{ID: d.ID, Adapter: adapter})
		}
	}
	return out
}

// Check is nil when the table has exactly one adapter per CLI that lists the concept.
func (a Adapters[T]) Check() error {
	var problems []string
	for _, d := range a.registry.With(a.concept) {
		if _, ok := a.byID[d.ID]; !ok {
			problems = append(problems, string(d.ID)+" lists "+string(a.concept)+" but has no adapter")
		}
	}
	for id := range a.byID {
		if _, err := a.registry.Require(id, a.concept); err != nil {
			problems = append(problems, "adapter for "+string(id)+": "+err.Error())
		}
	}
	if len(problems) == 0 {
		return nil
	}
	slices.Sort(problems)
	return fmt.Errorf("%s adapters do not match the registry: %s", a.concept, strings.Join(problems, "; "))
}
