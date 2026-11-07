package rules

// The capability grid: one state per capability, derived from concrete rules. Pure; no file is read.
//
//	Rule shape                                         Capability   Role in the cell
//	Read (bare, Read(), Read(*))                       Read files   wide        (also Secrets, wide)
//	Read(<path>)                                       Read files   narrow
//	Read(<path>) naming .env (Read(./.env*))           Secrets      own
//	Edit | Write | MultiEdit (bare or *)               Edit files   wide
//	Edit | Write | MultiEdit (<path>)                  Edit files   narrow
//	Bash (bare, Bash(*))                               Run commands wide        (also Push and deploy, wide)
//	Bash(<command>) except push and deploy prefixes    Run commands narrow
//	Bash(git push ..) Bash(vercel ..) and the other    Push+deploy  own
//	  deploy-like prefixes
//	WebFetch | WebSearch (bare or *)                   Network      wide
//	WebFetch(..) | WebSearch(..)                       Network      narrow
//	anything else (mcp__*, Skill, Task, ...)           no cell
//
// State of a cell (deny beats ask beats allow, as in Claude Code):
//
//	no rule at all                                     none
//	a wide deny                                        deny
//	wide ask   + narrow deny                           mixed;  wide ask   otherwise: ask
//	wide allow + narrow deny or ask                    mixed;  wide allow otherwise: allow
//	narrow rules only                                  mixed   (a scoped rule is not a cell value)
//	own rules only (Push and deploy, Secrets)          their verdict when all agree, else mixed
//	wide + own rules                                   strongest verdict among all of them

type role int

const (
	roleWide role = iota
	roleOwn
	roleNarrow
)

type placement struct {
	capability Capability
	role       role
}

// placements are the cells a parsed rule belongs to.
func placements(rule ParsedRule) []placement {
	wide := isWide(rule)
	specifier := ""
	if rule.Specifier != nil {
		specifier = *rule.Specifier
	}
	switch rule.Tool {
	case "Read":
		if wide {
			return []placement{{Read, roleWide}, {Secrets, roleWide}}
		}
		if namesEnvFile(specifier) {
			return []placement{{Secrets, roleOwn}}
		}
		return []placement{{Read, roleNarrow}}
	case "Edit", "Write", "MultiEdit":
		if wide {
			return []placement{{Edit, roleWide}}
		}
		return []placement{{Edit, roleNarrow}}
	case "Bash":
		if wide {
			return []placement{{Run, roleWide}, {Push, roleWide}}
		}
		if looksLikePushOrDeploy(specifier) {
			return []placement{{Push, roleOwn}}
		}
		return []placement{{Run, roleNarrow}}
	case "WebFetch", "WebSearch":
		if wide {
			return []placement{{Network, roleWide}}
		}
		return []placement{{Network, roleNarrow}}
	}
	return nil
}

type verdictSet map[Verdict]bool

func verdictsOf(items []Rule) verdictSet {
	set := verdictSet{}
	for _, item := range items {
		set[item.Verdict] = true
	}
	return set
}

func (s verdictSet) union(o verdictSet) verdictSet {
	out := verdictSet{}
	for v := range s {
		out[v] = true
	}
	for v := range o {
		out[v] = true
	}
	return out
}

// strongest is the verdict that wins, deny over ask over allow; false for an empty set.
func (s verdictSet) strongest() (State, bool) {
	switch {
	case s[Deny]:
		return StateDeny, true
	case s[Ask]:
		return StateAsk, true
	case s[Allow]:
		return StateAllow, true
	}
	return StateNone, false
}

func cellState(wide, own, narrow []Rule) State {
	if len(wide) == 0 && len(own) == 0 && len(narrow) == 0 {
		return StateNone
	}
	w := verdictsOf(wide)
	if w[Deny] {
		return StateDeny
	}
	o := verdictsOf(own)
	if len(narrow) == 0 {
		if len(own) == 0 {
			s, _ := w.strongest()
			return s
		}
		if len(wide) > 0 {
			s, _ := w.union(o).strongest()
			return s
		}
		if len(o) == 1 {
			for v := range o {
				return State(v)
			}
		}
		return StateMixed
	}
	n := verdictsOf(narrow)
	if w[Ask] {
		if n[Deny] {
			return StateMixed
		}
		return StateAsk
	}
	if w[Allow] {
		if n[Deny] || n[Ask] {
			return StateMixed
		}
		return StateAllow
	}
	return StateMixed
}

// CapabilityGrid derives the grid from rules of one scope or several: the same function sees one flat list.
func CapabilityGrid(rules []Rule) []Cell {
	type bucket struct{ wide, own, narrow []Rule }
	cells := map[Capability]*bucket{}
	for _, item := range rules {
		parsed, ok := ParseRule(item.Rule)
		if !ok {
			continue
		}
		for _, p := range placements(parsed) {
			b := cells[p.capability]
			if b == nil {
				b = &bucket{}
				cells[p.capability] = b
			}
			switch p.role {
			case roleWide:
				b.wide = append(b.wide, item)
			case roleOwn:
				b.own = append(b.own, item)
			case roleNarrow:
				b.narrow = append(b.narrow, item)
			}
		}
	}
	out := make([]Cell, 0, len(Capabilities))
	for _, c := range Capabilities {
		b := cells[c]
		if b == nil {
			b = &bucket{}
		}
		state := cellState(b.wide, b.own, b.narrow)
		behind := make([]Rule, 0, len(b.wide)+len(b.own)+len(b.narrow))
		behind = append(behind, b.wide...)
		behind = append(behind, b.own...)
		behind = append(behind, b.narrow...)
		out = append(out, Cell{Capability: c, Label: c.Label(), State: state, Editable: state != StateMixed, Rules: behind})
	}
	return out
}

// cellOf is the cell of one capability.
func cellOf(grid []Cell, c Capability) Cell {
	for _, cell := range grid {
		if cell.Capability == c {
			return cell
		}
	}
	return Cell{Capability: c, Label: c.Label(), State: StateNone, Editable: true, Rules: []Rule{}}
}
