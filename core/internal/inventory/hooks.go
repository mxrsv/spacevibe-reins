package inventory

import (
	"slices"
	"strconv"
	"strings"

	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// Hooks.

func parseHooks(config ojson.Value, cli CLI, owner *string, sourceFile string, project *string, problems *[]string, otherTypes *int) []Hook {
	var out []Hook
	hooksValue, ok := config.Member("hooks")
	if !ok {
		return out
	}
	events, ok := hooksValue.ObjectValue()
	if !ok {
		return out
	}
	// A duplicated key counts once, with the last value, as JSON.parse has it.
	seen := map[string]struct{}{}
	for _, member := range events {
		if _, dup := seen[member.Key]; dup {
			continue
		}
		seen[member.Key] = struct{}{}
		last, _ := hooksValue.Member(member.Key)
		groups, ok := last.ArrayValue()
		if !ok {
			continue
		}
		for _, group := range groups {
			var matcher *string
			if m, ok := group.Member("matcher"); ok {
				if s, ok := m.StringValue(); ok {
					matcher = &s
				}
			}
			hookList, _ := group.Member("hooks")
			list, _ := hookList.ArrayValue()
			for _, hook := range list {
				cv, ok := hook.Member("command")
				if !ok {
					if isOtherHookType(hook) {
						*otherTypes++
					}
					continue
				}
				command, ok := cv.StringValue()
				if !ok {
					continue
				}
				paths := ScriptPaths(command)
				// Dead only when every script is known to be gone: a script under a folder SpaceVibe cannot stat
				// may well work.
				allMissing, anyUnknown := true, false
				for _, p := range paths {
					switch pathPresence(p) {
					case present:
						allMissing = false
					case unknown:
						allMissing, anyUnknown = false, true
					}
				}
				dead := len(paths) > 0 && allMissing
				if anyUnknown {
					note := "A script named in " + sourceFile + " cannot be checked, so its hook is not marked dead."
					if !slices.Contains(*problems, note) {
						*problems = append(*problems, note)
					}
				}
				// A global id hashes owner, event, matcher and command. A project hook also hashes its file,
				// so the same hook in two files has two ids.
				seed := deref(owner) + "|" + member.Key + "|" + deref(matcher) + "|" + command
				if project != nil {
					seed += "|" + sourceFile
				}
				async := false
				if v, ok := hook.Member("async"); ok {
					async, _ = v.BoolValue()
				}
				ownerName := "user"
				if owner != nil {
					ownerName = *owner
				}
				out = append(out, Hook{
					ID: string(cli) + ":hook:" + hashes.Sha(seed), CLI: cli, Event: member.Key, Matcher: matcher, Command: command,
					Timeout: timeoutOf(hook), Async: async, Owner: ownerName, Removable: isUserLevel(owner, project),
					Dead: dead, Paths: paths, Hash: hashes.HookHash(member.Key, command), File: sourceFile,
					Scope: scopeOf(project), Project: project,
				})
			}
		}
	}
	return out
}

// isOtherHookType: a hook that names a handler type other than command (http, mcp_tool, prompt, agent). Such a hook
// has no command, so it is not listed; it is counted so the screen can say that some hooks are not shown.
func isOtherHookType(hook ojson.Value) bool {
	t, ok := hook.Member("type")
	if !ok {
		return false
	}
	name, ok := t.StringValue()
	return ok && name != "command"
}

// timeoutOf is Double(numberText). A number outside the float range reads as absent here, where Swift's
// Double(String) gives infinity (which its own JSON encoder then cannot write).
func timeoutOf(hook ojson.Value) *float64 {
	v, ok := hook.Member("timeout")
	if !ok {
		return nil
	}
	text, ok := v.NumberText()
	if !ok {
		return nil
	}
	f, err := strconv.ParseFloat(text, 64)
	if err != nil {
		return nil
	}
	return &f
}

// Plugins.

type plugin struct{ name, path string }

// plugins are the enabled Claude plugins whose install folder still exists. Read-only: SpaceVibe never changes a
// plugin.
func plugins(r roots.Roots, settings ojson.Value, haveSettings bool, problems *[]string) []plugin {
	file := join(r.Claude.Root, "plugins", "installed_plugins.json")
	installed, status := readJSON(file)
	if status != jsonValue {
		if reason := unusableReason(status); reason != "" {
			*problems = append(*problems, file+" "+reason+", so plugin skills, agents and hooks are not shown.")
		}
		return nil
	}
	pluginsValue, ok := installed.Member("plugins")
	if !ok {
		return nil
	}
	entries, ok := pluginsValue.ObjectValue()
	if !ok {
		return nil
	}
	var enabled ojson.Value
	haveEnabled := false
	if haveSettings {
		enabled, haveEnabled = settings.Member("enabledPlugins")
	}
	var out []plugin
	seen := map[string]struct{}{}
	for _, entry := range entries {
		if _, dup := seen[entry.Key]; dup {
			continue
		}
		seen[entry.Key] = struct{}{}
		value, _ := pluginsValue.Member(entry.Key)
		if !haveEnabled {
			continue
		}
		flag, ok := enabled.Member(entry.Key)
		if on, isBool := flag.BoolValue(); !ok || !isBool || !on {
			continue
		}
		first, ok := value.Element(0)
		if !ok {
			continue
		}
		pv, ok := first.Member("installPath")
		if !ok {
			continue
		}
		path, ok := pv.StringValue()
		if !ok || path == "" || !exists(path) {
			continue
		}
		name, _, _ := strings.Cut(entry.Key, "@")
		out = append(out, plugin{name, path})
	}
	return out
}
