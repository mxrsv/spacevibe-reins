package inventory

import (
	"context"
	"path/filepath"
	"strconv"
	"strings"

	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/toml"
)

// Read lists the skills, agents and hooks of both CLIs, plugin-owned items, and the .claude folders of the
// discovered projects. Every file that cannot be used becomes a plain sentence in Problems; nothing here
// fails. It reads the disk synchronously. Ported from Inventory.read.
func Read(r roots.Roots) Snapshot {
	snapshot, _, _ := read(context.Background(), r)
	return snapshot
}

// read is Read plus the project folders it discovered, for the process-wide list (see Service). It looks at
// the context between the CLIs, plugins and projects and returns its error when it ended.
func read(ctx context.Context, r roots.Roots) (Snapshot, []string, error) {
	var (
		items    []Item
		hooks    []Hook
		problems []string
		// otherHooks counts hooks of a type other than command (http, mcp_tool, prompt, agent), which are not listed.
		otherHooks int
	)
	clis := []struct {
		cli CLI
		r   roots.CLIRoots
	}{{Claude, r.Claude}, {Codex, r.Codex}}
	for _, c := range clis {
		if err := ctx.Err(); err != nil {
			return Snapshot{}, nil, err
		}
		switch pathPresence(c.r.Root) {
		case missing:
			continue
		case unknown:
			problems = append(problems, c.r.Root+" cannot be read, so its skills, agents and hooks cannot be shown.")
			continue
		}
		items = append(items, readSkills(c.r.Skills, c.cli, nil, nil, &problems)...)
		items = append(items, readAgents(c.r.Agents, c.cli, nil, nil, &problems)...)
		config, status := readJSON(c.r.HookFile)
		switch status {
		case jsonValue:
			hooks = append(hooks, parseHooks(config, c.cli, nil, c.r.HookFile, nil, &problems, &otherHooks)...)
		case jsonInvalid:
			problems = append(problems, c.r.HookFile+" is not valid JSON, so its hooks cannot be shown or changed.")
		case jsonTooLarge:
			problems = append(problems, c.r.HookFile+" is too large to read, so its hooks cannot be shown.")
		case jsonUnreadable:
			problems = append(problems, c.r.HookFile+" cannot be read, so its hooks cannot be shown.")
		}
	}

	claudeSettings, settingsStatus := readJSON(r.Claude.HookFile)
	haveSettings := settingsStatus == jsonValue
	if reason := unusableReason(settingsStatus); reason != "" {
		// The hooks loop above already says the file cannot be used for hooks; this is what else depends on it.
		problems = append(problems, r.Claude.HookFile+" "+reason+", so enabled plugins and skill overrides are not known.")
	}
	for _, plugin := range plugins(r, claudeSettings, haveSettings, &problems) {
		if err := ctx.Err(); err != nil {
			return Snapshot{}, nil, err
		}
		owner := plugin.name
		base := absolute(plugin.path)
		items = append(items, readSkills(join(base, "skills"), Claude, &owner, nil, &problems)...)
		items = append(items, readAgents(join(base, "agents"), Claude, &owner, nil, &problems)...)
		hookFile := join(base, "hooks", "hooks.json")
		config, status := readJSON(hookFile)
		if status == jsonValue {
			hooks = append(hooks, parseHooks(config, Claude, &owner, hookFile, nil, &problems, &otherHooks)...)
		} else if reason := unusableReason(status); reason != "" {
			problems = append(problems, hookFile+" "+reason+", so the hooks of the plugin "+owner+" are not shown.")
		}
	}

	projects := discoverProjects(ctx, r)
	for _, path := range projects {
		if err := ctx.Err(); err != nil {
			return Snapshot{}, nil, err
		}
		project := path
		dir := join(path, ".claude")
		if pathPresence(dir) == unknown {
			problems = append(problems, path+" cannot be read, so its skills, agents and hooks cannot be shown.")
			continue
		}
		items = append(items, readSkills(join(dir, "skills"), Claude, nil, &project, &problems)...)
		items = append(items, readAgents(join(dir, "agents"), Claude, nil, &project, &problems)...)
		for _, name := range []string{"settings.json", "settings.local.json"} {
			file := join(dir, name)
			config, status := readJSON(file)
			switch status {
			case jsonValue:
				hooks = append(hooks, parseHooks(config, Claude, nil, file, &project, &problems, &otherHooks)...)
			case jsonInvalid:
				problems = append(problems, file+" is not valid JSON, so its hooks cannot be shown.")
			case jsonTooLarge:
				problems = append(problems, file+" is too large to read, so its hooks cannot be shown.")
			case jsonUnreadable:
				problems = append(problems, file+" cannot be read, so its hooks cannot be shown.")
			}
		}
	}

	// Claude global skills carry the skillOverrides value of settings.json (nil when there is none).
	var overrides ojson.Value
	haveOverrides := false
	if haveSettings {
		overrides, haveOverrides = claudeSettings.Member("skillOverrides")
	}
	for i := range items {
		item := &items[i]
		if item.CLI == Claude && item.Kind == KindSkill && item.Scope == ScopeGlobal {
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

	names := map[string]struct{}{}
	for _, item := range items {
		names[string(item.CLI)+":"+item.Key()] = struct{}{}
	}
	for i := range items {
		_, items[i].InOther = names[string(items[i].CLI.Other())+":"+items[i].Key()]
	}

	if otherHooks == 1 {
		problems = append(problems, "1 hook of another type is not shown.")
	} else if otherHooks > 1 {
		problems = append(problems, strconv.Itoa(otherHooks)+" hooks of other types are not shown.")
	}

	if items == nil {
		items = []Item{}
	}
	if hooks == nil {
		hooks = []Hook{}
	}
	if problems == nil {
		problems = []string{}
	}
	if err := ctx.Err(); err != nil {
		return Snapshot{}, nil, err
	}
	return Snapshot{
		Items: items, Hooks: hooks, Problems: problems, Events: Events(),
		Roots: map[string]string{string(Claude): r.Claude.Root, string(Codex): r.Codex.Root},
	}, projects, nil
}

// ItemFile is the text of a skill or agent file for the detail view, capped.
type ItemFile struct {
	Size      int64  `json:"size"`
	Text      string `json:"text"`
	Truncated bool   `json:"truncated"`
}

// ReadItemFile is the first 64 KB of a skill or agent file for the detail view. False when it cannot be read.
func ReadItemFile(path string) (ItemFile, bool) {
	info, err := osStat(path)
	if err != nil {
		return ItemFile{}, false
	}
	text, ok := readText(path, itemFileBytes)
	if !ok {
		return ItemFile{}, false
	}
	return ItemFile{Size: info.Size(), Text: text, Truncated: info.Size() > itemFileBytes}, true
}

func absolute(path string) string {
	if filepath.IsAbs(path) {
		return strings.TrimRight(path, "/")
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return abs
}

// Skills and agents.

func readSkills(dir string, cli CLI, owner, project *string, problems *[]string) []Item {
	if isUnreadableFolder(dir) {
		*problems = append(*problems, dir+" cannot be read, so its skills cannot be shown.")
	}
	var out []Item
	for _, entry := range listDir(dir) {
		if isSystemName(entry) {
			continue
		}
		path := join(dir, entry)
		file := join(path, "SKILL.md")
		text, ok := readText(file, maxTextBytes)
		if !ok {
			if pathPresence(file) != missing {
				*problems = append(*problems, file+" cannot be read, so this skill is not shown.")
			}
			continue
		}
		fm := ParseFrontmatter(text)
		out = append(out, Item{
			ID: string(cli) + ":skill:" + idTag(owner, project) + ":" + entry, CLI: cli, Kind: KindSkill,
			Name: nonEmpty(fm["name"], entry), Entry: entry, Description: fm["description"],
			Owner: ownerOf(owner, path), Path: path, File: file, Removable: isUserLevel(owner, project),
			Scope: scopeOf(project), Project: project,
		})
	}
	return out
}

func readAgents(dir string, cli CLI, owner, project *string, problems *[]string) []Item {
	if isUnreadableFolder(dir) {
		*problems = append(*problems, dir+" cannot be read, so its agents cannot be shown.")
	}
	var out []Item
	for _, entry := range listDir(dir) {
		if isSystemName(entry) {
			continue
		}
		isMarkdown := strings.HasSuffix(entry, ".md")
		if !isMarkdown && !strings.HasSuffix(entry, ".toml") {
			continue
		}
		path := join(dir, entry)
		text, ok := readText(path, maxTextBytes)
		if !ok {
			*problems = append(*problems, path+" cannot be read, so this agent is not shown.")
			continue
		}
		var fields map[string]string
		fallback := strings.TrimSuffix(entry, ".toml")
		if isMarkdown {
			fields = ParseFrontmatter(text)
			fallback = strings.TrimSuffix(entry, ".md")
		} else {
			fields = tomlFields(text)
		}
		out = append(out, Item{
			ID: string(cli) + ":agent:" + idTag(owner, project) + ":" + entry, CLI: cli, Kind: KindAgent,
			Name: nonEmpty(fields["name"], fallback), Entry: entry, Description: fields["description"],
			Owner: ownerOf(owner, path), Path: path, File: path, Removable: isUserLevel(owner, project),
			Scope: scopeOf(project), Project: project,
		})
	}
	return out
}

// tomlFields are the name and description of a Codex agent .toml: the first assignment of each key, in any
// table, as the Node regex finds it.
func tomlFields(text string) map[string]string {
	doc := toml.Read(text)
	out := map[string]string{}
	for _, key := range []string{"name", "description"} {
		for _, e := range doc.Entries {
			if len(e.KeyPath) == 1 && e.KeyPath[0] == key && e.Value != nil {
				if s, ok := e.Value.AsString(); ok {
					out[key] = s
					break
				}
			}
		}
	}
	return out
}

func isSystemName(name string) bool {
	return strings.HasPrefix(name, ".") || strings.HasPrefix(name, "_")
}

func nonEmpty(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

func isUserLevel(owner, project *string) bool {
	return (owner == nil || *owner == "") && project == nil
}

func ownerOf(owner *string, path string) string {
	if owner != nil {
		return *owner
	}
	if isSymlink(path) {
		return "link"
	}
	return "user"
}

func scopeOf(project *string) Scope {
	if project == nil {
		return ScopeGlobal
	}
	return ScopeProject
}

func idTag(owner, project *string) string {
	if project != nil {
		return "project:" + hashes.Sha(*project)
	}
	if owner != nil {
		return *owner
	}
	return "local"
}
