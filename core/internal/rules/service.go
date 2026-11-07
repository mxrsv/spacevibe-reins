package rules

import (
	"context"
	"slices"
	"strings"
	"sync"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/roots"
)

// Service holds the seven rules.* RPC methods: snapshot, preview, setCapability, add, remove, changeVerdict and check
// (docs/internals/core-protocol.md). A later wiring step registers them.
//
// It keeps the project list of the process: rules.snapshot with refreshProjects refreshes it, every other call reuses
// it, and discovery runs once if it is empty. A project folder outside the list is 404, so no caller can make the core
// create <any folder>/.claude/settings.json. Every message and problem has the settings file's absolute path replaced
// by the scope's label (RulesScopes.scrub), because the shell must not see paths.
//
// A write is short and ends in a journal entry, so ctx is looked at twice and never in between: before the write lock
// is taken and again as the first step inside it (Store.edit), so a request cancelled while it queued changes nothing.
type Service struct {
	roots roots.Roots

	// Discover lists the projects; the default is project discovery of the inventory package. Tests replace it.
	Discover func(ctx context.Context) ([]string, error)

	mu       sync.Mutex
	projects []string
}

// NewService returns a service over the roots.
func NewService(r roots.Roots) *Service {
	s := &Service{roots: r}
	s.Discover = func(ctx context.Context) ([]string, error) { return inventory.NewService(r, nil).Projects(ctx) }
	return s
}

// SetProjects stores a project list found elsewhere (inventory.read), so both methods share one list.
func (s *Service) SetProjects(dirs []string) {
	s.mu.Lock()
	s.projects = append([]string(nil), dirs...)
	s.mu.Unlock()
}

// projectList is the process's list; refresh (or an empty list) runs discovery.
func (s *Service) projectList(ctx context.Context, refresh bool) ([]string, error) {
	s.mu.Lock()
	known := s.projects
	s.mu.Unlock()
	if refresh || len(known) == 0 {
		found, err := s.Discover(ctx)
		if err != nil {
			return nil, err
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		s.SetProjects(found)
		known = found
	}
	return append([]string{}, known...), nil
}

func (s *Service) store(ctx context.Context) (*Store, error) {
	dirs, err := s.projectList(ctx, false)
	if err != nil {
		return nil, err
	}
	store := NewStore(s.roots, func() []string { return dirs })
	store.ctx = ctx
	return store, nil
}

// Params of the methods. Enum members arrive as text; each is checked here, never defaulted.
type (
	// SnapshotParams is rules.snapshot. Dir is null for the global scope, absolute otherwise.
	SnapshotParams struct {
		Scope           ScopeKind `json:"scope"`
		Dir             *string   `json:"dir"`
		RefreshProjects bool      `json:"refreshProjects"`
	}
	// CapabilityParams is rules.preview and rules.setCapability.
	CapabilityParams struct {
		Scope      ScopeKind  `json:"scope"`
		Dir        *string    `json:"dir"`
		Capability Capability `json:"capability"`
		Verdict    Verdict    `json:"verdict"`
	}
	// RuleParams is rules.add and rules.remove.
	RuleParams struct {
		Scope   ScopeKind `json:"scope"`
		Dir     *string   `json:"dir"`
		Verdict Verdict   `json:"verdict"`
		Rule    string    `json:"rule"`
	}
	// ChangeParams is rules.changeVerdict.
	ChangeParams struct {
		Scope ScopeKind `json:"scope"`
		Dir   *string   `json:"dir"`
		Rule  string    `json:"rule"`
		From  Verdict   `json:"from"`
		To    Verdict   `json:"to"`
	}
	// CheckParams is rules.check.
	CheckParams struct {
		Rule string `json:"rule"`
	}
)

// SetCapabilityResult is the result of rules.setCapability. Entry is null when the file already holds that.
type SetCapabilityResult struct {
	Entry *mutate.EntryRef `json:"entry"`
}

// CheckResult is the result of rules.check: Message is the sentence a write would refuse with, null when valid.
type CheckResult struct {
	Valid   bool    `json:"valid"`
	Message *string `json:"message"`
}

// Snapshot is everything the Rules screen shows for one scope (RulesSnapshot.swift), minus UI-only fields.
type Snapshot struct {
	// ProjectDirs are the discovered projects.
	ProjectDirs []string `json:"projectDirs"`
	// GlobalRuleCount is the rule count of the global file: the sidebar badge.
	GlobalRuleCount int `json:"globalRuleCount"`
	// Scope and Dir are the selection that was actually read: global when the asked project is not listed.
	Scope ScopeKind `json:"scope"`
	Dir   *string   `json:"dir"`
	// FileLabel is the short name of the scope's file.
	FileLabel string `json:"fileLabel"`
	// Exists is false when the scope's file does not exist yet: the first rule creates it. It is not "unknown":
	// see NotReadable.
	Exists bool `json:"exists"`
	// Problems are sentences about files that are not valid settings or cannot be read, with the path replaced by FileLabel.
	Problems []string         `json:"problems"`
	Rules    []Rule           `json:"rules"`
	Grid     []Cell           `json:"grid"`
	Codex    CodexPermissions `json:"codex"`

	// NotReadable is true when the scope's file or project folder cannot be looked at, so Rules and Grid are unknown,
	// not empty, and the scope is not editable (G-fix.1). New; the Swift screen has no such state.
	NotReadable bool `json:"notReadable"`
	// GlobalNotReadable is the same for the global file, which GlobalRuleCount counts (G-fix.1). New.
	GlobalNotReadable bool `json:"globalNotReadable"`
}

// scopeOf checks the scope params. A global scope takes no folder; a project or local scope takes an absolute one.
func scopeOf(kind ScopeKind, dir *string) (Scope, error) {
	switch kind {
	case KindGlobal:
		if dir != nil && *dir != "" {
			return Scope{}, coreerr.New("A global scope takes no folder.")
		}
		return Global, nil
	case KindProject, KindLocal:
		if dir == nil || !strings.HasPrefix(*dir, "/") {
			return Scope{}, coreerr.New(needAbsoluteMessage)
		}
		return Scope{Kind: kind, Dir: *dir}, nil
	}
	return Scope{}, coreerr.New("The scope must be global, project or local.")
}

func verdictOf(v Verdict, what string) error {
	if v.Valid() {
		return nil
	}
	return coreerr.New("The " + what + " must be allow, ask or deny.")
}

func capabilityOf(c Capability) error {
	if c.Valid() {
		return nil
	}
	return coreerr.New("The capability must be read, edit, run, network, push or secrets.")
}

// scrub replaces the settings file's absolute path (and its link-resolved spelling) by the scope's label.
func scrub(text, path, label string) string {
	out := strings.ReplaceAll(text, path, label)
	if resolved := roots.ResolvedPath(path); resolved != path {
		out = strings.ReplaceAll(out, resolved, label)
	}
	return out
}

// scrubbed returns err with the settings file's path replaced by the scope's label, status kept. An error that is not
// a coreerr is returned as it is.
func (s *Service) scrubbed(store *Store, scope Scope, err error) error {
	if err == nil {
		return nil
	}
	e, ok := coreerr.As(err)
	if !ok {
		return err
	}
	file, _, locErr := store.locate(scope)
	if locErr != nil {
		return e
	}
	return coreerr.NewStatus(scrub(e.Message, file, scope.FileLabel()), e.Status)
}

// Snapshot is rules.snapshot.
func (s *Service) Snapshot(ctx context.Context, p SnapshotParams) (Snapshot, error) {
	if err := ctx.Err(); err != nil {
		return Snapshot{}, err
	}
	asked, err := scopeOf(p.Scope, p.Dir)
	if err != nil {
		return Snapshot{}, err
	}
	dirs, err := s.projectList(ctx, p.RefreshProjects)
	if err != nil {
		return Snapshot{}, err
	}
	store := NewStore(s.roots, func() []string { return dirs })
	scope := asked
	if scope.Kind != KindGlobal && !slices.Contains(dirs, scope.Dir) {
		scope = Global
	}
	global, err := store.ListRules(Global)
	if err != nil {
		return Snapshot{}, s.scrubbed(store, Global, err)
	}
	listing := global
	if scope.Kind != KindGlobal {
		if listing, err = store.ListRules(scope); err != nil {
			return Snapshot{}, s.scrubbed(store, scope, err)
		}
	}
	file, _, err := store.locate(scope)
	if err != nil {
		return Snapshot{}, s.scrubbed(store, scope, err)
	}
	problems := make([]string, len(listing.Problems))
	for i, problem := range listing.Problems {
		problems[i] = scrub(problem, file, scope.FileLabel())
	}
	out := Snapshot{
		ProjectDirs: dirs, GlobalRuleCount: len(global.Rules), Scope: scope.Kind, FileLabel: scope.FileLabel(),
		Exists: pathPresent(file), Problems: problems, Rules: listing.Rules, Grid: CapabilityGrid(listing.Rules),
		Codex: ReadCodexPermissions(s.roots), NotReadable: listing.NotReadable, GlobalNotReadable: global.NotReadable,
	}
	if scope.Kind != KindGlobal {
		dir := scope.Dir
		out.Dir = &dir
	}
	return out, nil
}

// Preview is rules.preview: what a cell write would remove and write. It writes nothing.
func (s *Service) Preview(ctx context.Context, p CapabilityParams) (Preview, error) {
	scope, store, err := s.begin(ctx, p.Scope, p.Dir)
	if err != nil {
		return Preview{}, err
	}
	if err := capabilityOf(p.Capability); err != nil {
		return Preview{}, err
	}
	if err := verdictOf(p.Verdict, "verdict"); err != nil {
		return Preview{}, err
	}
	preview, err := store.PreviewSetCapability(scope, p.Capability, p.Verdict)
	return preview, s.scrubbed(store, scope, err)
}

// SetCapability is rules.setCapability. The entry is null when the file already holds exactly that; the shell turns
// that into its "Nothing to change" sentence.
func (s *Service) SetCapability(ctx context.Context, p CapabilityParams) (SetCapabilityResult, error) {
	scope, store, err := s.begin(ctx, p.Scope, p.Dir)
	if err != nil {
		return SetCapabilityResult{}, err
	}
	if err := capabilityOf(p.Capability); err != nil {
		return SetCapabilityResult{}, err
	}
	if err := verdictOf(p.Verdict, "verdict"); err != nil {
		return SetCapabilityResult{}, err
	}
	entry, err := store.SetCapability(scope, p.Capability, p.Verdict)
	if err != nil {
		return SetCapabilityResult{}, s.scrubbed(store, scope, err)
	}
	if entry == nil {
		return SetCapabilityResult{}, nil
	}
	ref := entry.Ref()
	return SetCapabilityResult{Entry: &ref}, nil
}

// Add is rules.add.
func (s *Service) Add(ctx context.Context, p RuleParams) (mutate.EntryResult, error) {
	scope, store, err := s.begin(ctx, p.Scope, p.Dir)
	if err != nil {
		return mutate.EntryResult{}, err
	}
	if err := verdictOf(p.Verdict, "verdict"); err != nil {
		return mutate.EntryResult{}, err
	}
	entry, err := store.AddRule(scope, p.Verdict, p.Rule)
	return resultOf(entry), s.scrubbed(store, scope, err)
}

// Remove is rules.remove.
func (s *Service) Remove(ctx context.Context, p RuleParams) (mutate.EntryResult, error) {
	scope, store, err := s.begin(ctx, p.Scope, p.Dir)
	if err != nil {
		return mutate.EntryResult{}, err
	}
	if err := verdictOf(p.Verdict, "verdict"); err != nil {
		return mutate.EntryResult{}, err
	}
	entry, err := store.RemoveRule(scope, p.Verdict, p.Rule)
	return resultOf(entry), s.scrubbed(store, scope, err)
}

// ChangeVerdict is rules.changeVerdict.
func (s *Service) ChangeVerdict(ctx context.Context, p ChangeParams) (mutate.EntryResult, error) {
	scope, store, err := s.begin(ctx, p.Scope, p.Dir)
	if err != nil {
		return mutate.EntryResult{}, err
	}
	if err := verdictOf(p.From, "from verdict"); err != nil {
		return mutate.EntryResult{}, err
	}
	if err := verdictOf(p.To, "to verdict"); err != nil {
		return mutate.EntryResult{}, err
	}
	entry, err := store.ChangeVerdict(scope, p.Rule, p.From, p.To)
	return resultOf(entry), s.scrubbed(store, scope, err)
}

// Check is rules.check: the live check before a write. It is advice; the write checks again.
func (s *Service) Check(ctx context.Context, p CheckParams) (CheckResult, error) {
	if err := ctx.Err(); err != nil {
		return CheckResult{}, err
	}
	if message := Check(p.Rule); message != "" {
		return CheckResult{Message: &message}, nil
	}
	return CheckResult{Valid: true}, nil
}

// begin is what every scoped method does first: look at ctx, check the scope params, take the project list.
func (s *Service) begin(ctx context.Context, kind ScopeKind, dir *string) (Scope, *Store, error) {
	if err := ctx.Err(); err != nil {
		return Scope{}, nil, err
	}
	scope, err := scopeOf(kind, dir)
	if err != nil {
		return Scope{}, nil, err
	}
	store, err := s.store(ctx)
	return scope, store, err
}

func resultOf(entry mutate.Entry) mutate.EntryResult { return mutate.EntryResult{Entry: entry.Ref()} }
