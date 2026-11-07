package inventory

import (
	"context"
	"sync"
	"time"

	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/usage"
)

// UsageState is where loadout.rows finds the usage state of the process. *usage.Scanner implements it.
type UsageState interface {
	// Last is the result of the last scan that finished in this process.
	Last() (usage.Result, bool)
}

// Service holds the inventory methods (inventory.read, loadout.rows) and the process's list of discovered
// projects. A later wiring step registers its methods.
type Service struct {
	roots roots.Roots
	usage UsageState
	// Now is the clock; tests set it.
	Now func() time.Time

	mu       sync.Mutex
	projects []string
}

// NewService returns a service over the roots. state may be nil, then loadout.rows always reports scanning.
func NewService(r roots.Roots, state UsageState) *Service {
	return &Service{roots: r, usage: state, Now: time.Now}
}

// Read is inventory.read: the installed skills, agents and hooks, no cells, hook usage null. It refreshes the
// discovered-project list. Unreadable files become Problems, never errors; the only error is the context's,
// looked at between the CLIs, plugins and projects.
func (s *Service) Read(ctx context.Context) (Snapshot, error) {
	if err := ctx.Err(); err != nil {
		return Snapshot{}, err
	}
	snapshot, projects, err := read(ctx, s.roots)
	if err != nil {
		return Snapshot{}, err
	}
	s.mu.Lock()
	s.projects = projects
	s.mu.Unlock()
	return snapshot, nil
}

// Rows is loadout.rows: Read with the stored usage state attached, or "scanning" and pending cells when no
// scan has finished in this process.
func (s *Service) Rows(ctx context.Context) (LoadoutRows, error) {
	snapshot, err := s.Read(ctx)
	if err != nil {
		return LoadoutRows{}, err
	}
	in := usage.Scanning
	if s.usage != nil {
		if result, ok := s.usage.Last(); ok {
			in = usage.Ready(result)
		}
	}
	return BuildLoadoutRows(snapshot, in, s.Now()), nil
}

// Projects is the project list of this process. Discovery runs once if it is empty; Read refreshes it.
func (s *Service) Projects(ctx context.Context) ([]string, error) {
	s.mu.Lock()
	known := s.projects
	s.mu.Unlock()
	if len(known) == 0 {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		known = discoverProjects(ctx, s.roots)
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		s.mu.Lock()
		s.projects = known
		s.mu.Unlock()
	}
	return append([]string(nil), known...), nil
}

// Known is the project list as it stands, without running discovery: what the last Read or RefreshProjects found.
// It lets the entry point hand the list of an inventory read to the rules service (rules.SetProjects).
func (s *Service) Known() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.projects...)
}

// RefreshProjects runs project discovery again and stores the list. It is the refresh rules.snapshot asks for with
// refreshProjects, without the rest of Read.
func (s *Service) RefreshProjects(ctx context.Context) ([]string, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	found := discoverProjects(ctx, s.roots)
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	s.mu.Lock()
	s.projects = found
	s.mu.Unlock()
	return append([]string(nil), found...), nil
}
