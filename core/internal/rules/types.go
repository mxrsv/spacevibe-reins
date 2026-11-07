package rules

import (
	"strings"
)

// Verdict is what Claude Code does when a tool call matches a rule. The values are the keys of "permissions" in
// settings.json.
type Verdict string

// The verdicts, in the order the lists are read and written.
const (
	Allow Verdict = "allow"
	Ask   Verdict = "ask"
	Deny  Verdict = "deny"
)

// Verdicts is every verdict in file order.
var Verdicts = []Verdict{Allow, Ask, Deny}

// Valid reports whether v is one of the three verdicts.
func (v Verdict) Valid() bool { return v == Allow || v == Ask || v == Deny }

// title is the capitalised verdict used in journal labels: "Set Run commands to Deny".
func (v Verdict) title() string { return strings.ToUpper(string(v)[:1]) + string(v)[1:] }

// Capability is one row of the capability grid.
type Capability string

// The capabilities, same ids and order as CAPABILITIES in Node rules (git b58269d).
const (
	Read    Capability = "read"
	Edit    Capability = "edit"
	Run     Capability = "run"
	Network Capability = "network"
	Push    Capability = "push"
	Secrets Capability = "secrets"
)

// Capabilities is every capability in grid order.
var Capabilities = []Capability{Read, Edit, Run, Network, Push, Secrets}

// Valid reports whether c is a known capability.
func (c Capability) Valid() bool {
	for _, k := range Capabilities {
		if c == k {
			return true
		}
	}
	return false
}

// Label is the name shown for the capability.
func (c Capability) Label() string {
	switch c {
	case Read:
		return "Read files"
	case Edit:
		return "Edit files"
	case Run:
		return "Run commands"
	case Network:
		return "Network"
	case Push:
		return "Push and deploy"
	case Secrets:
		return "Secrets (.env)"
	}
	return string(c)
}

// State is the value of a grid cell. Mixed means rules for specific paths or commands disagree, so there is no
// single value to show or write.
type State string

// The cell states.
const (
	StateAllow State = "allow"
	StateAsk   State = "ask"
	StateDeny  State = "deny"
	StateMixed State = "mixed"
	StateNone  State = "none"
)

// ScopeKind says where a rule lives.
type ScopeKind string

// The scope kinds: the global settings.json, or a project's settings.json / settings.local.json.
const (
	KindGlobal  ScopeKind = "global"
	KindProject ScopeKind = "project"
	KindLocal   ScopeKind = "local"
)

// Valid reports whether k is a known scope kind.
func (k ScopeKind) Valid() bool { return k == KindGlobal || k == KindProject || k == KindLocal }

// Scope is one settings file: the global one, or a project's shared or local one.
type Scope struct {
	Kind ScopeKind
	// Dir is the project folder; empty for the global scope.
	Dir string
}

// Global is the scope of ~/.claude/settings.json.
var Global = Scope{Kind: KindGlobal}

// ProjectScope is <dir>/.claude/settings.json.
func ProjectScope(dir string) Scope { return Scope{Kind: KindProject, Dir: dir} }

// LocalScope is <dir>/.claude/settings.local.json.
func LocalScope(dir string) Scope { return Scope{Kind: KindLocal, Dir: dir} }

// ScopesFor is the scopes shown for a project: global, project, local (just global without a project).
func ScopesFor(dir string) []Scope {
	if dir == "" {
		return []Scope{Global}
	}
	return []Scope{Global, ProjectScope(dir), LocalScope(dir)}
}

// FileLabel is the short name of the settings file, without any folder: safe to show next to a preview.
func (s Scope) FileLabel() string {
	switch s.Kind {
	case KindProject:
		return ".claude/settings.json"
	case KindLocal:
		return ".claude/settings.local.json"
	}
	return "~/.claude/settings.json"
}

// journalLabel is used in journal labels, as in Node rules (git b58269d).
func (s Scope) journalLabel() string {
	if s.Kind == KindGlobal {
		return "global"
	}
	return string(s.Kind) + " " + s.Dir
}

// ParsedRule is Tool or Tool(specifier). The specifier is kept as written (not trimmed); nil when absent or blank.
type ParsedRule struct {
	Tool      string
	Specifier *string
}

// VerdictRule is a rule string under a verdict.
type VerdictRule struct {
	Verdict Verdict `json:"verdict"`
	Rule    string  `json:"rule"`
}

// Rule is one rule string found in a settings file, or a synthetic one (empty ID) built to ask what a grid would say.
type Rule struct {
	// ID is "<scope>:<verdict>:<rule>".
	ID    string    `json:"id"`
	Scope ScopeKind `json:"scope"`
	// Dir is the project folder, null for the global scope.
	Dir *string `json:"dir"`
	// File is the settings file the rule came from; empty for a synthetic rule.
	File      string  `json:"file"`
	Verdict   Verdict `json:"verdict"`
	Rule      string  `json:"rule"`
	Tool      *string `json:"tool"`
	Specifier *string `json:"specifier"`
}

// newRule builds the rule item of a rule string.
func newRule(scope Scope, file string, verdict Verdict, rule string) Rule {
	r := Rule{ID: string(scope.Kind) + ":" + string(verdict) + ":" + rule, Scope: scope.Kind, File: file, Verdict: verdict, Rule: rule}
	if scope.Kind != KindGlobal {
		dir := scope.Dir
		r.Dir = &dir
	}
	if parsed, ok := ParseRule(rule); ok {
		tool := parsed.Tool
		r.Tool = &tool
		r.Specifier = parsed.Specifier
	}
	return r
}

// syntheticRule is a rule that is not in any file, for what-if questions to the grid.
func syntheticRule(verdict Verdict, rule string) Rule { return newRule(Global, "", verdict, rule) }

func (r Rule) entry() VerdictRule { return VerdictRule{Verdict: r.Verdict, Rule: r.Rule} }

// Listing is the rules of some scopes, plus what could not be read.
type Listing struct {
	Rules []Rule `json:"rules"`
	// Problems is one sentence per file that could not be read as settings. It names the file, never quotes it.
	Problems []string `json:"problems"`
	// NotReadable is true when a file or project folder could not be looked at, so its rules are unknown. It is not
	// "no rules" (G-fix.1). Outside the golden projection.
	NotReadable bool `json:"notReadable"`
}

// Cell is one capability of the grid.
type Cell struct {
	Capability Capability `json:"capability"`
	Label      string     `json:"label"`
	State      State      `json:"state"`
	// Editable is false for mixed: the engine refuses to write it.
	Editable bool `json:"editable"`
	// Rules are the concrete rules behind the state: wide first, then the cell's own, then narrow.
	Rules []Rule `json:"rules"`
}

// Preview is what SetCapability would remove and write. It carries no absolute path.
type Preview struct {
	Capability Capability `json:"capability"`
	Verdict    Verdict    `json:"verdict"`
	// ScopeLabel is "~/.claude/settings.json" or ".claude/settings.json" / ".claude/settings.local.json".
	ScopeLabel string `json:"scopeLabel"`
	Current    State  `json:"current"`
	// Resulting differs from Verdict when a rule that is kept (for example a bare Bash deny for Push and deploy) still wins.
	Resulting State         `json:"resulting"`
	Replaces  []VerdictRule `json:"replaces"`
	Writes    []VerdictRule `json:"writes"`
}
