package rules

import (
	"strings"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/ojson"
)

// Writing a grid cell: replace the cell's rules in ONE settings file with canonical ones.
//
//	Read -> Read    Edit -> Edit    Run -> Bash    Network -> WebFetch + WebSearch
//	Push and deploy -> Bash(git push *) + Bash(vercel *)    Secrets -> Read(./.env) + Read(./.env.*)
//
// Which rules a write replaces: the cell's wide rules (Read, Edit, Run, Network) or its own rules (Push and deploy,
// Secrets). Narrow rules are never touched. A mixed cell is refused (RulesCapabilityWrite.swift).
//
// Secrets writes Read(./.env), which anchors at the working folder only, and Write(path) rules never match a Read cell.
// Both are as in Swift (an open owner item, SF 2): not changed here.
var (
	pushRules   = []string{"Bash(git push *)", "Bash(vercel *)"}
	secretRules = []string{"Read(./.env)", "Read(./.env.*)"}
)

func replacedRole(c Capability) role {
	switch c {
	case Push, Secrets:
		return roleOwn
	}
	return roleWide
}

func canonicalRules(c Capability) []string {
	switch c {
	case Read:
		return []string{"Read"}
	case Edit:
		return []string{"Edit"}
	case Run:
		return []string{"Bash"}
	case Network:
		return []string{"WebFetch", "WebSearch"}
	case Push:
		return pushRules
	}
	return secretRules
}

// plan is what a cell write would remove and write.
type plan struct {
	current, resulting State
	replaces, writes   []VerdictRule
}

// plan is the preview: validate, list the scope, plan on the listing. It reads without the write lock, so it only
// answers a question; SetCapability plans again from the locked document.
func (s *Store) plan(scope Scope, capability Capability, verdict Verdict) (plan, error) {
	if err := checkCapabilityWrite(capability, verdict); err != nil {
		return plan{}, err
	}
	listing, err := s.ListRules(scope)
	if err != nil {
		return plan{}, err
	}
	if len(listing.Problems) > 0 {
		problem := listing.Problems[0]
		// The problem ends with a period already; keep one.
		if !strings.HasSuffix(problem, ".") {
			problem += "."
		}
		return plan{}, coreerr.NewStatus(problem+notNothingChanged, coreerr.StatusConflict)
	}
	return planOn(listing.Rules, capability, verdict)
}

func checkCapabilityWrite(capability Capability, verdict Verdict) error {
	if !capability.Valid() {
		return coreerr.New("That capability is not known.")
	}
	return checkVerdict(verdict)
}

// planOn is the pure part of a plan: what writing the cell would remove and write, given the rules of the one file.
func planOn(rules []Rule, capability Capability, verdict Verdict) (plan, error) {
	cell := cellOf(CapabilityGrid(rules), capability)
	if cell.State == StateMixed {
		return plan{}, coreerr.NewStatus(capability.Label()+" has rules for specific paths or commands here, so it has no single value. Edit the individual rules instead.", coreerr.StatusConflict)
	}
	want := replacedRole(capability)
	var replaces []VerdictRule
	var kept []Rule
	for _, item := range rules {
		if replaced(item, capability, want) {
			replaces = append(replaces, item.entry())
		} else {
			kept = append(kept, item)
		}
	}
	var writes []VerdictRule
	for _, rule := range canonicalRules(capability) {
		writes = append(writes, VerdictRule{Verdict: verdict, Rule: rule})
		kept = append(kept, syntheticRule(verdict, rule))
	}
	resulting := cellOf(CapabilityGrid(kept), capability).State
	if replaces == nil {
		replaces = []VerdictRule{}
	}
	return plan{current: cell.State, resulting: resulting, replaces: replaces, writes: writes}, nil
}

// docRules are the rules of the document, in listing order (allow, ask, deny). Only string items count, as in ListRules.
func docRules(scope Scope, file string, doc *ojson.Document) ([]Rule, error) {
	permissions, present, err := permissionsOf(doc.Root(), file)
	if err != nil {
		return nil, err
	}
	var out []Rule
	for _, verdict := range Verdicts {
		for _, rule := range rulesOf(permissions, present, verdict) {
			out = append(out, newRule(scope, file, verdict, rule))
		}
	}
	return out, nil
}

// replaced: the rule is in the cell with the role a write replaces.
func replaced(item Rule, capability Capability, want role) bool {
	parsed, ok := ParseRule(item.Rule)
	if !ok {
		return false
	}
	for _, p := range placements(parsed) {
		if p.capability == capability && p.role == want {
			return true
		}
	}
	return false
}

// PreviewSetCapability is what a cell write would remove and write. It writes nothing. Resulting differs from
// verdict when a rule that is kept (for example a bare Bash deny for Push and deploy) still wins.
func (s *Store) PreviewSetCapability(scope Scope, capability Capability, verdict Verdict) (Preview, error) {
	p, err := s.plan(scope, capability, verdict)
	if err != nil {
		return Preview{}, err
	}
	return Preview{
		Capability: capability, Verdict: verdict, ScopeLabel: scope.FileLabel(), Current: p.current, Resulting: p.resulting,
		Replaces: p.replaces, Writes: p.writes,
	}, nil
}

// SetCapability replaces the cell's rules and records a journal entry. The entry is nil when the file already holds
// exactly that. The plan is made inside the write lock from the document the edit is going to change, so a writer that
// never takes our lock (Claude Code) cannot make the written cell differ from what was planned, and a cell that became
// mixed in the meantime is refused (409) like one that was mixed before.
func (s *Store) SetCapability(scope Scope, capability Capability, verdict Verdict) (*mutate.Entry, error) {
	if err := checkCapabilityWrite(capability, verdict); err != nil {
		return nil, err
	}
	label := "Set " + capability.Label() + " to " + verdict.title() + " (" + scope.journalLabel() + ")"
	return s.edit(scope, label, func(file string, doc *ojson.Document) (*ojson.Document, error) {
		rules, err := docRules(scope, file, doc)
		if err != nil {
			return nil, err
		}
		p, err := planOn(rules, capability, verdict)
		if err != nil {
			return nil, err
		}
		return editRules(doc, file, p.replaces, p.writes)
	})
}
