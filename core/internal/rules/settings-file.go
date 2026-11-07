package rules

import (
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/ojson"
)

// The "permissions" block of one Claude Code settings file: shape checks and the edit that adds or removes rules.
// Nothing here reads or returns any other key; env and friends are never looked at, and no message quotes content
// (RulesSettingsFile.swift).

// permissionsOf is the "permissions" object, or false when the file has none (a missing key or null counts as empty,
// as in Node). It refuses, with a 409, a permissions value that is not an object and a verdict list that is not an
// array (a null list is not an array either).
func permissionsOf(root ojson.Value, file string) (ojson.Value, bool, error) {
	value, has := root.Member("permissions")
	if !has || value.Kind() == ojson.KindNull {
		return ojson.Value{}, false, nil
	}
	if value.Kind() != ojson.KindObject {
		return ojson.Value{}, false, coreerr.NewStatus(file+" has a permissions value that is not an object. Nothing was changed.", coreerr.StatusConflict)
	}
	for _, verdict := range Verdicts {
		if list, ok := value.Member(string(verdict)); ok && list.Kind() != ojson.KindArray {
			return ojson.Value{}, false, coreerr.NewStatus(file+" has permissions."+string(verdict)+" that is not a list. Nothing was changed.", coreerr.StatusConflict)
		}
	}
	return value, true, nil
}

// listOf is the elements of one verdict list; nil when absent.
func listOf(permissions ojson.Value, present bool, verdict Verdict) []ojson.Value {
	if !present {
		return nil
	}
	list, ok := permissions.Member(string(verdict))
	if !ok {
		return nil
	}
	items, _ := list.ArrayValue()
	return items
}

// rulesOf are the string rules of one verdict, in file order. Values that are not strings are skipped.
func rulesOf(permissions ojson.Value, present bool, verdict Verdict) []string {
	var out []string
	for _, item := range listOf(permissions, present, verdict) {
		if s, ok := item.StringValue(); ok {
			out = append(out, s)
		}
	}
	return out
}

// verdictHolding is the first verdict (allow, ask, deny) whose list contains rule.
func verdictHolding(permissions ojson.Value, present bool, rule string) (Verdict, bool) {
	for _, verdict := range Verdicts {
		for _, r := range rulesOf(permissions, present, verdict) {
			if r == rule {
				return verdict, true
			}
		}
	}
	return "", false
}

// listChange is what one verdict list becomes: which elements go (highest index first) and which rules are appended.
type listChange struct {
	verdict       Verdict
	removeIndices []int
	appended      []string
}

// editRules removes every occurrence of each remove rule and appends each add rule that is not already there, one
// list per verdict, exactly as withRules in Node rules (git b58269d): kept elements first (non-strings are kept), then
// the new ones. It returns the document unchanged when no list would differ, so a no-op writes nothing.
func editRules(doc *ojson.Document, file string, remove, add []VerdictRule) (*ojson.Document, error) {
	permissions, present, err := permissionsOf(doc.Root(), file)
	if err != nil {
		return nil, err
	}
	var changes []listChange
	for _, verdict := range Verdicts {
		drop := map[string]bool{}
		for _, r := range remove {
			if r.Verdict == verdict {
				drop[r.Rule] = true
			}
		}
		var put []string
		for _, r := range add {
			if r.Verdict == verdict {
				put = append(put, r.Rule)
			}
		}
		if len(drop) == 0 && len(put) == 0 {
			continue
		}
		current := listOf(permissions, present, verdict)
		var removeIndices []int
		var kept []ojson.Value
		for index, item := range current {
			if text, ok := item.StringValue(); ok && drop[text] {
				removeIndices = append(removeIndices, index)
			} else {
				kept = append(kept, item)
			}
		}
		var appended []string
		for _, rule := range put {
			if !containsString(kept, rule) && !containsRule(appended, rule) {
				appended = append(appended, rule)
			}
		}
		// Compare the lists, not the operations: removing a rule and writing it back at the end is a no-op when it was last.
		next := append(append([]ojson.Value(nil), kept...), stringValues(appended)...)
		if !sameList(next, current) {
			reversed := make([]int, len(removeIndices))
			for i, index := range removeIndices {
				reversed[len(removeIndices)-1-i] = index
			}
			changes = append(changes, listChange{verdict: verdict, removeIndices: reversed, appended: appended})
		}
	}
	if len(changes) == 0 {
		return doc, nil
	}
	failed := coreerr.NewStatus(file+" could not be edited. Nothing was changed.", coreerr.StatusConflict)
	result := doc
	if value, ok := doc.Root().Member("permissions"); ok && value.Kind() == ojson.KindNull {
		if result, err = result.Set(ojson.Path("permissions"), ojson.Object()); err != nil {
			return nil, failed
		}
	}
	for _, change := range changes {
		path := ojson.Path("permissions", string(change.verdict))
		for _, index := range change.removeIndices {
			if result, err = result.Remove(append(append([]ojson.Step(nil), path...), ojson.Index(index))); err != nil {
				return nil, failed
			}
		}
		for _, rule := range change.appended {
			if result, err = result.Append(ojson.String(rule), path); err != nil {
				return nil, failed
			}
		}
	}
	return result, nil
}

func stringValues(items []string) []ojson.Value {
	out := make([]ojson.Value, len(items))
	for i, s := range items {
		out[i] = ojson.String(s)
	}
	return out
}

func containsString(values []ojson.Value, s string) bool {
	for _, v := range values {
		if got, ok := v.StringValue(); ok && got == s {
			return true
		}
	}
	return false
}

func containsRule(rules []string, s string) bool {
	for _, r := range rules {
		if r == s {
			return true
		}
	}
	return false
}

func sameList(a, b []ojson.Value) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if !a[i].Equal(b[i]) {
			return false
		}
	}
	return true
}
