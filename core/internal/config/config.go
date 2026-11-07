// Package config is the only place the core reads the environment (workspace E5).
// Every other package receives a Config; none calls os.Getenv.
package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"spacevibe.dev/core/internal/identity"
)

const (
	envTest = identity.EnvPrefix + "TEST"
	envHome = identity.EnvPrefix + "HOME"
	// The folders of the CLIs, as the CLIs read them.
	envUserHome        = "HOME"
	envClaudeConfigDir = "CLAUDE_CONFIG_DIR"
	envCodexHome       = "CODEX_HOME"
	// envProcFixture is the same name as proc.EnvProcFixture; config cannot import proc (proc imports config).
	envProcFixture = identity.EnvPrefix + "PROC_FIXTURE"
)

// Config is the typed, validated environment.
type Config struct {
	// Test is true when SPACEVIBE_TEST is "1": the real-home guard applies (G1.6).
	Test bool
	// Home is the data root override (SPACEVIBE_HOME). Empty means the default under the user's home.
	Home string
	// UserHome is HOME, as given (empty counts as unset). It only picks where the CLI folders are
	// looked for; it is never the real home (see roots.RealHome).
	UserHome string
	// ClaudeConfigDir is CLAUDE_CONFIG_DIR, as given (empty counts as unset).
	ClaudeConfigDir string
	// CodexHome is CODEX_HOME, as given (empty counts as unset).
	CodexHome string
	// ProcFixture is SPACEVIBE_PROC_FIXTURE, a process-list fixture file for dev runs (empty counts as unset).
	// internal/proc takes it as an argument and never reads the environment.
	ProcFixture string
}

// Load reads the environment through os.Getenv.
func Load() (Config, error) { return LoadFrom(os.Getenv) }

// LoadFrom reads through getenv, so a test can fake the environment. It fails closed: an unknown
// SPACEVIBE_TEST value, or a relative SPACEVIBE_HOME, HOME, CLAUDE_CONFIG_DIR or CODEX_HOME, is an error, never a guess.
func LoadFrom(getenv func(string) string) (Config, error) {
	var c Config
	switch v := getenv(envTest); v {
	case "", "0":
	case "1":
		c.Test = true
	default:
		return Config{}, fmt.Errorf("%s must be 1 or 0, got %q", envTest, v)
	}
	if v := strings.TrimSpace(getenv(envHome)); v != "" {
		if !filepath.IsAbs(v) {
			return Config{}, fmt.Errorf("%s must be an absolute path", envHome)
		}
		c.Home = filepath.Clean(v)
	}
	for _, folder := range []struct {
		name string
		into *string
	}{{envUserHome, &c.UserHome}, {envClaudeConfigDir, &c.ClaudeConfigDir}, {envCodexHome, &c.CodexHome}} {
		v := getenv(folder.name)
		if v != "" && !filepath.IsAbs(v) {
			return Config{}, fmt.Errorf("%s must be an absolute path", folder.name)
		}
		*folder.into = v
	}
	c.ProcFixture = getenv(envProcFixture)
	return c, nil
}
