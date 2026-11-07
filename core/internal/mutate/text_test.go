package mutate

import "testing"

// The two developer_instructions patterns and the header pattern of MutateText.swift ran on ICU (NSRegularExpression); the
// Go port matches them by hand (text.go). These vectors are the cases the patterns decide: block versus line form,
// the multiline ^ and the ICU \s and line terminators.

// Checked against NSRegularExpression (a Swift script with the two patterns) for the ICU cases.
// Swift: MutateText.tomlInstructions / MutateTests.swift "an agent keeps its quotes and backslashes through markdown and TOML"
func TestTomlInstructions(t *testing.T) {
	for _, c := range []struct{ name, in, want string }{
		{"block, one leading newline dropped", "developer_instructions = \"\"\"\nline1\nline2\n\"\"\"\n", "line1\nline2\n"},
		{"block on the key line", `developer_instructions = """inline"""`, "inline"},
		{"literal block keeps escapes", "developer_instructions = '''\nkeep \\n as written'''", `keep \n as written`},
		{"line form with escapes", `developer_instructions = "Say \"hi\" \\ always."`, `Say "hi" \ always.`},
		{"indented key is not at a line start", `  developer_instructions = "x"`, ""},
		{"key after CRLF", "name = \"a\"\r\ndeveloper_instructions = \"x\"", "x"},
		{"key after U+2028", "a developer_instructions = \"x\"", "x"},
		{"key after a vertical tab", "a\vdeveloper_instructions = \"x\"", "x"},
		{"a no-break space counts as \\s", "developer_instructions =\u00a0\"x\"", "x"},
		{"key after NEL", "a\u0085developer_instructions = \"x\"", "x"},
		{"the block form wins over an earlier line form", "developer_instructions = \"line\"\ndeveloper_instructions = \"\"\"block\"\"\"", "block"},
		{"unterminated block falls to the line form (an empty string)", `developer_instructions = """abc`, ""},
		{"unterminated string", `developer_instructions = "unterminated`, ""},
		{"backslash at the end", `developer_instructions = "a\`, ""},
		{"backslash before a line break does not match", "developer_instructions = \"a\\\nb\"", ""},
		{"space and a line break around the equals sign", "developer_instructions\t=\n  \"x\"", "x"},
		{"no key", "name = \"a\"\n", ""},
		{"a key with a longer name", `developer_instructions_extra = "x"`, ""},
	} {
		if got := tomlInstructions(c.in); got != c.want {
			t.Errorf("%s: %q, want %q", c.name, got, c.want)
		}
	}
}

// Swift: MutateText.stripHeader
func TestStripHeader(t *testing.T) {
	for _, c := range []struct{ in, want string }{
		{"---\nname: x\n---\nBody", "Body"},
		{"---\r\nname: x\r\n---\r\n\r\nBody", "\r\nBody"},
		{"no header", "no header"},
		{"---\nunterminated", "---\nunterminated"},
		{"text\n---\nname: x\n---\nBody", "text\n---\nname: x\n---\nBody"},
	} {
		if got := stripHeader(c.in); got != c.want {
			t.Errorf("%q -> %q, want %q", c.in, got, c.want)
		}
	}
}

// Swift: Mutate.validName (NAME_RE of the Node core)
func TestValidName(t *testing.T) {
	for name, ok := range map[string]bool{"a": true, "9a": true, "a-b-9": true, "": false, "-a": false, "A": false, "a_b": false, "a b": false, "a.b": false, "é": false} {
		if (validName(name) == nil) != ok {
			t.Errorf("validName(%q) ok=%v, want %v", name, !ok, ok)
		}
	}
}
