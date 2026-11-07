package config

import "testing"

func fake(env map[string]string) func(string) string {
	return func(k string) string { return env[k] }
}

func TestLoadFrom(t *testing.T) {
	cases := []struct {
		name    string
		env     map[string]string
		want    Config
		wantErr bool
	}{
		{"empty", nil, Config{}, false},
		{"test on", map[string]string{"SPACEVIBE_TEST": "1"}, Config{Test: true}, false},
		{"test off", map[string]string{"SPACEVIBE_TEST": "0"}, Config{}, false},
		{"test junk fails closed", map[string]string{"SPACEVIBE_TEST": "yes"}, Config{}, true},
		{"home", map[string]string{"SPACEVIBE_HOME": "/tmp/x/"}, Config{Home: "/tmp/x"}, false},
		{"cli folders", map[string]string{"HOME": "/h", "CLAUDE_CONFIG_DIR": "/c", "CODEX_HOME": "/x"}, Config{UserHome: "/h", ClaudeConfigDir: "/c", CodexHome: "/x"}, false},
		{"proc fixture", map[string]string{"SPACEVIBE_PROC_FIXTURE": "/tmp/p.json"}, Config{ProcFixture: "/tmp/p.json"}, false},
		{"relative home fails closed", map[string]string{"SPACEVIBE_HOME": "x"}, Config{}, true},
		{"relative HOME fails closed", map[string]string{"HOME": "h"}, Config{}, true},
		{"relative CLAUDE_CONFIG_DIR fails closed", map[string]string{"CLAUDE_CONFIG_DIR": "./c"}, Config{}, true},
		{"relative CODEX_HOME fails closed", map[string]string{"CODEX_HOME": "../x"}, Config{}, true},
		{"empty folders count as unset", map[string]string{"HOME": "", "CLAUDE_CONFIG_DIR": "", "CODEX_HOME": ""}, Config{}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := LoadFrom(fake(c.env))
			if (err != nil) != c.wantErr {
				t.Fatalf("err = %v, wantErr %v", err, c.wantErr)
			}
			if got != c.want {
				t.Fatalf("got %+v, want %+v", got, c.want)
			}
		})
	}
}

// The error names the variable and never quotes its value.
func TestRelativeCLIFolderErrorIsAFixedSentence(t *testing.T) {
	for _, name := range []string{"HOME", "CLAUDE_CONFIG_DIR", "CODEX_HOME"} {
		_, err := LoadFrom(fake(map[string]string{name: "relative/SECRET"}))
		if err == nil || err.Error() != name+" must be an absolute path" {
			t.Errorf("%s: err = %v", name, err)
		}
	}
}
