package ojson

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"
)

func readFixture(t *testing.T) []byte {
	t.Helper()
	data, err := os.ReadFile(settingsFixture)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

// Swift: OrderedJSONTests.swift "invalid JSON is rejected with a position, never with file content" (16 arguments)
func TestRejectsInvalidJSON(t *testing.T) {
	cases := []struct {
		text    string
		problem Problem
	}{
		{"", UnexpectedEnd}, {"{", UnexpectedEnd}, {`{"a":1,}`, ExpectedKey}, {"[1,]", UnexpectedCharacter},
		{`{"a" 1}`, ExpectedColon}, {`{"a":1 "b":2}`, ExpectedCommaOrEnd}, {"[01]", InvalidNumber},
		{`{"a":1} x`, TrailingContent}, {"// c\n{}", UnexpectedCharacter}, {`{'a':1}`, ExpectedKey},
		{"\"a\nb\"", ControlCharacterInString}, {`"\x"`, InvalidEscape}, {`"\u12g4"`, InvalidEscape},
		{"[1 2]", ExpectedCommaOrEnd}, {"\uFEFF{}", UnexpectedCharacter}, {"tru", UnexpectedCharacter},
	}
	for _, c := range cases {
		t.Run(fmt.Sprintf("%q", c.text), func(t *testing.T) {
			_, err := ParseString(c.text)
			var se *SyntaxError
			if !errors.As(err, &se) {
				t.Fatalf("error = %v, want a *SyntaxError", err)
			}
			if se.Problem != c.problem {
				t.Errorf("problem = %s, want %s", se.Problem, c.problem)
			}
			if se.Line < 1 || se.Column < 1 {
				t.Errorf("position %d:%d must be 1-based", se.Line, se.Column)
			}
		})
	}
}

// Extra: exact positions (1-based line, 1-based byte column) as Swift's fail() computes them.
func TestSyntaxErrorPositions(t *testing.T) {
	cases := []struct {
		text         string
		line, column int
	}{
		{"", 1, 1},
		{"{", 1, 2},
		{"[1,]", 1, 4},
		{"{\n  \"a\" 1}", 2, 7},
		{"\"\\x\"", 1, 3},
		{"\"\\u12g4\"", 1, 6},
		{"\"a\nb\"", 1, 3},
		{"[\n\n  -]", 3, 3},
		{"{\"é\":1 x}", 1, 9}, // the column counts bytes
		{"{} x", 1, 4},
	}
	for _, c := range cases {
		t.Run(fmt.Sprintf("%q", c.text), func(t *testing.T) {
			_, err := ParseString(c.text)
			var se *SyntaxError
			if !errors.As(err, &se) {
				t.Fatalf("error = %v", err)
			}
			if se.Line != c.line || se.Column != c.column {
				t.Errorf("position %d:%d, want %d:%d", se.Line, se.Column, c.line, c.column)
			}
		})
	}
}

// Extra: more grammar the strict parser must refuse.
func TestRejectsMoreInvalidJSON(t *testing.T) {
	for _, text := range []string{
		"-", "1.", ".5", "+1", "1e", "1e+", "00", "-01", "0x10", "1.5.2", "NaN", "Infinity", "True", "nul", "nulll",
		`{"a"}`, `{"a":}`, `{,}`, `[,]`, `[1,,2]`, `{"a":1,"a"}`, `"abc`, `"\`, `"\u12`, `"\ud800\u12`,
		"[1] [2]", "{} {}", "\x00", "[\x0b1]", "\u00a0{}", "'a'", `{"a":1}}`, `]`,
	} {
		if _, err := ParseString(text); err == nil {
			t.Errorf("accepted %q", text)
		}
	}
	for _, text := range []string{" \t\r\n{} \t\r\n", "0", "-0.5e-3", "[0,-1,1E5]", `""`, "null", "true", "false"} {
		if _, err := ParseString(text); err != nil {
			t.Errorf("rejected %q: %v", text, err)
		}
	}
}

// Swift: OrderedJSONTests.swift "an error never contains the text of the file"
// Extended (S-R3): every failure kind, every way of printing the error.
func TestErrorsNeverCarryFileContent(t *testing.T) {
	const secret = "sk-this-must-never-appear"
	broken := []string{
		`{"token": "` + secret + `" "next": 1}`,
		`{"` + secret + `": }`,
		`{"` + secret + `" 1}`,
		`["` + secret + `",]`,
		`["` + secret + `" 1]`,
		`{"a": ` + secret + `}`,
		`{"a": 1} ` + secret,
		`"` + secret + `\x"`,
		`"` + secret + "\n\"",
		`"` + secret + `\u12g4"`,
		`"` + secret,
		`[` + secret + `]`,
		`-` + secret,
		`1` + secret,
		`tru` + secret,
		`{'` + secret + `':1}`,
		"{\"" + secret + "\":\xff}",
		strings.Repeat("[", MaxDepth+1) + `"` + secret + `"`,
		strings.Repeat(`{"`+secret+`":`, MaxDepth+1),
	}
	for i, text := range broken {
		_, err := ParseString(text)
		if err == nil {
			t.Errorf("case %d: accepted", i)
			continue
		}
		assertBlind(t, err, secret)
	}
}

func assertBlind(t *testing.T, err error, secret string) {
	t.Helper()
	for _, shown := range []string{err.Error(), fmt.Sprintf("%v", err), fmt.Sprintf("%+v", err), fmt.Sprintf("%#v", err), fmt.Sprintf("%q", err), fmt.Sprintf("%s", err)} {
		if strings.Contains(shown, secret) {
			t.Errorf("error %q contains file content", shown)
		}
	}
}

// Extra (S-R3): edit errors name no key, index or value either.
func TestEditErrorsNeverCarryNames(t *testing.T) {
	const secret = "sk-this-must-never-appear"
	d := mustDoc(t, `{"`+secret+`":"v","list":[1]}`)
	attempts := []func() error{
		func() error { _, err := d.Remove(Path(secret + "-missing")); return err },
		func() error { _, err := d.Set(Path(secret, "deeper"), Null()); return err },
		func() error { _, err := d.Append(Null(), Path(secret)); return err },
		func() error { _, err := d.Set(Path("n"), Number(secret)); return err },
		func() error { _, err := d.Set(Path("list", secret), Null()); return err },
	}
	for i, attempt := range attempts {
		err := attempt()
		if err == nil {
			t.Errorf("attempt %d: no error", i)
			continue
		}
		assertBlind(t, err, secret)
	}
}

// Swift: OrderedJSONTests.swift "invalid UTF-8 is rejected" (one case), extended.
func TestRejectsInvalidUTF8(t *testing.T) {
	cases := []struct {
		name string
		data []byte
	}{
		{"lone 0xFF in an object (Swift vector)", []byte{0x7B, 0xFF, 0x7D}},
		{"0xFF inside a string", []byte("{\"a\":\"x\xffy\"}")},
		{"overlong NUL C0 80", []byte("\"\xc0\x80\"")},
		{"encoded surrogate ED A0 80", []byte("\"\xed\xa0\x80\"")},
		{"beyond U+10FFFF F4 90 80 80", []byte("\"\xf4\x90\x80\x80\"")},
		{"truncated sequence at the end", []byte("\"\xe2\x82")},
		{"stray continuation byte", []byte("\"\x80\"")},
		{"invalid bytes after a valid document", []byte("{} \xff")},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if _, err := Parse(c.data); !errors.Is(err, ErrInvalidUTF8) {
				t.Errorf("error = %v, want ErrInvalidUTF8", err)
			}
		})
	}
	// Valid multi-byte text passes, including 4-byte sequences and the BOM-free U+FEFF inside a string.
	if _, err := ParseString("{\"k\":\"é € 🙂 \uFEFF\"}"); err != nil {
		t.Errorf("valid UTF-8 rejected: %v", err)
	}
}

// Swift: OrderedJSONTests.swift "absurd nesting is rejected instead of overflowing the stack"
// Extended with the exact boundary: depth 256 is accepted, depth 257 is not.
func TestNestingLimit(t *testing.T) {
	if MaxDepth != 256 {
		t.Fatalf("MaxDepth = %d, want 256", MaxDepth)
	}
	nest := func(open, closing string, n int) string { return strings.Repeat(open, n) + strings.Repeat(closing, n) }
	cases := []struct {
		name   string
		text   string
		tooDep bool
	}{
		{"Swift vector: 261 arrays", nest("[", "]", MaxDepth+5), true},
		{"Swift vector: 100 arrays", nest("[", "]", 100), false},
		{"256 arrays", nest("[", "]", 256), false},
		{"257 arrays", nest("[", "]", 257), true},
		{"256 objects", strings.Repeat(`{"a":`, 255) + `{}` + strings.Repeat("}", 255), false},
		{"257 objects", strings.Repeat(`{"a":`, 256) + `{}` + strings.Repeat("}", 256), true},
		{"256 mixed", strings.Repeat(`[{"a":`, 128) + `1` + strings.Repeat("}]", 128), false},
		{"257 mixed", `[` + strings.Repeat(`[{"a":`, 128) + `1` + strings.Repeat("}]", 128) + `]`, true},
		{"depth is per path, not a running total", "[" + strings.Repeat("[],", 999) + "[]]", false},
		{"too deep and unterminated", strings.Repeat("[", 5000), true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := ParseString(c.text)
			if c.tooDep {
				if !errors.Is(err, ErrTooDeep) {
					t.Errorf("error = %v, want ErrTooDeep", err)
				}
			} else if err != nil {
				t.Errorf("rejected: %v", err)
			}
		})
	}
}

// Swift: OrderedJSONTests.swift "pretty prints a new document in a chosen indent"
func TestPretty(t *testing.T) {
	value := Object(Member{"a", Array(Int(1), String("x"))}, Member{"o", Object()}, Member{"e", Array()})
	got, err := Pretty(value)
	if err != nil {
		t.Fatal(err)
	}
	if want := "{\n  \"a\": [\n    1,\n    \"x\"\n  ],\n  \"o\": {},\n  \"e\": []\n}\n"; got != want {
		t.Errorf("Pretty =\n%q\nwant\n%q", got, want)
	}
	got, err = PrettyStyled(Object(Member{"a", Int(1)}), "\t", "\r\n", false)
	if err != nil {
		t.Fatal(err)
	}
	if want := "{\r\n\t\"a\": 1\r\n}"; got != want {
		t.Errorf("PrettyStyled = %q, want %q", got, want)
	}
	if _, err := Pretty(Array(Number("1e"))); !errors.Is(err, ErrInvalidValue) {
		t.Errorf("error = %v, want ErrInvalidValue", err)
	}
	// Pretty output reads back as the same value and round-trips.
	back := mustDoc(t, got)
	if !back.Root().Equal(Object(Member{"a", Int(1)})) {
		t.Error("Pretty output did not read back")
	}
}
