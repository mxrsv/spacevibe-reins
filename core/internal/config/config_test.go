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
		{"relative home fails closed", map[string]string{"SPACEVIBE_HOME": "x"}, Config{}, true},
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
