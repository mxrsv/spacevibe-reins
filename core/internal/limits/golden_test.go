package limits

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/goldentest"
	"spacevibe.dev/core/internal/hashes"
)

// expectedGoldenCases is LimitsGoldenTests.expectedCases.
const expectedGoldenCases = 27

// The Swift writer (CanonicalJSON) and the Go writer (goldentest.Canonical) must agree: the committed golden,
// parsed and written again by Go, is the same bytes.
func TestGoldenLimitsCanonicalReproducesFile(t *testing.T) {
	dir, err := goldentest.FixturesDir()
	if err != nil {
		t.Fatal(err)
	}
	file, err := os.ReadFile(filepath.Join(dir, "golden", "limits.json"))
	if err != nil {
		t.Fatal(err)
	}
	tree, err := goldentest.LoadGolden("limits")
	if err != nil {
		t.Fatal(err)
	}
	again, err := goldentest.Canonical(tree)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(file, again) {
		t.Fatalf("Go canonical bytes differ from the Swift-written file\n%s",
			goldentest.UnifiedDiff("limits.json (Swift)", "limits.json (Go Canonical)", string(file), string(again)))
	}
	sum, _ := goldentest.CanonicalSHA256(tree)
	t.Logf("limits.json: Go Canonical reproduces the file byte for byte, sha256 %s (%d bytes)", sum, len(file))
}

// Swift: LimitsGoldenTests.swift "every Limits scenario reads the same as the committed golden, byte for byte".
// Each case's files are written into a temporary home, limits.Read runs at the case's fixed now, and the result
// (the Swift projection: cli, state, at, windows with the current flag, plan, source) must match the golden.
func TestGoldenLimits(t *testing.T) {
	golden, err := goldentest.LoadGolden("limits")
	if err != nil {
		t.Fatal(err)
	}
	top := golden.(map[string]any)
	cases := top["cases"].([]any)
	goldentest.AssertCaseCount(t, "limits", len(cases), expectedGoldenCases)
	if len(cases) != expectedGoldenCases {
		t.Fatalf("limits golden has %d cases, want %d", len(cases), expectedGoldenCases)
	}

	got := make([]any, len(cases))
	names := map[string]bool{}
	states := map[string]bool{}
	for i, raw := range cases {
		c := raw.(map[string]any)
		name := c["name"].(string)
		if names[name] {
			t.Fatalf("case name %s repeats", name)
		}
		names[name] = true
		result := runGoldenCase(t, c)
		for _, entry := range result.([]any) {
			states[entry.(map[string]any)["state"].(string)] = true
		}
		got[i] = map[string]any{"name": name, "now": c["now"], "input": c["input"], "result": result}

		want, _ := goldentest.Canonical(c["result"])
		have, _ := goldentest.Canonical(result)
		if !bytes.Equal(want, have) {
			t.Errorf("case %s: canonical bytes differ\n%s", name, goldentest.UnifiedDiff(name+" (golden)", name+" (Go)", string(want), string(have)))
		}
	}
	for _, state := range []string{"measured", "notRecorded", "unreadable", "notMeasurable", "notInstalled"} {
		if !states[state] {
			t.Errorf("no golden case reads as %s", state)
		}
	}
	whole := map[string]any{"format": top["format"], "environment": top["environment"], "tokens": top["tokens"], "cases": got}
	goldentest.AssertCanonicalEqual(t, "limits.json", golden, whole)
}

// runGoldenCase recreates the case's input files in a temporary home, runs limits.Read at the case's now and
// returns the projected result as a JSON tree.
func runGoldenCase(t *testing.T, c map[string]any) any {
	t.Helper()
	home := newTempHome(t)
	input := c["input"].(map[string]any)
	home.unsetClaude = input["unsetClaudeConfigDir"].(bool)
	now := goldenNumber(t, c["now"])

	for _, dir := range input["dirs"].([]any) {
		home.mkdir(dir.(string))
	}
	for _, raw := range input["files"].([]any) {
		file := raw.(map[string]any)
		var text string
		if repeated, ok := file["repeat"].(map[string]any); ok {
			text = strings.Repeat(repeated["text"].(string), int(goldenNumber(t, repeated["count"])))
		} else {
			text = resolveAccounts(home, file["text"].(string))
		}
		path := home.write(file["path"].(string), text)
		setModified(t, path, goldenNumber(t, file["mtime"]))
	}
	for _, fifo := range input["fifos"].([]any) {
		mkfifo(t, home.path(fifo.(string)))
	}

	result := home.read(now)
	data, err := json.Marshal(result.Limits)
	if err != nil {
		t.Fatal(err)
	}
	var tree any
	if err := json.Unmarshal(data, &tree); err != nil {
		t.Fatal(err)
	}
	return goldentest.HomeToken(tree, home.root)
}

// resolveAccounts turns `$ACCOUNT_KEY(a,o)` into the key the collector derives for account a and organization o
// in this home: the hex SHA-256 of "<claude root>\n<a>\n<o>" (LimitsClaudeStatusline.swift:17-22).
func resolveAccounts(home tempHome, text string) string {
	const token = "$ACCOUNT_KEY("
	for {
		start := strings.Index(text, token)
		if start < 0 {
			return text
		}
		end := strings.Index(text[start:], ")")
		parts := strings.Split(text[start+len(token):start+end], ",")
		key := hashes.SHA256Hex([]byte(home.roots().Claude.Root + "\n" + parts[0] + "\n" + parts[1]))
		text = text[:start] + key + text[start+end+1:]
	}
}

func goldenNumber(t *testing.T, v any) float64 {
	t.Helper()
	n, ok := v.(json.Number)
	if !ok {
		t.Fatalf("expected a number, got %T", v)
	}
	f, err := strconv.ParseFloat(string(n), 64)
	if err != nil {
		t.Fatal(err)
	}
	return f
}
