// Package config is the only place the core reads the environment (workspace E5).
// Every other package receives a Config; none calls os.Getenv.
package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/identity"
)

const (
	envTest = identity.EnvPrefix + "TEST"
	envHome = identity.EnvPrefix + "HOME"
	// envUserHome picks where the CLI folders are looked for. Each CLI's own root override (CLAUDE_CONFIG_DIR,
	// CODEX_HOME) is named in its registry entry (clis.Layout.RootEnv).
	envUserHome = "HOME"
	// envPath is searched for the binaries a CLI's registry entry names (clis.Installed). Only stat looks at it.
	envPath = "PATH"
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
	// RootOverrides is each CLI's root override (clis.Layout.RootEnv: CLAUDE_CONFIG_DIR, CODEX_HOME), as given and
	// keyed by CLI id. A missing or empty value counts as unset.
	RootOverrides map[clis.ID]string
	// SearchPath is the folders of PATH, in order. Empty entries are dropped; relative ones are kept and skipped by
	// clis.Installed.
	SearchPath []string
	// ProcFixture is SPACEVIBE_PROC_FIXTURE, a process-list fixture file for dev runs (empty counts as unset).
	// internal/proc takes it as an argument and never reads the environment.
	ProcFixture string
}

// Load reads the environment through os.Getenv.
func Load() (Config, error) { return LoadFrom(os.Getenv) }

// LoadFrom reads through getenv, so a test can fake the environment. It fails closed: an unknown
// SPACEVIBE_TEST value, or a relative SPACEVIBE_HOME, HOME or CLI root override, is an error, never a guess.
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
	v, err := absoluteOrEmpty(getenv, envUserHome)
	if err != nil {
		return Config{}, err
	}
	c.UserHome = v
	for _, d := range clis.All() {
		if d.Layout.RootEnv == "" {
			continue
		}
		v, err := absoluteOrEmpty(getenv, d.Layout.RootEnv)
		if err != nil {
			return Config{}, err
		}
		if v != "" {
			if c.RootOverrides == nil {
				c.RootOverrides = map[clis.ID]string{}
			}
			c.RootOverrides[d.ID] = v
		}
	}
	for _, dir := range filepath.SplitList(getenv(envPath)) {
		if dir != "" {
			c.SearchPath = append(c.SearchPath, dir)
		}
	}
	c.ProcFixture = getenv(envProcFixture)
	return c, nil
}

// absoluteOrEmpty is the variable as given, or an error when it is set and not an absolute path.
func absoluteOrEmpty(getenv func(string) string, name string) (string, error) {
	v := getenv(name)
	if v != "" && !filepath.IsAbs(v) {
		return "", fmt.Errorf("%s must be an absolute path", name)
	}
	return v, nil
}
