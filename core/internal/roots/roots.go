// Package roots finds the folders of the CLIs SpaceVibe reads and SpaceVibe's own data folder, and refuses
// any of them under the real home when SPACEVIBE_TEST=1 (AC3).
// Ported from Sources/ReinsCore/Roots.swift and FileEdit.refuseRealHomeUnderTest
// (Node inventory roots(), git b58269d).
package roots

import (
	"fmt"
	"path/filepath"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/identity"
)

// CLIRoots are the folders of one CLI that SpaceVibe reads.
type CLIRoots struct {
	Root   string
	Skills string
	Agents string
	// HookFile is Claude Code's settings.json, Codex's hooks.json.
	HookFile string
	// Logs holds the session logs: Claude projects/, Codex sessions/.
	Logs string
}

// Roots is where the config, the logs and SpaceVibe's own data live.
type Roots struct {
	Claude CLIRoots
	Codex  CLIRoots
	// Data is SpaceVibe's own data: journal, trash, caches.
	Data string
	// ClaudeState is Claude Code's global state file: .claude.json in CLAUDE_CONFIG_DIR when that is
	// set, otherwise in HOME beside .claude. Limits reads its usage cache and nothing else from it.
	ClaudeState string
	// Gemini is Gemini CLI's folder. Only whether it exists is checked.
	Gemini string
}

// UnderRealHomeError means SPACEVIBE_TEST=1 and a root sits under the real home.
type UnderRealHomeError struct {
	// Label is claude, codex, spacevibe, "claude state" or gemini.
	Label string
	// Path is the offending root, as configured.
	Path string
}

func (e *UnderRealHomeError) Error() string {
	return fmt.Sprintf("%s=1: the %s root %s is under the real home. Point HOME, CLAUDE_CONFIG_DIR, CODEX_HOME and %s at a temporary folder.",
		envTest, e.Label, e.Path, envHome)
}

const (
	envTest = identity.EnvPrefix + "TEST"
	envHome = identity.EnvPrefix + "HOME"
)

// Resolve derives every root from cfg. An empty value counts as unset; HOME falls back to realHome.
// realHome is the account's real home folder from RealHome; tests pass a stand-in.
// With cfg.Test set it returns *UnderRealHomeError when a root, or the real path behind it, is
// under realHome.
func Resolve(cfg config.Config, realHome string) (Roots, error) {
	home := orDefault(cfg.UserHome, realHome)
	claudeRoot := orDefault(cfg.ClaudeConfigDir, filepath.Join(home, ".claude"))
	codexRoot := orDefault(cfg.CodexHome, filepath.Join(home, ".codex"))
	dataRoot := orDefault(cfg.Home, filepath.Join(home, identity.DataDir))
	claudeState := filepath.Join(orDefault(cfg.ClaudeConfigDir, home), ".claude.json")
	geminiRoot := filepath.Join(home, ".gemini")
	if cfg.Test {
		err := assertNotUnderRealHome(realHome, []labelled{
			{"claude", claudeRoot}, {"codex", codexRoot}, {"spacevibe", dataRoot},
			{"claude state", claudeState}, {"gemini", geminiRoot},
		})
		if err != nil {
			return Roots{}, err
		}
	}
	cli := func(root, hookFile, logs string) CLIRoots {
		return CLIRoots{
			Root:     root,
			Skills:   filepath.Join(root, "skills"),
			Agents:   filepath.Join(root, "agents"),
			HookFile: filepath.Join(root, hookFile),
			Logs:     filepath.Join(root, logs),
		}
	}
	return Roots{
		Claude:      cli(claudeRoot, "settings.json", "projects"),
		Codex:       cli(codexRoot, "hooks.json", "sessions"),
		Data:        dataRoot,
		ClaudeState: claudeState,
		Gemini:      geminiRoot,
	}, nil
}

func orDefault(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
