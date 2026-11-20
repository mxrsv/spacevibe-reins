package mutate

import "spacevibe.dev/core/internal/roots"

// claudeWriter writes Claude Code: markdown agents with a YAML header, and hooks in settings.json.
type claudeWriter struct{}

func (claudeWriter) agentFile(name, description, instructions string) (string, string) {
	return "md", "---\nname: " + name + "\ndescription: " + yamlValue(description) + "\n---\n\n" + agentBody(instructions) + "\n"
}

// agentWithoutToolsGetsEveryTool: a Claude Code subagent with no tools line "inherits every tool available to
// subagents" (Claude Code's subagent docs), and agentFile writes none.
func (claudeWriter) agentWithoutToolsGetsEveryTool() bool { return true }

// takesCopiedHooks: Claude Code loads a hook SpaceVibe wrote as soon as it reads settings.json.
func (claudeWriter) takesCopiedHooks() bool { return true }

func (claudeWriter) configFiles(cli roots.CLIRoots) []string { return []string{cli.HookFile} }
