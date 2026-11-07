package textjs

import (
	"math"
	"testing"
)

const activityNowMs = 1_793_620_800_000.0 // 2026-11-02T12:00:00Z

func TestIsoString(t *testing.T) {
	cases := []struct {
		name string
		ms   float64
		want string
	}{
		// Swift: ActivityTests.swift "text helpers behave like the JavaScript they replace"
		{"swift now plus ms", 1_793_620_800_123, "2026-11-02T12:00:00.123Z"},
		// Swift: ActivitySafetyTests.swift "time conversion rejects non-finite and out-of-domain inputs before integer arithmetic"
		{"epoch", 0, "1970-01-01T00:00:00.000Z"},
		{"min", -62_167_219_200_000, "0000-01-01T00:00:00.000Z"},
		{"max", 253_402_300_799_999, "9999-12-31T23:59:59.999Z"},
		{"NaN", math.NaN(), "unknown date"},
		{"+Inf", math.Inf(1), "unknown date"},
		{"-Inf", math.Inf(-1), "unknown date"},
		{"max float", math.MaxFloat64, "unknown date"},
		{"-max float", -math.MaxFloat64, "unknown date"},
		{"Int64.max", float64(math.MaxInt64), "unknown date"},
		// Extra vectors, expected values from the Swift implementation.
		{"-1", -1, "1969-12-31T23:59:59.999Z"},
		{"-1000", -1000, "1969-12-31T23:59:59.000Z"},
		{"-1 day", -86_400_000, "1969-12-31T00:00:00.000Z"},
		{"-1 day -1 ms", -86_400_001, "1969-12-30T23:59:59.999Z"},
		{"1.9 truncates", 1.9, "1970-01-01T00:00:00.001Z"},
		{"-1.9 truncates toward zero", -1.9, "1969-12-31T23:59:59.999Z"},
		{"leap day 2000", 951_782_400_000, "2000-02-29T00:00:00.000Z"},
		{"leap day 2024", 1_709_164_800_000, "2024-02-29T00:00:00.000Z"},
		{"year 1", -62_135_596_800_000, "0001-01-01T00:00:00.000Z"},
		{"below min", -62_167_219_200_001, "unknown date"},
		{"above max", 253_402_300_800_000, "unknown date"},
		{"2100", 4_102_444_800_000, "2100-01-01T00:00:00.000Z"},
		{"1900", -2_208_988_800_000, "1900-01-01T00:00:00.000Z"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := IsoString(c.ms); got != c.want {
				t.Errorf("IsoString(%v) = %q, want %q", c.ms, got, c.want)
			}
		})
	}
}

func TestIsoDay(t *testing.T) {
	cases := []struct {
		ms   float64
		want string
	}{
		{-1, "1969-12-31"},
		{activityNowMs, "2026-11-02"},
		{-86_400_001, "1969-12-30"},
		{math.NaN(), "unknown da"}, // as in Swift: slices "unknown date"
	}
	for _, c := range cases {
		if got := IsoDay(c.ms); got != c.want {
			t.Errorf("IsoDay(%v) = %q, want %q", c.ms, got, c.want)
		}
	}
}

func TestBoundedTimestamp(t *testing.T) {
	for _, ms := range []float64{0, -62_167_219_200_000, 253_402_300_799_999, 1.5} {
		if got, ok := BoundedTimestamp(ms); !ok || got != ms {
			t.Errorf("BoundedTimestamp(%v) = %v, %v", ms, got, ok)
		}
	}
	for _, ms := range []float64{math.NaN(), math.Inf(1), math.Inf(-1), -62_167_219_200_001, 253_402_300_800_000, 1e30} {
		if _, ok := BoundedTimestamp(ms); ok {
			t.Errorf("BoundedTimestamp(%v) should be rejected", ms)
		}
	}
}

func TestParseTimestamp(t *testing.T) {
	cases := []struct {
		name, in string
		want     float64
		ok       bool
	}{
		// Swift: ActivityTests.swift "text helpers behave like the JavaScript they replace"
		{"swift Z with fraction", "2026-11-02T12:00:00.123Z", 1_793_620_800_123, true},
		{"swift offset", "2026-11-02T14:00:00+02:00", 1_793_620_800_000, true},
		// Extra vectors, expected values from the Swift implementation.
		{"date only", "2026-11-02", 1_793_577_600_000, true},
		{"Z", "2026-11-02T12:00:00Z", 1_793_620_800_000, true},
		{"space separator, no seconds, no zone", "2026-11-02 12:00", 1_793_620_800_000, true},
		{"hour 24", "2026-11-02T24:00:00Z", 1_793_664_000_000, true},
		{"fraction digits past ms are dropped", "2026-11-02T12:00:00.1234Z", 1_793_620_800_123, true},
		{"fraction without zone", "2026-11-02T12:00:00.5", 1_793_620_800_500, true},
		{"fraction 999999", "2026-11-02T12:00:00.999999Z", 1_793_620_800_999, true},
		{"empty fraction", "2026-11-02T12:00:00.", 0, false},
		{"negative offset", "2026-11-02T12:00-05:30", 1_793_640_600_000, true},
		{"offset without colon", "2026-11-02T12:00:00+0530", 1_793_601_000_000, true},
		{"short offset", "2026-11-02T12:00:00+05", 0, false},
		{"month 13", "2026-13-02", 0, false},
		{"Feb 31 rolls", "2026-02-31", 1_772_496_000_000, true},
		{"year 0", "0000-01-01", -62_167_219_200_000, true},
		{"year 1", "0001-01-01T00:00:00Z", -62_135_596_800_000, true},
		{"1900-03-01", "1900-03-01T00:00:00Z", -2_203_891_200_000, true},
		{"just before epoch", "1969-12-31T23:59:59.999Z", -1, true},
		{"trailing after Z", "2026-11-02T12:00:00Zx", 0, false},
		{"trailing after date", "2026-11-02x", 0, false},
		{"minute 60", "2026-11-02T12:60", 0, false},
		{"empty", "", 0, false},
		{"non-ASCII digit", "2026-11-0٢", 0, false},
		{"astral junk", "\U0001F600", 0, false},
		{"BOM prefix", "\uFEFF2026-11-02", 0, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, ok := ParseTimestamp(c.in)
			if ok != c.ok || got != c.want {
				t.Errorf("ParseTimestamp(%q) = %v, %v; want %v, %v", c.in, got, ok, c.want, c.ok)
			}
		})
	}
}

func TestParseProcessStart(t *testing.T) {
	cases := []struct {
		name, in string
		want     float64
		ok       bool
	}{
		// Swift: ActivityTests.swift "text helpers behave like the JavaScript they replace"
		{"swift now minus 2 min", "Mon Nov  2 11:58:00 2026", 1_793_620_680_000, true},
		{"swift garbage", "garbage", 0, false},
		// Swift: ActivitySafetyTests.swift "time conversion rejects non-finite and out-of-domain inputs before integer arithmetic"
		{"swift huge hour", "Mon Nov 2 9223372036854775807:00:00 2026", 0, false},
		{"swift Int.min year", "Mon Nov 2 11:00:00 -9223372036854775808", 0, false},
		{"swift hour 25", "Mon Nov 2 25:00:00 2026", 0, false},
		{"swift four clock parts", "Mon Nov 2 11:no:00:00 2026", 0, false},
		{"swift originalStart", "Mon Nov  2 11:00:00 2026", activityNowMs - 3_600_000, true},
		// Extra vectors, expected values from the Swift implementation.
		{"epoch is rejected (ms == 0)", "Thu Jan  1 00:00:00 1970", 0, false},
		{"plus signs in day and year", "Mon Nov +2 11:58:00 +2026", 1_793_620_680_000, true},
		{"year -0", "Mon Nov 2 11:58:00 -0", -62_140_737_720_000, true},
		{"plus signs in clock", "Mon Nov 2 +1:+5:+0 2026", 1_793_581_500_000, true},
		{"minus zero hour", "Mon Nov 2 -0:00:00 2026", 1_793_577_600_000, true},
		{"two clock parts", "Mon Nov 2 11:58 2026", 0, false},
		{"day 0", "Mon Nov 0 11:58:00 2026", 0, false},
		{"day 32", "Mon Nov 32 11:58:00 2026", 0, false},
		{"unknown month", "Mon Xxx 2 11:58:00 2026", 0, false},
		{"tabs separate fields", "Mon\tNov\t2\t11:58:00\t2026", 1_793_620_680_000, true},
		{"empty clock part", "Mon Nov 2 11::00 2026", 0, false},
		{"max year", "Mon Dec 31 23:59:59 9999", 253_402_300_799_000, true},
		{"year 0", "Mon Jan 1 00:00:00 0000", -62_167_219_200_000, true},
		{"year 10000", "Mon Jan 1 00:00:00 10000", 0, false},
		{"empty", "", 0, false},
		{"non-ASCII digit day", "Mon Nov ٢ 11:58:00 2026", 0, false},
		{"U+00A0 is not a separator", "Mon Nov 2 11:58:00 2026", 0, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, ok := ParseProcessStart(c.in)
			if ok != c.ok || got != c.want {
				t.Errorf("ParseProcessStart(%q) = %v, %v; want %v, %v", c.in, got, ok, c.want, c.ok)
			}
		})
	}
}
