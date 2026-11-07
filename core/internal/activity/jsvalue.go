package activity

import (
	"math"
	"strconv"

	"spacevibe.dev/core/internal/ojson"
)

// jv is a JSON value read the way the Swift fold read it: a missing key and JSON null are the same (what `??`
// treats as nullish), and every accessor on an absent value answers "not there".
type jv struct {
	v  ojson.Value
	ok bool
}

func present(v ojson.Value) jv { return jv{v: v, ok: true} }

// field is the member, or absent when the key is missing or null. With duplicate keys the last wins.
func (j jv) field(key string) jv {
	if !j.ok {
		return jv{}
	}
	m, found := j.v.Member(key)
	if !found || m.Kind() == ojson.KindNull {
		return jv{}
	}
	return present(m)
}

func (j jv) str() (string, bool) {
	if !j.ok {
		return "", false
	}
	return j.v.StringValue()
}

func (j jv) boolean() (bool, bool) {
	if !j.ok {
		return false, false
	}
	return j.v.BoolValue()
}

func (j jv) array() ([]ojson.Value, bool) {
	if !j.ok {
		return nil, false
	}
	return j.v.ArrayValue()
}

func (j jv) object() ([]ojson.Member, bool) {
	if !j.ok {
		return nil, false
	}
	return j.v.ObjectValue()
}

// number is a JSON number as a Double. A number too big for a Double is +-Inf, as Double("1e309") is in Swift.
func (j jv) number() (float64, bool) {
	if !j.ok {
		return 0, false
	}
	text, isNumber := j.v.NumberText()
	if !isNumber {
		return 0, false
	}
	f, err := strconv.ParseFloat(text, 64)
	if err != nil && !isRangeError(err) {
		return 0, false
	}
	return f, true
}

func isRangeError(err error) bool {
	ne, ok := err.(*strconv.NumError)
	return ok && ne.Err == strconv.ErrRange
}

// integer is Number.isInteger with a safe range.
func (j jv) integer() (int, bool) {
	d, ok := j.number()
	if !ok || math.IsInf(d, 0) || math.IsNaN(d) || d != math.Round(d) || math.Abs(d) >= 9e15 {
		return 0, false
	}
	return int(d), true
}

// truthy is JavaScript truthiness.
func (j jv) truthy() bool {
	if !j.ok {
		return false
	}
	switch j.v.Kind() {
	case ojson.KindNull:
		return false
	case ojson.KindBool:
		b, _ := j.v.BoolValue()
		return b
	case ojson.KindNumber:
		if d, ok := j.number(); ok {
			return d != 0 && !math.IsNaN(d)
		}
		return true
	case ojson.KindString:
		s, _ := j.v.StringValue()
		return s != ""
	}
	return true
}

// tokenCount is a non-negative finite number, else 0.
func tokenCount(j jv) float64 {
	if d, ok := j.number(); ok && !math.IsInf(d, 0) && !math.IsNaN(d) && d >= 0 {
		return d
	}
	return 0
}

func optional[T any](v T, ok bool) *T {
	if !ok {
		return nil
	}
	return &v
}
