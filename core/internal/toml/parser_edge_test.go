package toml

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// The vectors below are extra to the Swift suite. Each expected value was also produced by the
// Swift TOMLReader (differential run over about 85000 generated files, identical output).

func TestBareTokens(t *testing.T) {
	for _, tc := range []struct {
		token string
		want  Value
	}{
		{"-5", num(-5)},
		{"+5", num(5)},
		{"0o17", num(15)},
		{"0b101", num(5)},
		{"0xfe", num(254)},
		{"0x-5", num(-5)},
		{"0b2", raw("0b2")},
		{"9223372036854775807", num(math.MaxInt64)},
		{"9223372036854775808", raw("9223372036854775808")},
		{"1__0", num(10)},
		{"1e5", flt(1e5)},
		{"1E-3", flt(1e-3)},
		{".5", flt(0.5)},
		{"1.e5", flt(1e5)},
		{"1e999", flt(math.Inf(1))},
		{"5.", raw("5.")},
		{"1e", raw("1e")},
		{"0x1.8p1", flt(3)},
		{"0x1.8", flt(1.5)},
		{"-0x1e", flt(-30)},
		{"0X1e", raw("0X1e")},
		{"inf", raw("inf")},
		{"nan", raw("nan")},
		{"True", raw("True")},
		{"1979-05-27", raw("1979-05-27")},
		{"1979-05-27T07:32:00Z", raw("1979-05-27T07:32:00Z")},
		{"07:32:00", raw("07:32:00")},
	} {
		doc := Read("k = " + tc.token + "\n")
		wantValue(t, doc, []string{}, "k", tc.want)
		if doc.SkippedLines != 0 {
			t.Errorf("%q skipped %d lines", tc.token, doc.SkippedLines)
		}
	}
}

func TestDatetimeWithSpace(t *testing.T) {
	// a space after a 10-character date only joins a time that holds a colon
	doc := Read("a = 1979-05-27 x\nb = 1979-05-27 07:32:00.5 # c\n")
	wantValue(t, doc, []string{}, "b", raw("1979-05-27 07:32:00.5"))
	if _, ok := doc.Value([]string{}, "a"); !ok {
		t.Error("a must read as the raw date")
	}
	wantEqual(t, "skippedLines (the stray x)", doc.SkippedLines, 1)
}

func TestNulEndsAFloat(t *testing.T) {
	// Swift's Double(String) goes through C strtod; a NUL byte ends the number there.
	wantValue(t, Read("k = 1.5\x00junk\n"), []string{}, "k", flt(1.5))
	wantValue(t, Read("k = 1\x00\n"), []string{}, "k", raw("1\x00"))
}

func TestEscapes(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{`"\q"`, `\q`},               // unknown escape kept as written
		{`"\e\b\f\r"`, "\x1b\b\f\r"}, // the TOML 1.1 escapes
		{`"\U0001F600"`, "\U0001F600"},
		{`"\u+0e9"`, "é"}, // Swift's radix parser accepts a plus sign
		{`"\u-000"`, "\x00"},
		{`"\u0000"`, "\x00"},
	} {
		wantValue(t, Read("k = "+tc.in+"\n"), []string{}, "k", str(tc.want))
	}
	// unreadable escapes make the value nil and skip the line
	for _, in := range []string{`"\ud800"`, `"\U00110000"`, `"\u12"`, `"\u-001"`, `"\uzzzz"`} {
		doc := Read("k = " + in + "\nnext = 1\n")
		wantMissing(t, doc, []string{}, "k")
		wantValue(t, doc, []string{}, "next", num(1))
		wantEqual(t, in+" skipped", doc.SkippedLines, 1)
	}
}

func TestMultilineQuotes(t *testing.T) {
	// up to two quotes may sit right before the closing delimiter
	for _, tc := range []struct{ in, want string }{
		{`"""x""""`, `x"`},
		{`"""x"""""`, `x""`},
		{"'''x''''", "x'"},
		{"\"\"\"\r\nx\"\"\"", "x"},
		{`"""a\"""b"""`, `a"""b`},
	} {
		wantValue(t, Read("k = "+tc.in+"\n"), []string{}, "k", str(tc.want))
	}
	wantMissing(t, Read("k = \"\"\"never closed\n"), []string{}, "k")
}

func TestHeaders(t *testing.T) {
	doc := Read("[ a . \"b c\" ]\nx=1\n[a.b]\n[ok] trailing\n[a.\"b c\"]\ny=2\n")
	wantEqual(t, "skippedLines", doc.SkippedLines, 1) // "trailing" after [ok]
	wantEqual(t, "tablePaths(a)", doc.TablePaths([]string{"a"}), [][]string{{"a", "b c"}, {"a", "b"}})
	wantEqual(t, "tablePaths()", len(doc.TablePaths(nil)), 3)
	wantValue(t, doc, []string{"a", "b c"}, "y", num(2))
	// a header that is not closed is skipped and the keys after it stay in the previous table
	bad := Read("[t]\n[broken\nk = 1\n")
	wantEqual(t, "bad header skipped", bad.SkippedLines, 1)
	wantValue(t, bad, []string{"t"}, "k", num(1))
}

func TestLastEntryWinsEvenWhenUnreadable(t *testing.T) {
	doc := Read("a = 1\na = \"open\n")
	wantMissing(t, doc, []string{}, "a")
	wantEqual(t, "entries", len(doc.Entries), 2)
}

func TestInlineTableLastKeyWins(t *testing.T) {
	doc := Read("t = { a = 1, a = 2, b.c = 3 }\n")
	tv, _ := doc.Value([]string{}, "t")
	a, _ := tv.Get("a")
	wantEqual(t, "a", a, num(2))
	bc, ok := tv.Get("b.c")
	wantEqual(t, "b.c", []any{bc, ok}, []any{num(3), true})
	if _, ok := str("x").Get("a"); ok {
		t.Error("Get on a non-table must report no value")
	}
	wantMissing(t, Read("t = { a = 1,, }\nu = 1\n"), []string{}, "t")
}

func TestAccessors(t *testing.T) {
	s, ok := str("x").AsString()
	wantEqual(t, "AsString", []any{s, ok}, []any{"x", true})
	if _, ok := num(1).AsString(); ok {
		t.Error("AsString on an integer")
	}
	if b, ok := boolean(true).AsBool(); !ok || !b {
		t.Error("AsBool")
	}
	if n, ok := num(7).AsInt(); !ok || n != 7 {
		t.Error("AsInt")
	}
	if _, ok := arr().AsArray(); !ok {
		t.Error("AsArray")
	}
	if _, ok := (Value{Kind: KindTable}).AsTable(); !ok {
		t.Error("AsTable")
	}
	wantEqual(t, "Strings skips other kinds", arr(str("a"), num(1), str("b")).Strings(), []string{"a", "b"})
	wantEqual(t, "Strings of a non-array", num(1).Strings(), []string{})
}

func TestMalformedLines(t *testing.T) {
	doc := Read("= 1\nk\nk = \nk2 = 1 2\n\"open = 1\n'lit\n")
	// "= 1", "k" (no equals), "k = " (no value), "2" after k2's value, and the two open quotes
	wantEqual(t, "skippedLines", doc.SkippedLines, 6)
	wantValue(t, doc, []string{}, "k2", num(1))
}

func TestEmptyAndTriviaOnly(t *testing.T) {
	for _, text := range []string{"", "\n\n", "# only a comment", "  \t\r\n"} {
		doc := Read(text)
		if len(doc.Entries)+len(doc.Tables)+doc.SkippedLines != 0 {
			t.Errorf("%q: %+v", text, doc)
		}
	}
}

func TestReadFileBOMAndEncoding(t *testing.T) {
	dir := t.TempDir()
	write := func(name string, data []byte) string {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, data, 0o600); err != nil {
			t.Fatal(err)
		}
		return p
	}
	// Foundation's String(data:encoding:) drops a leading BOM, so the first key still reads
	doc, err := ReadFile(write("bom.toml", []byte("\xef\xbb\xbfa = 1\n")))
	if err != nil {
		t.Fatal(err)
	}
	wantValue(t, doc, []string{}, "a", num(1))
	wantEqual(t, "skipped", doc.SkippedLines, 0)
	if _, err := ReadFile(write("bad.toml", []byte("a = \"\xff\"\n"))); err != ErrUnreadable {
		t.Errorf("invalid UTF-8: err = %v, want ErrUnreadable", err)
	}
	if _, err := ReadFile(dir); err != ErrUnreadable {
		t.Errorf("a directory: err = %v, want ErrUnreadable", err)
	}
	// the BOM as text (Read, not ReadFile) is not a key character: the line is skipped
	wantEqual(t, "BOM via Read", Read("\xef\xbb\xbfa = 1\n").SkippedLines, 1)
}

func TestCodexQuirksFixture(t *testing.T) {
	// the fixture go-toml/v2 rejects (duplicate keys and tables) reads here, last assignment winning
	doc, err := ReadFile("../../testdata/fixtures/rules-home/codex-quirks/.codex/config.toml")
	if err != nil {
		t.Fatal(err)
	}
	wantValue(t, doc, []string{}, "approval_policy", str("never"))
	wantValue(t, doc, []string{"projects", "/work/one"}, "trust_level", str("untrusted"))
	wantValue(t, doc, []string{"permissions", "noisy", "network"}, "bad key", boolean(true))
	wantEqual(t, "skippedLines", doc.SkippedLines, 0)
	wantEqual(t, "hooks entries", len(doc.EntriesIn([]string{"hooks"})), 2)
}

// G-fix.21: TablePaths is linear. 50k distinct headers (the old scan took minutes) must finish
// well under 2 s, and duplicates and look-alike paths still collapse correctly.
func TestTablePathsLinearOn50kHeaders(t *testing.T) {
	const n = 50_000
	var b strings.Builder
	for i := 0; i < n; i++ {
		fmt.Fprintf(&b, "[projects.\"/work/p%d\"]\n", i)
	}
	b.WriteString("[projects.\"/work/p0\"]\n[other]\n")
	doc := Read(b.String())
	start := time.Now()
	got := doc.TablePaths([]string{"projects"})
	elapsed := time.Since(start)
	if len(got) != n {
		t.Fatalf("got %d paths, want %d", len(got), n)
	}
	if got[0][1] != "/work/p0" || got[n-1][1] != fmt.Sprintf("/work/p%d", n-1) {
		t.Errorf("order: %v ... %v", got[0], got[n-1])
	}
	if elapsed > 2*time.Second {
		t.Fatalf("TablePaths took %v for %d headers", elapsed, n)
	}
	if all := doc.TablePaths(nil); len(all) != n+1 {
		t.Errorf("TablePaths(nil) = %d, want %d", len(all), n+1)
	}
}

func TestTablePathsKeepsLookAlikesApart(t *testing.T) {
	doc := Read("[\"a b\".c]\n[a.\"b c\"]\n[\"a\".\"b c\"]\n[\"a b\".c]\n")
	got := doc.TablePaths(nil)
	wantEqual(t, "paths", got, [][]string{{"a b", "c"}, {"a", "b c"}})
}
