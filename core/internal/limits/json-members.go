package limits

import (
	"math"
	"strconv"

	"spacevibe.dev/core/internal/ojson"
)

// member is the value for a key, or false for a missing key, JSON null, or a value that is not an object
// (limitsMember in Swift). With duplicate keys the last wins.
func member(v ojson.Value, key string) (ojson.Value, bool) {
	value, ok := v.Member(key)
	if !ok || value.Kind() == ojson.KindNull {
		return ojson.Value{}, false
	}
	return value, true
}

func memberString(v ojson.Value, key string) (string, bool) {
	value, ok := member(v, key)
	if !ok {
		return "", false
	}
	return value.StringValue()
}

func memberNumber(v ojson.Value, key string) (float64, bool) {
	value, ok := member(v, key)
	if !ok {
		return 0, false
	}
	return number(value)
}

// number is a JSON number as a finite float, false for anything else (limitsNumber in Swift).
func number(v ojson.Value) (float64, bool) {
	text, ok := v.NumberText()
	if !ok {
		return 0, false
	}
	f, err := strconv.ParseFloat(text, 64)
	if err != nil || math.IsInf(f, 0) || math.IsNaN(f) {
		return 0, false
	}
	return f, true
}
