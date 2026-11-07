// Package pricing is the estimate-only model price table and the cost estimate built on it.
// Ported from Sources/ReinsCore/Pricing.swift.
//
// Unlike Swift, where the table is a literal that a test compares with pricing.json, the Go table
// IS the embedded pricing.json. Prices are USD per million tokens (standard API-equivalent, not
// what a subscription costs). A model with no price has no estimate; it is never guessed.
package pricing

import (
	_ "embed"
	"encoding/json"
	"math"
	"sync"

	"spacevibe.dev/core/internal/coreerr"
)

//go:embed pricing.json
var embedded []byte

// ModelPrice is the price of one model in USD per million tokens.
type ModelPrice struct {
	Input          float64
	Output         float64
	CacheWrite     float64
	CacheWriteLong float64
	CacheRead      float64
}

// Table maps a model name, as logged after cleaning, to its price.
type Table map[string]ModelPrice

// Load parses a pricing.json document. Every model needs all five rates; the source and fetchedAt
// fields are ignored, like Swift. Errors are fixed sentences and never quote the data.
func Load(data []byte) (Table, error) {
	var doc struct {
		Models map[string]struct {
			Input          *float64 `json:"input"`
			Output         *float64 `json:"output"`
			CacheWrite     *float64 `json:"cacheWrite"`
			CacheWriteLong *float64 `json:"cacheWriteLong"`
			CacheRead      *float64 `json:"cacheRead"`
		} `json:"models"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, coreerr.NewStatus("The price table is not valid JSON.", coreerr.StatusInternalFailure)
	}
	if len(doc.Models) == 0 {
		return nil, coreerr.NewStatus("The price table has no models.", coreerr.StatusInternalFailure)
	}
	table := make(Table, len(doc.Models))
	for name, row := range doc.Models {
		rates := []*float64{row.Input, row.Output, row.CacheWrite, row.CacheWriteLong, row.CacheRead}
		for _, rate := range rates {
			if rate == nil || *rate < 0 || math.IsInf(*rate, 0) {
				return nil, coreerr.NewStatus("A model in the price table has a missing or invalid rate.", coreerr.StatusInternalFailure)
			}
		}
		table[name] = ModelPrice{Input: *row.Input, Output: *row.Output, CacheWrite: *row.CacheWrite, CacheWriteLong: *row.CacheWriteLong, CacheRead: *row.CacheRead}
	}
	return table, nil
}

// Models returns the embedded table (Swift Pricing.models). The embedded file is checked by tests,
// so an invalid one is a build defect and panics. Callers must not modify the returned map.
func Models() Table { return defaultTable() }

var defaultTable = sync.OnceValue(func() Table {
	table, err := Load(embedded)
	if err != nil {
		panic(err)
	}
	return table
})

// Price returns the price for a model name as logged: exact match first, then without a trailing
// "[1m]"-style suffix and a "-YYYYMMDD" date (Swift Pricing.price(for:in:)).
func Price(model string, table Table) (ModelPrice, bool) {
	if exact, ok := table[model]; ok {
		return exact, true
	}
	price, ok := table[cleanName(model)]
	return price, ok
}

// cleanName ports Pricing.cleanName. The bracket rule follows the Swift code, not its regex comment:
// it cuts at the LAST "[" when no "]" sits between that "[" and the final "]".
func cleanName(model string) string {
	name := model
	if n := len(name); n > 0 && name[n-1] == ']' {
		open := -1
		for i := n - 1; i >= 0; i-- {
			if name[i] == '[' {
				open = i
				break
			}
		}
		if open >= 0 && !containsByte(name[open+1:n-1], ']') {
			name = name[:open]
		}
	}
	if n := len(name); n >= 9 && name[n-9] == '-' {
		digits := true
		for i := n - 8; i < n; i++ {
			if name[i] < '0' || name[i] > '9' {
				digits = false
				break
			}
		}
		if digits {
			name = name[:n-9]
		}
	}
	return name
}

func containsByte(s string, b byte) bool {
	for i := 0; i < len(s); i++ {
		if s[i] == b {
			return true
		}
	}
	return false
}

// Usage is the token counts of one model, as the log folding sums them. They are float64 like Swift.
type Usage struct {
	Input          float64
	Output         float64
	CacheWrite     float64
	CacheWriteLong float64
	CacheRead      float64
}

// ModelUsage is one model with its usage. Estimate takes a slice, never a map, to keep the order.
type ModelUsage struct {
	Model string
	Usage Usage
}

// Estimate is either a USD amount (HasUSD) or a note saying why there is none.
type Estimate struct {
	HasUSD bool
	USD    float64
	Note   string
}

const noUsageNote = "No token usage logged yet."

// EstimateCost sums the models in the order given: floating point addition is not associative and
// the golden compares exact values. Each product is wrapped in float64() so that no architecture
// fuses a multiply with the following add (Go's spec allows FMA on arm64; Swift does not fuse).
func EstimateCost(usage []ModelUsage, table Table) Estimate {
	usd := 0.0
	priced := false
	for _, mu := range usage {
		m := mu.Usage
		tokens := m.Input + m.Output + m.CacheWrite + m.CacheRead
		if tokens == 0 {
			continue
		}
		rate, ok := Price(mu.Model, table)
		if !ok {
			return Estimate{Note: "No price for model \"" + mu.Model + "\", so no estimate."}
		}
		long := min(m.CacheWrite, m.CacheWriteLong)
		sum := float64(m.Input*rate.Input) + float64(m.Output*rate.Output) + float64(m.CacheRead*rate.CacheRead)
		sum = sum + float64((m.CacheWrite-long)*rate.CacheWrite) + float64(long*rate.CacheWriteLong)
		usd += sum / 1_000_000
		priced = true
	}
	if priced {
		return Estimate{HasUSD: true, USD: usd}
	}
	return Estimate{Note: noUsageNote}
}
