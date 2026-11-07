package toml

import (
	"os"
	"reflect"
	"strings"
	"testing"
)

func str(s string) Value   { return Value{Kind: KindString, Str: s} }
func num(n int64) Value    { return Value{Kind: KindInteger, Int: n} }
func flt(f float64) Value  { return Value{Kind: KindFloat, Float: f} }
func boolean(b bool) Value { return Value{Kind: KindBool, Bool: b} }
func raw(s string) Value   { return Value{Kind: KindRaw, Str: s} }
func arr(items ...Value) Value {
	if items == nil {
		items = []Value{}
	}
	return Value{Kind: KindArray, Items: items}
}

// wantValue fails unless doc has table/key equal to want.
func wantValue(t *testing.T, doc Document, table []string, key string, want Value) {
	t.Helper()
	got, ok := doc.Value(table, key)
	if !ok {
		t.Errorf("%v %q: no value, want %+v", table, key, want)
		return
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("%v %q = %+v, want %+v", table, key, got, want)
	}
}

func wantMissing(t *testing.T, doc Document, table []string, key string) {
	t.Helper()
	if got, ok := doc.Value(table, key); ok {
		t.Errorf("%v %q = %+v, want no value", table, key, got)
	}
}

func wantEqual[T any](t *testing.T, name string, got, want T) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Errorf("%s = %#v, want %#v", name, got, want)
	}
}

// Swift: TOMLReaderTests.swift "scalars at the top level and in tables"
func TestScalars(t *testing.T) {
	doc := Read(`approval_policy = "on-request"   # a comment
count = 1_000
ratio = 0.5
hex = 0xFF
enabled = true
off = false
literal = 'C:\path\no escapes'
when = 1979-05-27 07:32:00

[sandbox_workspace_write]
network_access = false`)
	top := []string{}
	wantValue(t, doc, top, "approval_policy", str("on-request"))
	wantValue(t, doc, top, "count", num(1000))
	wantValue(t, doc, top, "ratio", flt(0.5))
	wantValue(t, doc, top, "hex", num(255))
	wantValue(t, doc, top, "enabled", boolean(true))
	wantValue(t, doc, top, "off", boolean(false))
	wantValue(t, doc, top, "literal", str(`C:\path\no escapes`))
	wantValue(t, doc, top, "when", raw("1979-05-27 07:32:00"))
	wantValue(t, doc, []string{"sandbox_workspace_write"}, "network_access", boolean(false))
	wantEqual(t, "skippedLines", doc.SkippedLines, 0)
}

// Swift: TOMLReaderTests.swift "quoted table names and quoted keys, as Codex writes project trust and permission profiles"
func TestQuotedNames(t *testing.T) {
	doc := Read(`[projects."/Users/someone/work/my app"]
trust_level = "trusted"

[projects.'/tmp/literal path']
trust_level = "untrusted"

[permissions.workspace.filesystem]
":project_roots" = "write"
"/tmp/x.y" = "read"
`)
	wantValue(t, doc, []string{"projects", "/Users/someone/work/my app"}, "trust_level", str("trusted"))
	wantValue(t, doc, []string{"projects", "/tmp/literal path"}, "trust_level", str("untrusted"))
	wantEqual(t, "tablePaths", doc.TablePaths([]string{"projects"}),
		[][]string{{"projects", "/Users/someone/work/my app"}, {"projects", "/tmp/literal path"}})
	fs := doc.EntriesIn([]string{"permissions", "workspace", "filesystem"})
	var keyPaths [][]string
	var values []Value
	for _, e := range fs {
		keyPaths = append(keyPaths, e.KeyPath)
		values = append(values, *e.Value)
	}
	wantEqual(t, "keyPaths", keyPaths, [][]string{{":project_roots"}, {"/tmp/x.y"}})
	wantEqual(t, "values", values, []Value{str("write"), str("read")})
}

// Swift: TOMLReaderTests.swift "dotted keys split outside quotes"
func TestDottedKeys(t *testing.T) {
	doc := Read("a.b.c = 1\n\"x.y\".z = 2\n")
	var keyPaths [][]string
	for _, e := range doc.Entries {
		keyPaths = append(keyPaths, e.KeyPath)
	}
	wantEqual(t, "keyPaths", keyPaths, [][]string{{"a", "b", "c"}, {"x.y", "z"}})
	wantValue(t, doc, []string{}, "a.b.c", num(1))
}

// Swift: TOMLReaderTests.swift "arrays, nested arrays and arrays over several lines with comments"
func TestArrays(t *testing.T) {
	doc := Read(`inline = ["a", "b", 3]
nested = [[1, 2], ["x"]]
writable_roots = [
  "/tmp/one",   # first
  "/tmp/two",
]
empty = []
after = "still read"`)
	top := []string{}
	wantValue(t, doc, top, "inline", arr(str("a"), str("b"), num(3)))
	wantValue(t, doc, top, "nested", arr(arr(num(1), num(2)), arr(str("x"))))
	roots, _ := doc.Value(top, "writable_roots")
	wantEqual(t, "writable_roots strings", roots.Strings(), []string{"/tmp/one", "/tmp/two"})
	wantValue(t, doc, top, "empty", arr())
	wantValue(t, doc, top, "after", str("still read"))
}

// Swift: TOMLReaderTests.swift "inline tables, also nested and holding arrays"
func TestInlineTables(t *testing.T) {
	doc := Read(`point = { x = 1, y = "two", list = [1, 2], inner = { k = true } }
[projects]
"/a/b" = { trust_level = "trusted" }`)
	point, _ := doc.Value([]string{}, "point")
	for key, want := range map[string]Value{"x": num(1), "y": str("two"), "list": arr(num(1), num(2))} {
		if got, ok := point.Get(key); !ok || !reflect.DeepEqual(got, want) {
			t.Errorf("point[%q] = %+v, %v; want %+v", key, got, ok, want)
		}
	}
	inner, _ := point.Get("inner")
	if k, ok := inner.Get("k"); !ok || !reflect.DeepEqual(k, boolean(true)) {
		t.Errorf("point.inner.k = %+v, %v", k, ok)
	}
	ab, _ := doc.Value([]string{"projects"}, "/a/b")
	if got, ok := ab.Get("trust_level"); !ok || !reflect.DeepEqual(got, str("trusted")) {
		t.Errorf("/a/b trust_level = %+v, %v", got, ok)
	}
}

// Swift: TOMLReaderTests.swift "strings: escapes, triple-quoted basic and literal, line-ending backslash"
func TestStrings(t *testing.T) {
	doc := Read("escaped = \"tab\\there \\\"q\\\" \\u00e9 \\\\\"\n" +
		"basic = \"\"\"\nfirst line\nsecond \"quoted\" line\"\"\"\n" +
		"literal = '''\nraw \\n stays\n'''\n" +
		"folded = \"\"\"one \\\n           two\"\"\"\n" +
		"same_line = \"\"\"inline\"\"\"\n" +
		"after = 1")
	top := []string{}
	wantValue(t, doc, top, "escaped", str("tab\there \"q\" é \\"))
	wantValue(t, doc, top, "basic", str("first line\nsecond \"quoted\" line"))
	wantValue(t, doc, top, "literal", str("raw \\n stays\n"))
	wantValue(t, doc, top, "folded", str("one two"))
	wantValue(t, doc, top, "same_line", str("inline"))
	wantValue(t, doc, top, "after", num(1))
}

// Swift: TOMLReaderTests.swift "an agent file's developer_instructions block reads whole"
func TestAgentFile(t *testing.T) {
	doc := Read("name = \"reviewer\"\ndescription = \"Reviews code\"\n" +
		"developer_instructions = \"\"\"\nBe careful.\n# not a comment, inside the string\n[not_a_table]\n\"\"\"")
	top := []string{}
	wantValue(t, doc, top, "name", str("reviewer"))
	wantValue(t, doc, top, "developer_instructions", str("Be careful.\n# not a comment, inside the string\n[not_a_table]\n"))
	wantEqual(t, "tables", len(doc.Tables), 0)
}

// Swift: TOMLReaderTests.swift "a hash inside a string is not a comment"
func TestHashInString(t *testing.T) {
	doc := Read("url = \"https://example.com/#frag\" # real comment\nsingle = 'a # b'\n")
	wantValue(t, doc, []string{}, "url", str("https://example.com/#frag"))
	wantValue(t, doc, []string{}, "single", str("a # b"))
}

// Swift: TOMLReaderTests.swift "array tables are marked and keep their path"
func TestArrayTables(t *testing.T) {
	doc := Read("[[servers]]\nname = \"a\"\n[[servers]]\nname = \"b\"\n")
	wantEqual(t, "tables", doc.Tables, []TableHeader{{Path: []string{"servers"}, IsArray: true}, {Path: []string{"servers"}, IsArray: true}})
	var marks []bool
	for _, e := range doc.Entries {
		marks = append(marks, e.InArrayTable)
	}
	wantEqual(t, "inArrayTable", marks, []bool{true, true})
	wantEqual(t, "entries in servers", len(doc.EntriesIn([]string{"servers"})), 2)
}

// Swift: TOMLReaderTests.swift "the last assignment wins and CRLF files read the same"
func TestLastWinsAndCRLF(t *testing.T) {
	doc := Read("a = 1\r\na = 2\r\n[t]\r\nb = \"x\"\r\nlist = [\r\n  1,\r\n  2\r\n]\r\n")
	wantValue(t, doc, []string{}, "a", num(2))
	wantValue(t, doc, []string{"t"}, "b", str("x"))
	wantValue(t, doc, []string{"t"}, "list", arr(num(1), num(2)))
}

// Swift: TOMLReaderTests.swift "a broken line is skipped and counted; the rest still reads"
func TestTolerant(t *testing.T) {
	doc := Read("good = 1\nthis is not toml\nbad = \"unterminated\nalso_good = 2\n[ok]\nx = 3\n")
	wantValue(t, doc, []string{}, "good", num(1))
	wantValue(t, doc, []string{}, "also_good", num(2))
	wantValue(t, doc, []string{"ok"}, "x", num(3))
	if doc.SkippedLines < 2 {
		t.Errorf("skippedLines = %d, want >= 2", doc.SkippedLines)
	}
	var bad *Entry
	for i := range doc.Entries {
		if doc.Entries[i].Key() == "bad" {
			bad = &doc.Entries[i]
			break
		}
	}
	if bad == nil {
		t.Fatal("the key bad must still count as present")
	}
	if bad.Value != nil {
		t.Errorf("bad value = %+v, want nil", *bad.Value)
	}
}

// Swift: TOMLReaderTests.swift "entries carry their line numbers"
func TestLines(t *testing.T) {
	doc := Read("# header comment\n\na = 1\n[t]\nb = 2\n")
	var lines []int
	for _, e := range doc.Entries {
		lines = append(lines, e.Line)
	}
	wantEqual(t, "lines", lines, []int{3, 5})
}

// Swift: TOMLReaderTests.swift "reads the Codex config of the synthetic fixture"
func TestFixture(t *testing.T) {
	doc := readFixture(t, "../../testdata/fixtures/home/.codex/config.toml")
	wantValue(t, doc, []string{}, "approval_policy", str("on-request"))
	wantValue(t, doc, []string{}, "sandbox_mode", str("workspace-write"))
	wantValue(t, doc, []string{"sandbox_workspace_write"}, "network_access", boolean(false))
	wantEqual(t, "projects", len(doc.TablePaths([]string{"projects"})), 3)
	wantEqual(t, "skippedLines", doc.SkippedLines, 0)
}

// readFixture parses a fixture file; the package parses text only.
func readFixture(t *testing.T, path string) Document {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return Read(string(data))
}

// nested builds "a = " followed by levels of [ and levels of ].
func nested(levels int) string {
	return "a = " + strings.Repeat("[", levels) + strings.Repeat("]", levels)
}

// Swift: ReadHardeningTests.swift "100000 nested brackets or braces are skipped, not recursed into"
func TestDeepNestingIsSkipped(t *testing.T) {
	brackets := Read("a = " + strings.Repeat("[", 100_000) + "\nb = 1\n")
	braces := Read("a = " + strings.Repeat("{ x = ", 100_000) + "\nb = 2\n")
	wantValue(t, brackets, []string{}, "b", num(1))
	wantValue(t, braces, []string{}, "b", num(2))
	if brackets.SkippedLines < 1 || braces.SkippedLines < 1 {
		t.Errorf("skippedLines = %d and %d, want >= 1 each", brackets.SkippedLines, braces.SkippedLines)
	}
}

// Swift: ReadHardeningTests.swift "nesting up to 64 levels reads; one more does not; ordinary nested values are unaffected"
func TestDepthLimit(t *testing.T) {
	if _, ok := Read(nested(64)).Value([]string{}, "a"); !ok {
		t.Error("64 levels must read")
	}
	over := Read(nested(65))
	wantMissing(t, over, []string{}, "a")
	wantEqual(t, "entries at 65 levels (the key still counts as present)", len(over.Entries), 1)
	doc := Read("a = [[1, 2], [3, [4]]]\nt = { x = [1, { y = 2 }] }\n")
	wantValue(t, doc, []string{}, "a", arr(arr(num(1), num(2)), arr(num(3), arr(num(4)))))
	tv, _ := doc.Value([]string{}, "t")
	x, _ := tv.Get("x")
	wantEqual(t, "t.x length", len(x.Items), 2)
}
