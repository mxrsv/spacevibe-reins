package mutate

import (
	"math"
	"strconv"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/ojson"
)

// The two pure edits on a hook file, withHook and withoutHook of Node mutate, done on an ojson.Document so the file
// keeps its key order, indent and every byte outside the edited array (MutateHookEdit.swift).
//
// A hook file holds hooks: { <event>: [ { matcher?, hooks: [ { type, command, ... } ] } ] }. A group is identified by
// its matcher (missing and null count as the same).

func layoutError(file string) error {
	return fail("The hooks in "+file+" have an unexpected layout. Nothing was changed.", coreerr.StatusConflict)
}

// hookValue is the hook object written for a new hook: {type: "command", command, timeout?}. A zero or missing
// timeout leaves the key out, as Node does.
func hookValue(command string, timeout *float64) (ojson.Value, error) {
	members := []ojson.Member{member("type", ojson.String("command")), member("command", ojson.String(command))}
	if timeout != nil && *timeout != 0 {
		t := *timeout
		if math.IsNaN(t) || math.IsInf(t, 0) {
			return ojson.Value{}, fail("The timeout must be a number.", coreerr.StatusBadRequest)
		}
		text := strconv.FormatFloat(t, 'g', -1, 64)
		if t == math.Round(t) && math.Abs(t) < 1e15 {
			text = strconv.FormatInt(int64(t), 10)
		}
		members = append(members, member("timeout", ojson.Number(text)))
	}
	return ojson.Object(members...), nil
}

// groupsOf is hooks.<event> of the document as an array, or none.
func groupsOf(doc *ojson.Document, event string) []ojson.Value {
	hooks, ok := doc.Root().Member("hooks")
	if !ok {
		return nil
	}
	groups, ok := hooks.Member(event)
	if !ok {
		return nil
	}
	items, _ := groups.ArrayValue()
	return items
}

func sameGroup(group ojson.Value, matcher *string) bool {
	m, ok := group.Member("matcher")
	if !ok || m.Kind() == ojson.KindNull {
		return matcher == nil
	}
	own, ok := m.StringValue()
	return ok && matcher != nil && *matcher == own
}

// commandOf is the command string of a hook object, and whether it has one.
func commandOf(hook ojson.Value) (string, bool) {
	c, ok := hook.Member("command")
	if !ok {
		return "", false
	}
	return c.StringValue()
}

func sameCommand(hook ojson.Value, command string, has bool) bool {
	c, ok := commandOf(hook)
	return ok == has && c == command
}

// hookAdding adds the hook to the first group with the same matcher that does not run this command yet, else as a
// new group.
func hookAdding(doc *ojson.Document, file, event string, matcher *string, hook ojson.Value) (*ojson.Document, error) {
	command, has := commandOf(hook)
	for index, group := range groupsOf(doc, event) {
		if !sameGroup(group, matcher) {
			continue
		}
		hooks, _ := group.Member("hooks")
		items, _ := hooks.ArrayValue()
		runs := false
		for _, h := range items {
			if sameCommand(h, command, has) {
				runs = true
				break
			}
		}
		if !runs {
			next, err := doc.Append(hook, ojson.Path("hooks", event, index, "hooks"))
			if err != nil {
				return nil, layoutError(file)
			}
			return next, nil
		}
	}
	var members []ojson.Member
	if matcher != nil && *matcher != "" {
		members = append(members, member("matcher", ojson.String(*matcher)))
	}
	members = append(members, member("hooks", ojson.Array(hook)))
	next, err := doc.Append(ojson.Object(members...), ojson.Path("hooks", event))
	if err != nil {
		return nil, layoutError(file)
	}
	return next, nil
}

// hookRemoving removes the first hook with this command from the first group with this matcher that has it. An empty
// group goes with it, and so does an event left with no group. It returns the hook that was removed, and false when
// none matched.
func hookRemoving(doc *ojson.Document, file, event string, matcher *string, command string) (*ojson.Document, ojson.Value, bool, error) {
	groups := groupsOf(doc, event)
	for groupIndex, group := range groups {
		if !sameGroup(group, matcher) {
			continue
		}
		hooksValue, ok := group.Member("hooks")
		if !ok {
			continue
		}
		hooks, ok := hooksValue.ArrayValue()
		if !ok {
			continue
		}
		hookIndex := -1
		for i, h := range hooks {
			if sameCommand(h, command, true) {
				hookIndex = i
				break
			}
		}
		if hookIndex < 0 {
			continue
		}
		var path []ojson.Step
		switch {
		case len(hooks) > 1:
			path = ojson.Path("hooks", event, groupIndex, "hooks", hookIndex)
		case len(groups) > 1:
			path = ojson.Path("hooks", event, groupIndex)
		default:
			path = ojson.Path("hooks", event)
		}
		next, err := doc.Remove(path)
		if err != nil {
			return nil, ojson.Value{}, false, layoutError(file)
		}
		return next, hooks[hookIndex], true, nil
	}
	return doc, ojson.Value{}, false, nil
}
