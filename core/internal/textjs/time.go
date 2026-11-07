package textjs

import (
	"fmt"
	"math"
	"strconv"
	"strings"
)

const (
	msPerDay = 86_400_000
	// ISO years are four digits (0000 through 9999).
	minTimestampMs = -62_167_219_200_000
	maxTimestampMs = 253_402_300_799_999
	// UnknownDate is what IsoString returns for a timestamp outside the ISO year range.
	UnknownDate = "unknown date"
)

var monthNames = [...]string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

// BoundedTimestamp returns ms when it is finite and inside the four-digit ISO year range.
// Untrusted numbers go through it before integer conversion or arithmetic.
func BoundedTimestamp(ms float64) (float64, bool) {
	if math.IsNaN(ms) || math.IsInf(ms, 0) || ms < minTimestampMs || ms > maxTimestampMs {
		return 0, false
	}
	return ms, true
}

// IsoString is new Date(ms).toISOString(): 2026-11-02T12:00:00.000Z. It returns UnknownDate
// when ms is out of range.
func IsoString(ms float64) string {
	ms, ok := BoundedTimestamp(ms)
	if !ok {
		return UnknownDate
	}
	whole := int64(math.Trunc(ms))
	days := whole / msPerDay
	rest := whole % msPerDay
	if rest < 0 {
		rest += msPerDay
		days--
	}
	year, month, day := civilFromDays(days)
	hour := rest / 3_600_000
	minute := rest % 3_600_000 / 60_000
	second := rest % 60_000 / 1000
	milli := rest % 1000
	return fmt.Sprintf("%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", year, month, day, hour, minute, second, milli)
}

// IsoDay is new Date(ms).toISOString().slice(0, 10). Like the Swift port it slices the
// UnknownDate text too ("unknown da"); callers check BoundedTimestamp first.
func IsoDay(ms float64) string {
	s := IsoString(ms)
	return s[:min(10, len(s))]
}

// civilFromDays converts days since 1970-01-01 to a civil date (proleptic Gregorian).
func civilFromDays(days int64) (year, month, day int64) {
	z := days + 719_468
	era := z / 146_097
	if z < 0 {
		era = (z - 146_096) / 146_097
	}
	doe := z - era*146_097
	yoe := (doe - doe/1460 + doe/36_524 - doe/146_096) / 365
	doy := doe - (365*yoe + yoe/4 - yoe/100)
	mp := (5*doy + 2) / 153
	day = doy - (153*mp+2)/5 + 1
	month = mp - 9
	if mp < 10 {
		month = mp + 3
	}
	year = yoe + era*400
	if month <= 2 {
		year++
	}
	return year, month, day
}

func daysFromCivil(year, month, day int) int64 {
	y := int64(year)
	if month <= 2 {
		y--
	}
	era := y / 400
	if y < 0 {
		era = (y - 399) / 400
	}
	yoe := y - era*400
	m := int64(month)
	shifted := m + 9
	if m > 2 {
		shifted = m - 3
	}
	doy := (153*shifted+2)/5 + int64(day) - 1
	doe := yoe*365 + yoe/4 - yoe/100 + doy
	return era*146_097 + doe - 719_468
}

// timestampScanner reads ASCII digits and fixed bytes from a timestamp.
type timestampScanner struct {
	b []byte
	i int
}

func (p *timestampScanner) digits(count int) (int, bool) {
	if p.i+count > len(p.b) {
		return 0, false
	}
	value := 0
	for k := 0; k < count; k++ {
		c := p.b[p.i+k]
		if c < '0' || c > '9' {
			return 0, false
		}
		value = value*10 + int(c-'0')
	}
	p.i += count
	return value, true
}

func (p *timestampScanner) take(c byte) bool {
	if p.i < len(p.b) && p.b[p.i] == c {
		p.i++
		return true
	}
	return false
}

// ParseTimestamp is Date.parse for the ISO timestamps the CLIs write:
// 2026-11-02T11:00:00.000Z, with or without a fraction, and +hh:mm offsets. A time
// without a zone is read as UTC (JavaScript reads it as local time). ok is false when text does not parse.
func ParseTimestamp(text string) (ms float64, ok bool) {
	p := &timestampScanner{b: []byte(text)}
	year, ok1 := p.digits(4)
	if !ok1 || !p.take('-') {
		return 0, false
	}
	month, ok1 := p.digits(2)
	if !ok1 || !p.take('-') {
		return 0, false
	}
	day, ok1 := p.digits(2)
	if !ok1 || month < 1 || month > 12 || day < 1 || day > 31 {
		return 0, false
	}
	ms = float64(daysFromCivil(year, month, day)) * msPerDay
	if p.i == len(p.b) {
		return ms, true
	}
	if !p.take('T') && !p.take(' ') {
		return 0, false
	}
	hour, ok1 := p.digits(2)
	if !ok1 || !p.take(':') {
		return 0, false
	}
	minute, ok1 := p.digits(2)
	if !ok1 {
		return 0, false
	}
	second := 0
	fraction := 0.0
	if p.take(':') {
		second, ok1 = p.digits(2)
		if !ok1 {
			return 0, false
		}
		if p.take('.') {
			scale := 100.0
			seen := false
			for p.i < len(p.b) && p.b[p.i] >= '0' && p.b[p.i] <= '9' {
				if scale >= 1 {
					fraction += float64(p.b[p.i]-'0') * scale
				}
				scale /= 10
				p.i++
				seen = true
			}
			if !seen {
				return 0, false
			}
		}
	}
	if hour > 24 || minute >= 60 || second >= 60 {
		return 0, false
	}
	ms += float64(hour*3_600_000+minute*60_000+second*1000) + math.Floor(fraction)
	if p.take('Z') {
		return endOfText(p, ms)
	}
	if p.i < len(p.b) && (p.b[p.i] == '+' || p.b[p.i] == '-') {
		sign := 1.0
		if p.b[p.i] == '-' {
			sign = -1
		}
		p.i++
		offsetHour, ok1 := p.digits(2)
		if !ok1 {
			return 0, false
		}
		p.take(':')
		offsetMinute, ok1 := p.digits(2)
		if !ok1 || p.i != len(p.b) {
			return 0, false
		}
		return ms - sign*float64(offsetHour*3_600_000+offsetMinute*60_000), true
	}
	return endOfText(p, ms)
}

// endOfText returns ms only when the scanner has consumed all of the text.
func endOfText(p *timestampScanner, ms float64) (float64, bool) {
	if p.i != len(p.b) {
		return 0, false
	}
	return ms, true
}

// ParseProcessStart is Date.parse(`${text} UTC`) for a `ps -o lstart=` value such as
// "Mon Nov  2 11:58:00 2026" (printed with TZ=UTC). Swift took an optional String; callers
// with no value skip the call.
func ParseProcessStart(text string) (float64, bool) {
	parts := strings.FieldsFunc(text, func(r rune) bool { return r == ' ' || r == '\t' })
	if len(parts) != 5 {
		return 0, false
	}
	month := -1
	for i, name := range monthNames {
		if name == parts[1] {
			month = i
			break
		}
	}
	day, dayErr := strconv.Atoi(parts[2])
	year, yearErr := strconv.Atoi(parts[4])
	if month < 0 || dayErr != nil || yearErr != nil || day < 1 || day > 31 || year < 0 || year > 9999 {
		return 0, false
	}
	clockParts := strings.Split(parts[3], ":")
	if len(clockParts) != 3 {
		return 0, false
	}
	var clock [3]int
	for i, part := range clockParts {
		v, err := strconv.Atoi(part)
		if err != nil {
			return 0, false
		}
		clock[i] = v
	}
	if clock[0] < 0 || clock[0] > 23 || clock[1] < 0 || clock[1] > 59 || clock[2] < 0 || clock[2] > 59 {
		return 0, false
	}
	ms := float64(daysFromCivil(year, month+1, day))*msPerDay + float64(clock[0]*3_600_000+clock[1]*60_000+clock[2]*1000)
	if ms == 0 {
		return 0, false
	}
	return BoundedTimestamp(ms)
}
