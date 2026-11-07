package pricing

import (
	"math"
	"strings"
	"testing"
)

// swiftTable is the literal table of Sources/ReinsCore/Pricing.swift. In Go the table is the
// embedded JSON, so this is the expected value, not the source.
var swiftTable = Table{
	"claude-opus-5-5":   {Input: 4.0, Output: 20.0, CacheWrite: 5.0, CacheWriteLong: 8.0, CacheRead: 0.2},
	"claude-sonnet-5-5": {Input: 2.0, Output: 10.0, CacheWrite: 2.5, CacheWriteLong: 4.0, CacheRead: 0.1},
	"claude-opus-4-6":   {Input: 5.0, Output: 25.0, CacheWrite: 6.25, CacheWriteLong: 10.0, CacheRead: 0.5},
	"claude-sonnet-4-6": {Input: 3.0, Output: 15.0, CacheWrite: 3.75, CacheWriteLong: 6.0, CacheRead: 0.3},
	"claude-haiku-4-5":  {Input: 1.0, Output: 5.0, CacheWrite: 1.25, CacheWriteLong: 2.0, CacheRead: 0.1},
	"gpt-6-astra":       {Input: 10.0, Output: 50.0, CacheWrite: 12.5, CacheWriteLong: 25.0, CacheRead: 1.0},
	"gpt-6.1-sol":       {Input: 2.0, Output: 10.0, CacheWrite: 2.5, CacheWriteLong: 5.0, CacheRead: 0.1},
	"gpt-6-luna":        {Input: 0.1, Output: 0.5, CacheWrite: 0.125, CacheWriteLong: 0.25, CacheRead: 0.01},
}

// Swift: ActivityPricingTests.swift "the Swift price table equals core/internal/pricing/pricing.json"
func TestEmbeddedTableEqualsSwiftLiteral(t *testing.T) {
	models := Models()
	if len(models) != len(swiftTable) {
		t.Fatalf("embedded table has %d models, want %d", len(models), len(swiftTable))
	}
	for name, want := range swiftTable {
		got, ok := models[name]
		if !ok {
			t.Errorf("%s is missing from pricing.json", name)
			continue
		}
		if got != want {
			t.Errorf("%s = %+v, want %+v", name, got, want)
		}
	}
}

// Every embedded entry parses with all five rates finite and positive.
func TestEmbeddedEntriesParse(t *testing.T) {
	for name, p := range Models() {
		for field, rate := range map[string]float64{"input": p.Input, "output": p.Output, "cacheWrite": p.CacheWrite, "cacheWriteLong": p.CacheWriteLong, "cacheRead": p.CacheRead} {
			if !(rate > 0) || math.IsInf(rate, 0) {
				t.Errorf("%s %s = %v", name, field, rate)
			}
		}
	}
}

func TestLoadRejectsBadTables(t *testing.T) {
	good := `{"models":{"m":{"input":1,"output":2,"cacheWrite":3,"cacheWriteLong":4,"cacheRead":5}}}`
	table, err := Load([]byte(good))
	if err != nil || table["m"] != (ModelPrice{1, 2, 3, 4, 5}) {
		t.Fatalf("good table: %+v, %v", table, err)
	}
	bad := map[string]string{
		"not json":        `{"models":`,
		"no models":       `{"models":{}}`,
		"missing models":  `{}`,
		"missing a rate":  `{"models":{"secret-token-xyz":{"input":1,"output":2,"cacheWrite":3,"cacheWriteLong":4}}}`,
		"negative":        `{"models":{"m":{"input":-1,"output":2,"cacheWrite":3,"cacheWriteLong":4,"cacheRead":5}}}`,
		"string rate":     `{"models":{"m":{"input":"1","output":2,"cacheWrite":3,"cacheWriteLong":4,"cacheRead":5}}}`,
		"null rate":       `{"models":{"m":{"input":null,"output":2,"cacheWrite":3,"cacheWriteLong":4,"cacheRead":5}}}`,
		"overflow number": `{"models":{"m":{"input":1e999,"output":2,"cacheWrite":3,"cacheWriteLong":4,"cacheRead":5}}}`,
	}
	for name, doc := range bad {
		_, err := Load([]byte(doc))
		if err == nil {
			t.Errorf("%s: want an error", name)
			continue
		}
		if strings.Contains(err.Error(), "secret-token-xyz") {
			t.Errorf("%s: error quotes the data: %v", name, err)
		}
	}
}

// Swift: ActivityTests.swift (Pricing.price(for:) lines 375-377), plus the cleanName rules of Pricing.swift.
func TestPriceLookup(t *testing.T) {
	table := Models()
	tests := []struct {
		model string
		input float64 // 0 means no price
	}{
		{"claude-sonnet-4-6[1m]", 3},
		{"claude-haiku-4-5-20251001", 1},
		{"claude-mystery-9", 0},
		{"claude-sonnet-4-6", 3},                   // exact
		{"claude-haiku-4-5-20251001[1m]", 1},       // suffix first, then date
		{"claude-sonnet-4-6[200k]", 3},             // any bracket text
		{"claude-sonnet-4-6[]", 3},                 // empty brackets
		{"claude-sonnet-4-6-2025101", 0},           // 7 digits: not a date
		{"claude-sonnet-4-6-202510011", 0},         // 9 digits: "-" is not at the date position
		{"claude-sonnet-4-6_20251001", 0},          // wrong separator
		{"claude-sonnet-4-6-2025100a", 0},          // not all digits
		{"claude-sonnet-4-6-20251001-20251001", 0}, // date stripped once only
		{"claude-sonnet-4-6[1m]x", 0},              // bracket not at the end
		{"claude-sonnet-4-6[1m]]", 0},              // "]" inside the last bracket pair
		{"claude-sonnet-4-6[1m][2m]", 0},           // only the last bracket group goes, once
		{"claude-sonnet-4-6]", 0},                  // no "["
		{"claude-sonnet-4-6[1m-20251001", 0},       // not closed
		{"", 0},
		{"[1m]", 0},
		{"gpt-6.1-sol-20260101", 2},
		{"-20251001", 0}, // cleans to "", which is not a model
	}
	for _, tt := range tests {
		got, ok := Price(tt.model, table)
		if (tt.input != 0) != ok || (ok && got.Input != tt.input) {
			t.Errorf("Price(%q) = %+v, %v; want input %v", tt.model, got, ok, tt.input)
		}
	}
}

// Swift cuts at the last "[" (Pricing.swift cleanName), not where the regex in its comment would
// start matching: "a[b[c]" gives "a[b" in Swift, "a" with /\[[^\]]*\]$/.
func TestCleanNameFollowsSwiftNotItsComment(t *testing.T) {
	for in, want := range map[string]string{
		"a[b[c]":                              "a[b",
		"claude-haiku-4-5-20251001":           "claude-haiku-4-5",
		"x-12345678[tag]":                     "x",
		"x[tag]-12345678":                     "x[tag]",
		"claude-sonnet-4-6[1m][2m]":           "claude-sonnet-4-6[1m]",
		"claude-sonnet-4-6[1m]]":              "claude-sonnet-4-6[1m]]",
		"claude-sonnet-4-6-20251001-20251001": "claude-sonnet-4-6-20251001",
		"claude-sonnet-4-6-202510011":         "claude-sonnet-4-6-202510011",
		"[1m]":                                "",
		"":                                    "",
		"plain":                               "plain",
	} {
		if got := cleanName(in); got != want {
			t.Errorf("cleanName(%q) = %q, want %q", in, got, want)
		}
	}
}

// Swift: ActivityPricingTests.swift "estimate sums per model and says why when it cannot"
func TestEstimateSimple(t *testing.T) {
	table := Models()
	usage := Usage{Input: 1_000_000}
	if got := EstimateCost([]ModelUsage{{"claude-sonnet-4-6[1m]", usage}}, table); got != (Estimate{HasUSD: true, USD: 3}) {
		t.Errorf("sonnet = %+v", got)
	}
	if got := EstimateCost([]ModelUsage{{"claude-mystery-9", usage}}, table); got != (Estimate{Note: `No price for model "claude-mystery-9", so no estimate.`}) {
		t.Errorf("mystery = %+v", got)
	}
	if got := EstimateCost([]ModelUsage{{"claude-sonnet-4-6", Usage{}}}, table); got != (Estimate{Note: "No token usage logged yet."}) {
		t.Errorf("empty = %+v", got)
	}
}

func TestEstimateRules(t *testing.T) {
	table := Models()
	// Models with no tokens are skipped even when they have no price.
	got := EstimateCost([]ModelUsage{{"claude-mystery-9", Usage{}}, {"claude-sonnet-4-6", Usage{Output: 1_000_000}}}, table)
	if got != (Estimate{HasUSD: true, USD: 15}) {
		t.Errorf("skip empty = %+v", got)
	}
	// An unpriced model with tokens ends the estimate, even after priced ones.
	got = EstimateCost([]ModelUsage{{"claude-sonnet-4-6", Usage{Output: 1}}, {"nope", Usage{Input: 1}}}, table)
	if got.HasUSD || got.Note != `No price for model "nope", so no estimate.` {
		t.Errorf("unpriced after priced = %+v", got)
	}
	// Only cacheWriteLong tokens do not count as usage (the Swift token sum leaves it out).
	got = EstimateCost([]ModelUsage{{"claude-sonnet-4-6", Usage{CacheWriteLong: 5}}}, table)
	if got != (Estimate{Note: "No token usage logged yet."}) {
		t.Errorf("long only = %+v", got)
	}
	// The long share is capped by the cache write total: 1M written, 4M "long" bills 1M at the long rate.
	got = EstimateCost([]ModelUsage{{"claude-sonnet-4-6", Usage{CacheWrite: 1_000_000, CacheWriteLong: 4_000_000}}}, table)
	if got != (Estimate{HasUSD: true, USD: 6}) {
		t.Errorf("long cap = %+v", got)
	}
	// Split: 1M written, 250k of it long: 750k * 3.75 + 250k * 6 = 4.3125.
	got = EstimateCost([]ModelUsage{{"claude-sonnet-4-6", Usage{CacheWrite: 1_000_000, CacheWriteLong: 250_000}}}, table)
	if got != (Estimate{HasUSD: true, USD: 4.3125}) {
		t.Errorf("long split = %+v", got)
	}
	if got := EstimateCost(nil, table); got.HasUSD || got.Note != "No token usage logged yet." {
		t.Errorf("nil usage = %+v", got)
	}
}

// Bit patterns below were produced by compiling the Swift expression of Pricing.estimate with
// swiftc -O (rates of claude-sonnet-4-6). The two orders differ in the last bit, so the summation
// order and the absence of fused multiply-add are both pinned.
func TestEstimateBitIdenticalToSwift(t *testing.T) {
	table := Models()
	a := ModelUsage{"claude-sonnet-4-6", Usage{143451, 21151, 51043, 5575, 37881040}}
	b := ModelUsage{"claude-sonnet-4-6", Usage{996426, 71532, 48329, 17689, 66639540}}
	c := ModelUsage{"claude-sonnet-4-6", Usage{877474, 73570, 87033, 27999, 48508753}}
	forward := EstimateCost([]ModelUsage{a, b, c}, table).USD
	reverse := EstimateCost([]ModelUsage{c, b, a}, table).USD
	if got := math.Float64bits(forward); got != 4632975238735604918 {
		t.Errorf("forward bits = %d", got)
	}
	if got := math.Float64bits(reverse); got != 4632975238735604917 {
		t.Errorf("reverse bits = %d", got)
	}
	d := ModelUsage{"claude-sonnet-4-6", Usage{123457, 7891, 33333, 11111, 987654321}}
	e := ModelUsage{"claude-sonnet-4-6", Usage{1, 3, 777, 1000, 12345}}
	f := ModelUsage{"claude-sonnet-4-6", Usage{98765, 4321, 55555, 0, 7}}
	if got := math.Float64bits(EstimateCost([]ModelUsage{d, e, f}, table).USD); got != 4643941518261761115 {
		t.Errorf("second vector bits = %d", got)
	}
}
