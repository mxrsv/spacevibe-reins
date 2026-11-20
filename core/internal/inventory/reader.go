package inventory

import (
	"context"
	"path/filepath"
	"strconv"
	"strings"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/toml"
)

// Read lists the skills, agents and hooks of every CLI with the inventory concept, what each keeps outside its root
// folders (plugin-owned items), and the project folders of the discovered projects. Every file that cannot be used
// becomes a plain sentence in Problems; nothing here fails. It reads the disk synchronously. Ported from
// Inventory.read.
func Read(r roots.Roots) Snapshot {
	snapshot, _, _ := read(context.Background(), r)
	return snapshot
}

// readAcc collects one read. otherHooks counts hooks of a type other than command (http, mcp_tool, prompt, agent),
// which are not listed.
type readAcc struct {
	items      []Item
	hooks      []Hook
	problems   []string
	otherHooks int
}

// read is Read plus the project folders it discovered, for the process-wide list (see Service). It looks at
// the context between the CLIs, their extras and projects and returns its error when it ended. Order: every CLI's
// root folders in wire order, then every CLI's extras, then the projects.
func read(ctx context.Context, r roots.Roots) (Snapshot, []string, error) {
	bound, err := bind(r)
	if err != nil {
		return Snapshot{}, nil, err
	}
	var acc readAcc
	for _, b := range bound {
		if err := ctx.Err(); err != nil {
			return Snapshot{}, nil, err
		}
		readRootFolders(b.id, b.roots, &acc)
	}
	for _, b := range bound {
		b.adapter.readExtras(ctx, b.roots, &acc)
		if err := ctx.Err(); err != nil {
			return Snapshot{}, nil, err
		}
	}

	projects := projectPaths(discoverBound(ctx, bound))
	for _, path := range projects {
		if err := ctx.Err(); err != nil {
			return Snapshot{}, nil, err
		}
		for _, b := range bound {
			if folder, ok := b.adapter.projectFolder(); ok {
				readProjectFolder(b.id, folder, path, &acc)
			}
		}
	}

	items, hooks, problems := acc.items, acc.hooks, acc.problems

	if acc.otherHooks == 1 {
		problems = append(problems, "1 hook of another type is not shown.")
	} else if acc.otherHooks > 1 {
		problems = append(problems, strconv.Itoa(acc.otherHooks)+" hooks of other types are not shown.")
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
	rootList := make([]CLIRoot, 0, len(bound))
	for _, b := range bound {
		rootList = append(rootList, CLIRoot{CLI: b.id, Root: b.roots.Root})
	}
	return Snapshot{Items: items, Hooks: hooks, Problems: problems, Events: Events(), Roots: rootList}, projects, nil
}

// readRootFolders reads one CLI's skills, agents and hook file from the folders its registry layout names.
func readRootFolders(cli clis.ID, r roots.CLIRoots, acc *readAcc) {
	switch pathPresence(r.Root) {
	case missing:
		return
	case unknown:
		acc.problems = append(acc.problems, r.Root+" cannot be read, so its skills, agents and hooks cannot be shown.")
		return
	}
	acc.items = append(acc.items, readSkills(r.Skills, cli, nil, nil, &acc.problems)...)
	acc.items = append(acc.items, readAgents(r.Agents, cli, nil, nil, &acc.problems)...)
	config, status := readJSON(r.HookFile)
	switch status {
	case jsonValue:
		acc.hooks = append(acc.hooks, parseHooks(config, cli, nil, r.HookFile, nil, &acc.problems, &acc.otherHooks)...)
	case jsonInvalid:
		acc.problems = append(acc.problems, r.HookFile+" is not valid JSON, so its hooks cannot be shown or changed.")
	case jsonTooLarge:
		acc.problems = append(acc.problems, r.HookFile+" is too large to read, so its hooks cannot be shown.")
	case jsonUnreadable:
		acc.problems = append(acc.problems, r.HookFile+" cannot be read, so its hooks cannot be shown.")
	}
}

// readProjectFolder reads one CLI's configuration folder inside a project.
func readProjectFolder(cli clis.ID, folder projectFolder, path string, acc *readAcc) {
	project := path
	dir := join(path, folder.Name)
	if pathPresence(dir) == unknown {
		acc.problems = append(acc.problems, path+" cannot be read, so its skills, agents and hooks cannot be shown.")
		return
	}
	acc.items = append(acc.items, readSkills(join(dir, "skills"), cli, nil, &project, &acc.problems)...)
	acc.items = append(acc.items, readAgents(join(dir, "agents"), cli, nil, &project, &acc.problems)...)
	for _, name := range folder.HookFiles {
		file := join(dir, name)
		config, status := readJSON(file)
		switch status {
		case jsonValue:
			acc.hooks = append(acc.hooks, parseHooks(config, cli, nil, file, &project, &acc.problems, &acc.otherHooks)...)
		case jsonInvalid:
			acc.problems = append(acc.problems, file+" is not valid JSON, so its hooks cannot be shown.")
		case jsonTooLarge:
			acc.problems = append(acc.problems, file+" is too large to read, so its hooks cannot be shown.")
		case jsonUnreadable:
			acc.problems = append(acc.problems, file+" cannot be read, so its hooks cannot be shown.")
		}
	}
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

func readSkills(dir string, cli clis.ID, owner, project *string, problems *[]string) []Item {
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
			ID: string(cli) + ":skill:" + idTag(owner, project) + ":" + entry, CLI: cli, ReadBy: readBy(cli), Kind: KindSkill,
			Name: nonEmpty(fm["name"], entry), Entry: entry, Description: fm["description"],
			Owner: ownerOf(owner, path), Path: path, File: file, Removable: isUserLevel(owner, project),
			Scope: scopeOf(project), Project: project,
		})
	}
	return out
}

func readAgents(dir string, cli clis.ID, owner, project *string, problems *[]string) []Item {
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
			ID: string(cli) + ":agent:" + idTag(owner, project) + ":" + entry, CLI: cli, ReadBy: readBy(cli), Kind: KindAgent,
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

// readBy is the CLIs that read a file in cli's own folders: cli alone, until a folder that several CLIs read is listed
// by more than one adapter (spec MC-R7).
func readBy(cli clis.ID) []clis.ID { return []clis.ID{cli} }

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
