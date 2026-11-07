package inventory

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"spacevibe.dev/core/internal/goldentest"
)

func TestFrontmatter(t *testing.T) {
	cases := []struct {
		name string // Swift: FrontmatterTests.swift "<name>"
		text string
		want map[string]string
	}{
		{"plain, double-quoted and single-quoted values",
			"---\nname: ponytail\ndescription: \"Say \\\"hi\\\" \\u00e9\"\ntitle: 'it''s fine'\nmodel: sonnet\n---\nbody",
			map[string]string{"name": "ponytail", "description": "Say \"hi\" é", "title": "it's fine", "model": "sonnet"}},
		{"a folded > block joins its lines with spaces",
			"---\nname: keep\ndescription: >\n  folded\n  text\n\n  more\nnext: x\n---\nbody",
			map[string]string{"name": "keep", "description": "folded text  more", "next": "x"}},
		{"a literal | block keeps newlines; strip and keep markers are accepted",
			"---\na: |\n  one\n  two\nb: >-\n  x\n  y\nc: |+\n  z\n---\n",
			map[string]string{"a": "one\ntwo", "b": "x y", "c": "z"}},
		{"CRLF files read the same",
			"---\r\nname: x\r\ndescription: >\r\n  a\r\n  b\r\n---\r\nbody",
			map[string]string{"name": "x", "description": "a b"}},
		{"indented lines, lists and keys that do not start with a letter are ignored",
			"---\nname: a\ntools:\n  - Read\n  - Edit\n1bad: x\n  nested: y\nlast: z\n---\n",
			map[string]string{"name": "a", "tools": "", "last": "z"}},
		{"a colon inside the value is kept; the last duplicate key wins; keys may hold dashes",
			"---\nargument-hint: <a: b>\nname: first\nname: second\nurl: http://x/y\n---\n",
			map[string]string{"argument-hint": "<a: b>", "name": "second", "url": "http://x/y"}},
		{"a malformed double-quoted value drops its first and last character, like the Node reader",
			"---\nname: \"abc\" trailing\n---\n",
			map[string]string{"name": "abc\" trailin"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { // Swift: FrontmatterTests.swift "<name>"
			if got := ParseFrontmatter(c.text); !reflect.DeepEqual(got, c.want) {
				t.Errorf("got %q\nwant %q", got, c.want)
			}
		})
	}
}

// Swift: FrontmatterTests.swift "no header, an unterminated header or an empty header give no fields"
func TestFrontmatterMissing(t *testing.T) {
	for _, text := range []string{"# just markdown\n", "---\nname: x\n", "---\n---\n", "\n---\nname: x\n---\n", ""} {
		if got := ParseFrontmatter(text); len(got) != 0 {
			t.Errorf("%q gave %q, want no fields", text, got)
		}
	}
}

// Swift: FrontmatterTests.swift "the fixture skills and agents read"
func TestFrontmatterFixture(t *testing.T) {
	dir, err := goldentest.FixturesDir()
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, "home/.claude/skills/ponytail/SKILL.md"))
	if err != nil {
		t.Fatal(err)
	}
	fm := ParseFrontmatter(string(data))
	if fm["name"] != "ponytail" || fm["description"] != "Pick the laziest solution that works" {
		t.Errorf("fm = %q", fm)
	}
}

// Extra (G2.1): invalid UTF-8 in a header line reads as U+FFFD, as Swift's String(decoding:) gives; a
// single-quote value needs two characters; unusual spaces trim like Foundation's whitespacesAndNewlines.
func TestFrontmatterEdges(t *testing.T) {
	if got := ParseFrontmatter("---\nname: a\xe2\x82b\n---\n")["name"]; got != "a\uFFFDb" {
		t.Errorf("name = %q", got)
	}
	if got := ParseFrontmatter("---\nname: '\n---\n")["name"]; got != "'" {
		t.Errorf("a lone quote = %q", got)
	}
	if got := ParseFrontmatter("---\nname: \u00a0\u3000x\u2028\n---\n")["name"]; got != "x" {
		t.Errorf("unicode spaces = %q", got)
	}
	if got := ParseFrontmatter("---\nd: >x\n  y\n---\n"); got["d"] != ">x" {
		t.Errorf(">x is not a block marker, got %q", got)
	}
}
