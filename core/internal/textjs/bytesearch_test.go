package textjs

import (
	"slices"
	"testing"
)

func TestContains(t *testing.T) {
	line := []byte(`{"type":"assistant","text":"hé"}`)
	cases := []struct {
		needle string
		want   bool
	}{
		{`"type":"assistant"`, true},
		{`"type":"user"`, false},
		{"", true},
		{string(line), true},
		{string(line) + "x", false},
	}
	for _, c := range cases {
		if got := Contains(line, c.needle); got != c.want {
			t.Errorf("Contains(%q) = %v, want %v", c.needle, got, c.want)
		}
	}
	if !Contains(nil, "") || Contains(nil, "a") {
		t.Error("nil haystack")
	}
}

func TestToolUseIDs(t *testing.T) {
	cases := []struct {
		name, in string
		want     []string
	}{
		{"two", `"tool_use_id":"a" "tool_use_id":"bb"`, []string{"a", "bb"}},
		{"empty value skipped", `"tool_use_id":""x"tool_use_id":"c`, nil},
		{"empty then next key", `"tool_use_id":""tool_use_id":"q"`, []string{"q"}},
		{"no closing quote", `x"tool_use_id":"abc`, nil},
		{"no key", `{"a":1}`, nil},
		{"invalid bytes repaired", "\"tool_use_id\":\"a\xFFb\"", []string{"a�b"}},
		{"astral id", "\"tool_use_id\":\"\U0001F600\"", []string{"\U0001F600"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := ToolUseIDs([]byte(c.in)); !slices.Equal(got, c.want) {
				t.Errorf("ToolUseIDs(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}
