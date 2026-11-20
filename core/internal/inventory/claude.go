package inventory

import (
	"context"
	"strings"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// claudeInventory is Claude Code: skills, agents (.md) and settings.json hooks in CLAUDE_CONFIG_DIR, plus enabled
// plugins, the skillOverrides of settings.json, and the .claude folder of each discovered project.
type claudeInventory struct{}

// kinds: Claude Code logs skill, subagent and hook runs; its events come from its docs.
func (claudeInventory) kinds() Kinds {
	return Kinds{
		KindSkill: {Support: SupportFull, Runs: RunsCounted, CopyFormat: CopySkillFolder},
		KindAgent: {Support: SupportFull, Runs: RunsCounted, CopyFormat: CopyAgentFields},
		KindHook: {Support: SupportFull, Runs: RunsCounted, CopyFormat: CopyCommandHook, Events: []string{
			"SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Notification",
			"SubagentStart", "SubagentStop", "Elicitation", "ElicitationResult", "TeammateIdle", "PreCompact", "PostCompact", "Stop",
			"StopFailure", "SessionEnd"}},
	}
}

// projectCandidates are the cwd in the head of the newest session logs of each folder under projects/.
func (claudeInventory) projectCandidates(ctx context.Context, cli roots.CLIRoots) []string {
	return logCwds(ctx, cli.Logs)
}

func (claudeInventory) projectFolder() (projectFolder, bool) {
	return projectFolder{Name: ".claude", HookFiles: []string{"settings.json", "settings.local.json"}, Worktrees: "/.claude/worktrees/"}, true
}

// readExtras reads the enabled plugins and the skill overrides, both named in settings.json.
func (claudeInventory) readExtras(ctx context.Context, cli roots.CLIRoots, acc *readAcc) {
	settings, settingsStatus := readJSON(cli.HookFile)
	haveSettings := settingsStatus == jsonValue
	if reason := unusableReason(settingsStatus); reason != "" {
		// The hooks pass already says the file cannot be used for hooks; this is what else depends on it.
		acc.problems = append(acc.problems, cli.HookFile+" "+reason+", so enabled plugins and skill overrides are not known.")
	}
	for _, plugin := range plugins(cli.Root, settings, haveSettings, &acc.problems) {
		if ctx.Err() != nil {
			return // Read checks the context next and drops this partial read
		}
		owner := plugin.name
		base := absolute(plugin.path)
		acc.items = append(acc.items, readSkills(join(base, "skills"), clis.Claude, &owner, nil, &acc.problems)...)
		acc.items = append(acc.items, readAgents(join(base, "agents"), clis.Claude, &owner, nil, &acc.problems)...)
		hookFile := join(base, "hooks", "hooks.json")
		config, status := readJSON(hookFile)
		if status == jsonValue {
			acc.hooks = append(acc.hooks, parseHooks(config, clis.Claude, &owner, hookFile, nil, &acc.problems, &acc.otherHooks)...)
		} else if reason := unusableReason(status); reason != "" {
			acc.problems = append(acc.problems, hookFile+" "+reason+", so the hooks of the plugin "+owner+" are not shown.")
		}
	}
	applySkillOverrides(acc.items, settings, haveSettings)
}

// applySkillOverrides gives every global Claude Code skill (plugin skills included) the skillOverrides value of
// settings.json, nil when there is none. Project skills never carry one.
func applySkillOverrides(items []Item, settings ojson.Value, haveSettings bool) {
	var overrides ojson.Value
	haveOverrides := false
	if haveSettings {
		overrides, haveOverrides = settings.Member("skillOverrides")
	}
	for i := range items {
		item := &items[i]
		if item.CLI == clis.Claude && item.Kind == KindSkill && item.Scope == ScopeGlobal {
			item.HasSkillOverride = true
			item.SkillOverride = nil
			if haveOverrides {
				if v, ok := overrides.Member(item.Name); ok {
					if s, ok := v.StringValue(); ok {
						item.SkillOverride = &s
					}
				}
			}
		}
	}
}

// Plugins.

type plugin struct{ name, path string }

// plugins are the enabled Claude plugins whose install folder still exists. Read-only: SpaceVibe never changes a
// plugin.
func plugins(claudeRoot string, settings ojson.Value, haveSettings bool, problems *[]string) []plugin {
	file := join(claudeRoot, "plugins", "installed_plugins.json")
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
