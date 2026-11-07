package hashes

import (
	"encoding/hex"
	"encoding/json"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fixtureHome is where goldentest materializes testdata/fixtures/home; golden hook ids and
// project ids hash absolute paths under it (plan B6, FixtureHome.swift:12).
const (
	fixtureHome = "/private/tmp/reins-fixture-home"
	homeToken   = "$HOME"
)

// Swift: JournalTests.swift "sha256 matches CryptoKit and the Node core"
func TestSHA256Hex(t *testing.T) {
	fixed := []struct{ in, want string }{
		{"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
		// `{"model":"y"}\n` hashed by the Node core in a real journal entry.
		{"{\"model\":\"y\"}\n", "e6435d1aa4741b10a9f7a2363778ee376b5a70c5905ff4d1fc6827b82d01f110"},
		{"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
	}
	for _, c := range fixed {
		if got := SHA256Hex([]byte(c.in)); got != c.want {
			t.Errorf("SHA256Hex(%q) = %s, want %s", c.in, got, c.want)
		}
	}
	// The Swift test compares against CryptoKit at these lengths (the 64-byte block edges); Go has
	// no second implementation to compare with, so these check the length and the lowercase format.
	rng := rand.New(rand.NewSource(1))
	for _, n := range []int{0, 1, 55, 56, 63, 64, 65, 119, 120, 1000, 100_000} {
		data := make([]byte, n)
		rng.Read(data)
		got := SHA256Hex(data)
		if _, err := hex.DecodeString(got); err != nil || len(got) != 64 || got != strings.ToLower(got) {
			t.Errorf("length %d: bad format %s", n, got)
		}
	}
}

// Swift: InventoryTests.swift "sha is the first 12 hex digits of SHA-1" (InventoryTests.swift:30-32)
func TestSha(t *testing.T) {
	cases := []struct{ in, want string }{
		{"abc", "a9993e364706"},
		{"", "da39a3ee5e6b"},
		{strings.Repeat("a", 1000), "291e9a6c66994949b57ba5e650361e98fc36b1ba"[:12]},
		// Multi-byte UTF-8 is hashed as its bytes.
		{"é", Sha("\xc3\xa9")},
	}
	for _, c := range cases {
		if got := Sha(c.in); got != c.want {
			t.Errorf("Sha(%.20q) = %s, want %s", c.in, got, c.want)
		}
	}
	// Swift: ActivityTests.swift:621 Inventory.sha("Stop|sh /h/check.sh").count == 12
	if got := Sha("Stop|sh /h/check.sh"); len(got) != 12 {
		t.Errorf("len = %d, want 12", len(got))
	}
}

func TestSHA1HexBlockEdges(t *testing.T) {
	// FIPS 180 vectors and the padding edges around the 56/64 byte boundary.
	cases := []struct{ in, want string }{
		{"abc", "a9993e364706816aba3e25717850c26c9cd0d89d"},
		{"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "84983e441c3bd26ebaae4aa1f95129e5e54670f1"},
		{strings.Repeat("a", 1000), "291e9a6c66994949b57ba5e650361e98fc36b1ba"},
	}
	for _, c := range cases {
		if got := SHA1Hex([]byte(c.in)); got != c.want {
			t.Errorf("SHA1Hex(%.20q) = %s, want %s", c.in, got, c.want)
		}
	}
}

// Swift: InventoryTests.swift "bare" (InventoryTests.swift:37-38)
func TestBare(t *testing.T) {
	cases := []struct{ in, want string }{
		{"neon:neon-postgres", "neon-postgres"},
		{"plain", "plain"},
		{"a:b:c", "c"},
		{"trailing:", ""},
		{":lead", "lead"},
		{"", ""},
	}
	for _, c := range cases {
		if got := Bare(c.in); got != c.want {
			t.Errorf("Bare(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// Swift: InventoryTests.swift "dead hooks" (InventoryTests.swift:164-166): hash is sha("event|command").
func TestHookHashJoin(t *testing.T) {
	if got, want := HookHash("Stop", "sh /h/check.sh"), Sha("Stop|sh /h/check.sh"); got != want {
		t.Errorf("HookHash = %s, want %s", got, want)
	}
	// The separator is part of the identity: moving it changes the hash.
	if HookHash("Stop|a", "b") != HookHash("Stop", "a|b") {
		t.Error("event|command must hash the joined text, so these two collide by design")
	}
	if HookHash("Stop", "x") == HookHash("Stop", "y") || HookHash("Stop", "x") == HookHash("Pre", "x") {
		t.Error("event and command must both feed the hash")
	}
}

func goldenDir(t *testing.T) string {
	t.Helper()
	dir := filepath.Join("..", "..", "testdata", "fixtures")
	if _, err := os.Stat(dir); err != nil {
		t.Skipf("fixtures not found: %v", err)
	}
	return dir
}

func expandHome(s string) string { return strings.ReplaceAll(s, homeToken, fixtureHome) }

type goldenHook struct {
	ID      string  `json:"id"`
	CLI     string  `json:"cli"`
	Event   string  `json:"event"`
	Matcher *string `json:"matcher"`
	Command string  `json:"command"`
	Owner   string  `json:"owner"`
	Hash    string  `json:"hash"`
	File    string  `json:"file"`
	Scope   string  `json:"scope"`
	Project *string `json:"project"`
}

type goldenItem struct {
	ID      string  `json:"id"`
	Project *string `json:"project"`
}

// Recomputes every hook hash and id, and every project id, in golden/inventory.json from the
// real inputs: the golden stores $HOME-token paths, the ids were hashed over the materialized
// root. Seed layout per InventoryReader.swift:165: owner|event|matcher|command[|file if project];
// an owner of "user" is the Swift nil owner, which seeds as "".
func TestGoldenInventoryHookAndProjectIDs(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join(goldenDir(t), "golden", "inventory.json"))
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		Inventory struct {
			Hooks []goldenHook `json:"hooks"`
			Items []goldenItem `json:"items"`
		} `json:"inventory"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	hooks := doc.Inventory.Hooks
	if len(hooks) < 9 {
		t.Fatalf("expected at least 9 golden hooks, got %d", len(hooks))
	}
	projectHooks := 0
	for _, h := range hooks {
		command := expandHome(h.Command)
		if got := HookHash(h.Event, command); got != h.Hash {
			t.Errorf("%s: hash = %s, want %s (command %q)", h.ID, got, h.Hash, h.Command)
		}
		owner := h.Owner
		if owner == "user" {
			owner = ""
		}
		matcher := ""
		if h.Matcher != nil {
			matcher = *h.Matcher
		}
		seed := owner + "|" + h.Event + "|" + matcher + "|" + command
		if h.Scope == "project" {
			projectHooks++
			seed += "|" + expandHome(h.File)
		}
		if got := h.CLI + ":hook:" + Sha(seed); got != h.ID {
			t.Errorf("id = %s, want %s (seed %q)", got, h.ID, seed)
		}
	}
	if projectHooks == 0 {
		t.Error("no project-scoped hook covered, the file part of the seed is untested")
	}

	// "project:<sha(project path)>" inside item ids.
	projects := 0
	for _, it := range doc.Inventory.Items {
		if it.Project == nil {
			continue
		}
		want := "project:" + Sha(expandHome(*it.Project)) + ":"
		if !strings.Contains(it.ID, want) {
			t.Errorf("item id %s does not contain %s", it.ID, want)
		}
		projects++
	}
	if projects == 0 {
		t.Error("no project items covered")
	}
}

// golden/mutate.json "initial" maps every fixture file to the SHA-1 of its content (40 hex).
// The hash is over the stored bytes verbatim: 187 of the 220 files contain the literal $HOME
// token and still match unsubstituted, so a harness must not rewrite tokens before hashing.
func TestGoldenMutateContentHashes(t *testing.T) {
	dir := goldenDir(t)
	raw, err := os.ReadFile(filepath.Join(dir, "golden", "mutate.json"))
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		Initial map[string]string `json:"initial"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	if len(doc.Initial) < 200 {
		t.Fatalf("expected the 220 fixture file hashes, got %d", len(doc.Initial))
	}
	for rel, want := range doc.Initial {
		data, err := os.ReadFile(filepath.Join(dir, "home", filepath.FromSlash(rel)))
		if err != nil {
			t.Errorf("%s: %v", rel, err)
			continue
		}
		if got := SHA1Hex(data); got != want {
			t.Errorf("%s: sha1 = %s, want %s", rel, got, want)
		}
	}
}
