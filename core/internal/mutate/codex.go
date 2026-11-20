package mutate

import (
	"path/filepath"

	"spacevibe.dev/core/internal/roots"
)

// codexWriter writes Codex: TOML agents, hooks.json, and (for rules) config.toml.
type codexWriter struct{}

func (codexWriter) agentFile(name, description, instructions string) (string, string) {
	return "toml", "name = " + tomlQuote(name) + "\ndescription = " + tomlQuote(description) + "\ndeveloper_instructions = " + tomlQuote(agentBody(instructions)) + "\n"
}

// agentWithoutToolsGetsEveryTool is false: what Codex gives an agent file with no model or tools is not verified, so
// SpaceVibe does not claim it.
func (codexWriter) agentWithoutToolsGetsEveryTool() bool { return false }

// takesCopiedHooks is false: Codex skips a hook SpaceVibe wrote until it is trusted, so a copy would look done and do
// nothing (spec, "To verify"; G-fix.16).
func (codexWriter) takesCopiedHooks() bool { return false }

func (codexWriter) configFiles(cli roots.CLIRoots) []string {
	return []string{cli.HookFile, filepath.Join(cli.Root, "config.toml")}
}
