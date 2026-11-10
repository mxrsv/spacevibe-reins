package rules

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"unicode"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
)

// maxJSONBytes is the largest settings file read (InventoryFileIO.maxJSONBytes).
const maxJSONBytes = 16 << 20

// Fixed sentences of the store. Those with a file name are scrubbed by Service.
const (
	needAbsoluteMessage    = "A project scope needs an absolute folder."
	unknownProjectMessage  = "That project is not known to SpaceVibe."
	projectGoneMessage     = "That project folder does not exist."
	alreadyThatVerdictText = "The rule already has that verdict."
	ruleChangedMessage     = "This rule has already changed. Refresh the list."
	nothingToChangeMessage = "Nothing to change: the file already holds that."
	notNothingChanged      = " Nothing was changed."
	noRulesPickedMessage   = "Pick at least one rule to change."
)

// Store reads and writes the permission rules of Claude Code settings files. Behavior reference: Node rules
// (git b58269d). Differences from Node, on purpose:
//   - A project folder must be one that project discovery found (404 otherwise). In Node this check sits in the IPC
//     layer; here it is in the engine so no caller can make SpaceVibe create <any folder>/.claude/settings.json.
//   - The file is edited in place (only the changed list), not rewritten.
//   - A project or local file must really live in <project>/.claude: a .claude that resolves elsewhere, or a settings
//     file that is itself a link, is refused (409), because a hostile repo could point it at any other JSON file. The
//     global file may be a link (a dotfiles setup) and is followed.
type Store struct {
	roots    roots.Roots
	discover func() []string

	// ctx is the request's context; a write looks at it again as the first step inside the write lock, so a request
	// that was cancelled while it waited for the lock changes nothing. Nil means never cancelled.
	ctx context.Context
	// beforeLockedRead runs inside the write lock before the file is read. Tests only: it stands in for a writer that
	// never takes our lock.
	beforeLockedRead func()
}

// NewStore returns a store over the roots. projects lists the folders a project scope may name; nil means
// inventory.DiscoverProjects, which reads log heads, so a caller that lists and writes in quick succession passes a
// cached list.
func NewStore(r roots.Roots, projects func() []string) *Store {
	if projects == nil {
		projects = func() []string { return inventory.DiscoverProjects(r) }
	}
	return &Store{roots: r, discover: projects}
}

// folderState is what is known about the folder that holds a scope's file.
type folderState int

const (
	folderReadable folderState = iota
	// folderGone: the project folder does not exist (deleted since discovery).
	folderGone
	// folderUnreadable: the folder cannot be looked at (a privacy denial, no permission): it may well exist (G-fix.1).
	folderUnreadable
)

// locate is the settings file of a scope and what is known about its project folder. It refuses a relative folder
// (400) and a folder discovery did not find (404); a folder that is gone or cannot be looked at is reported in the
// state, so a read can say so without aborting.
func (s *Store) locate(scope Scope) (string, folderState, error) {
	var name string
	switch scope.Kind {
	case KindGlobal:
		return s.roots.Claude.HookFile, folderReadable, nil
	case KindProject:
		name = "settings.json"
	case KindLocal:
		name = "settings.local.json"
	default:
		return "", folderReadable, coreerr.New("That scope is not known.")
	}
	if !strings.HasPrefix(scope.Dir, "/") {
		return "", folderReadable, coreerr.New(needAbsoluteMessage)
	}
	known := normalize(scope.Dir)
	if !slices.Contains(s.discover(), known) {
		return "", folderReadable, coreerr.NewStatus(unknownProjectMessage, coreerr.StatusNotFound)
	}
	file := join(known, ".claude", name)
	switch fsx.PathPresence(known) {
	case fsx.Missing:
		return file, folderGone, nil
	case fsx.Unknown:
		return file, folderUnreadable, nil
	}
	if info, err := os.Stat(known); err != nil || !info.IsDir() {
		return file, folderGone, nil
	}
	return file, folderReadable, nil
}

// File is the settings file of a scope, for a caller that is going to use it. A project folder that is gone is a 404
// and one that cannot be looked at is a 409 that names the file.
func (s *Store) File(scope Scope) (string, error) {
	file, state, err := s.locate(scope)
	if err != nil {
		return "", err
	}
	switch state {
	case folderGone:
		return "", coreerr.NewStatus(projectGoneMessage, coreerr.StatusNotFound)
	case folderUnreadable:
		return "", coreerr.NewStatus(file+" is not readable, so SpaceVibe left it alone.", coreerr.StatusConflict)
	}
	return file, nil
}

// requireInsideProject refuses a project or local settings file that is not really inside <project>/.claude. The
// global file is exempt. The messages name the absolute folder, as in Swift (scrub only replaces the settings file).
func requireInsideProject(file string, scope Scope) error {
	if scope.Kind == KindGlobal {
		return nil
	}
	claudeDir := filepath.Dir(file)
	expected := roots.ResolvedPath(filepath.Dir(claudeDir)) + "/.claude"
	if _, err := os.Lstat(claudeDir); err == nil {
		if _, err := filepath.EvalSymlinks(claudeDir); err != nil {
			return coreerr.NewStatus(claudeDir+" is a link to nothing, so SpaceVibe left it alone.", coreerr.StatusConflict)
		}
		if roots.ResolvedPath(claudeDir) != expected {
			return coreerr.NewStatus(claudeDir+" points outside the project, so SpaceVibe left it alone.", coreerr.StatusConflict)
		}
	}
	if info, err := os.Lstat(file); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return coreerr.NewStatus(file+" is a link, so SpaceVibe left it alone. Edit the file it points at.", coreerr.StatusConflict)
	}
	return nil
}

// ListRules lists the rules of each scope, in the order given, verdicts allow, ask, deny. A file that is not valid
// settings is reported in Problems and contributes no rules; a missing file contributes nothing. A file or project
// folder that cannot be looked at is a problem too, with NotReadable set, never "no rules" (G-fix.1). A project folder
// that is gone is a 404 when it is the only scope asked for, and a problem line when it is one of several, so it does
// not hide the other scopes.
func (s *Store) ListRules(scopes ...Scope) (Listing, error) {
	if len(scopes) == 0 {
		scopes = []Scope{Global}
	}
	out := Listing{Rules: []Rule{}, Problems: []string{}}
	for _, scope := range scopes {
		file, state, err := s.locate(scope)
		if err != nil {
			return Listing{}, err
		}
		switch state {
		case folderGone:
			if len(scopes) == 1 {
				return Listing{}, coreerr.NewStatus(projectGoneMessage, coreerr.StatusNotFound)
			}
			out.Problems = append(out.Problems, projectGoneMessage)
			continue
		case folderUnreadable:
			out.Problems = append(out.Problems, file+notReadableSentence)
			out.NotReadable = true
			continue
		}
		if err := requireInsideProject(file, scope); err != nil {
			if e, ok := coreerr.As(err); ok {
				out.Problems = append(out.Problems, e.Message)
				continue
			}
			return Listing{}, err
		}
		switch fsx.PathPresence(file) {
		case fsx.Missing:
			continue
		case fsx.Unknown:
			out.Problems = append(out.Problems, file+notReadableSentence)
			out.NotReadable = true
			continue
		}
		data, err := fsx.ReadRegular(file, maxJSONBytes)
		if err != nil {
			out.Problems = append(out.Problems, file+" could not be read.")
			out.NotReadable = true
			continue
		}
		text := textjs.Repair(string(data))
		if isBlank(text) {
			continue
		}
		doc, err := mutate.ParseObject(text, file)
		var permissions ojson.Value
		var present bool
		if err == nil {
			permissions, present, err = permissionsOf(doc.Root(), file)
		}
		if err != nil {
			e, ok := coreerr.As(err)
			if !ok {
				return Listing{}, err
			}
			out.Problems = append(out.Problems, strings.ReplaceAll(e.Message, notNothingChanged, ""))
			continue
		}
		for _, verdict := range Verdicts {
			for _, rule := range rulesOf(permissions, present, verdict) {
				out.Rules = append(out.Rules, newRule(scope, file, verdict, rule))
			}
		}
	}
	return out, nil
}

// notReadableSentence ends the problem of a settings file or project folder that cannot be looked at.
const notReadableSentence = " is not readable, so SpaceVibe cannot tell what rules it holds."

// AddRule adds rule under verdict. It refuses (409) a rule that is already in the file under any verdict.
func (s *Store) AddRule(scope Scope, verdict Verdict, rule string) (mutate.Entry, error) {
	if err := checkVerdict(verdict); err != nil {
		return mutate.Entry{}, err
	}
	text, err := checkedRule(rule)
	if err != nil {
		return mutate.Entry{}, err
	}
	label := "Added " + string(verdict) + " rule " + text + " (" + scope.journalLabel() + ")"
	return s.required(s.edit(scope, label, func(file string, doc *ojson.Document) (*ojson.Document, error) {
		permissions, present, err := permissionsOf(doc.Root(), file)
		if err != nil {
			return nil, err
		}
		if at, found := verdictHolding(permissions, present, text); found {
			return nil, coreerr.NewStatus(text+" is already in "+string(at)+". Change its verdict instead.", coreerr.StatusConflict)
		}
		return editRules(doc, file, nil, []VerdictRule{{verdict, text}})
	}))
}

// RemoveRule removes rule from verdict. It refuses (409) when the file no longer has it there.
func (s *Store) RemoveRule(scope Scope, verdict Verdict, rule string) (mutate.Entry, error) {
	if err := checkVerdict(verdict); err != nil {
		return mutate.Entry{}, err
	}
	label := "Removed " + string(verdict) + " rule " + rule + " (" + scope.journalLabel() + ")"
	return s.required(s.edit(scope, label, func(file string, doc *ojson.Document) (*ojson.Document, error) {
		if err := requireRule(rule, verdict, doc, file); err != nil {
			return nil, err
		}
		return editRules(doc, file, []VerdictRule{{verdict, rule}}, nil)
	}))
}

// ChangeVerdict moves rule from one verdict to another.
func (s *Store) ChangeVerdict(scope Scope, rule string, from, to Verdict) (mutate.Entry, error) {
	if err := checkVerdict(from); err != nil {
		return mutate.Entry{}, err
	}
	if err := checkVerdict(to); err != nil {
		return mutate.Entry{}, err
	}
	if from == to {
		return mutate.Entry{}, coreerr.New(alreadyThatVerdictText)
	}
	label := "Changed " + rule + " from " + string(from) + " to " + string(to) + " (" + scope.journalLabel() + ")"
	return s.required(s.edit(scope, label, func(file string, doc *ojson.Document) (*ojson.Document, error) {
		if err := requireRule(rule, from, doc, file); err != nil {
			return nil, err
		}
		return editRules(doc, file, []VerdictRule{{from, rule}}, []VerdictRule{{to, rule}})
	}))
}

// RuleMove is one rule of a bulk change and the verdict the caller saw it under.
type RuleMove struct {
	Rule string  `json:"rule"`
	From Verdict `json:"from"`
}

// ChangeVerdicts moves every listed rule to one verdict in a single write: one file edit, one backup, one journal
// entry, so one Undo restores them all. It refuses (400) an empty list, a bad verdict or a rule whose from equals to,
// and (409, nothing written) when any rule is no longer under its from.
func (s *Store) ChangeVerdicts(scope Scope, to Verdict, moves []RuleMove) (mutate.Entry, error) {
	if err := checkVerdict(to); err != nil {
		return mutate.Entry{}, err
	}
	if len(moves) == 0 {
		return mutate.Entry{}, coreerr.New(noRulesPickedMessage)
	}
	var remove, add []VerdictRule
	for _, m := range moves {
		if err := checkVerdict(m.From); err != nil {
			return mutate.Entry{}, err
		}
		if m.From == to {
			return mutate.Entry{}, coreerr.New(alreadyThatVerdictText)
		}
		remove = append(remove, VerdictRule{m.From, m.Rule})
		add = append(add, VerdictRule{to, m.Rule})
	}
	noun := " rules"
	if len(moves) == 1 {
		noun = " rule"
	}
	label := "Changed " + strconv.Itoa(len(moves)) + noun + " to " + string(to) + " (" + scope.journalLabel() + ")"
	return s.required(s.edit(scope, label, func(file string, doc *ojson.Document) (*ojson.Document, error) {
		for _, m := range moves {
			if err := requireRule(m.Rule, m.From, doc, file); err != nil {
				return nil, err
			}
		}
		return editRules(doc, file, remove, add)
	}))
}

func checkVerdict(v Verdict) error {
	if v.Valid() {
		return nil
	}
	return coreerr.New("The verdict must be allow, ask or deny.")
}

func requireRule(rule string, verdict Verdict, doc *ojson.Document, file string) error {
	permissions, present, err := permissionsOf(doc.Root(), file)
	if err != nil {
		return err
	}
	for _, r := range rulesOf(permissions, present, verdict) {
		if r == rule {
			return nil
		}
	}
	return coreerr.NewStatus(ruleChangedMessage, coreerr.StatusConflict)
}

// edit is one write of a scope's settings file, under the write lock taken once. The refusals come in this order: the
// scope (400, 404), the folder (409), a link out of the project (409), the journal (409), the file (409), the change.
func (s *Store) edit(scope Scope, label string, change func(file string, doc *ojson.Document) (*ojson.Document, error)) (*mutate.Entry, error) {
	var entry *mutate.Entry
	ctx := s.ctx
	if ctx == nil {
		ctx = context.Background()
	}
	err := mutate.WithLockContext(ctx, s.roots, func(tx *mutate.Tx) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		file, err := s.File(scope)
		if err != nil {
			return err
		}
		if err := requireInsideProject(file, scope); err != nil {
			return err
		}
		if s.beforeLockedRead != nil {
			s.beforeLockedRead()
		}
		entry, err = tx.EditJSON(file, label, nil, func(doc *ojson.Document) (*ojson.Document, error) { return change(file, doc) })
		return err
	})
	return entry, err
}

// required turns "nothing changed" into the 409 of add, remove and change verdict.
func (s *Store) required(entry *mutate.Entry, err error) (mutate.Entry, error) {
	if err != nil {
		return mutate.Entry{}, err
	}
	if entry == nil {
		return mutate.Entry{}, coreerr.NewStatus(nothingToChangeMessage, coreerr.StatusConflict)
	}
	return *entry, nil
}

// isBlank is Swift's text.allSatisfy(\.isWhitespace): nothing but spaces and line breaks (and the empty text).
func isBlank(text string) bool { return strings.TrimFunc(text, unicode.IsSpace) == "" }

// readCapped reads at most max bytes of a regular file, without blocking on a FIFO. A longer file is cut and
// truncated is true, so the caller can say the result is partial instead of reporting it as complete.
func readCapped(path string, max int64) (data []byte, truncated bool, err error) {
	f, err := fsx.OpenRegular(path)
	if err != nil {
		return nil, false, err
	}
	defer f.Close()
	data, err = io.ReadAll(io.LimitReader(f, max+1))
	if err != nil {
		return nil, false, err
	}
	if int64(len(data)) > max {
		return data[:max], true, nil
	}
	return data, false, nil
}

// join is NSString's appendingPathComponent: single slashes, nothing cleaned.
func join(base string, parts ...string) string {
	for _, p := range parts {
		base = strings.TrimRight(base, "/") + "/" + p
	}
	return base
}

// normalize is path.resolve for an absolute path: "." and ".." folded, no trailing slash. Symlinks are not followed.
func normalize(path string) string {
	var stack []string
	for _, part := range strings.Split(path, "/") {
		switch part {
		case "", ".":
		case "..":
			if len(stack) > 0 {
				stack = stack[:len(stack)-1]
			}
		default:
			stack = append(stack, part)
		}
	}
	return "/" + strings.Join(stack, "/")
}

// pathPresent is true only when the path is there.
func pathPresent(path string) bool { return fsx.PathPresence(path) == fsx.Present }
