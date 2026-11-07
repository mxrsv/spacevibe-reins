package goldentest

import (
	"errors"
	"math"
	"strconv"
	"strings"
)

// es6Number is Number.prototype.toString(10) for a finite float64, which is the text JSON.stringify writes
// (ECMA-262 Number::toString). Go's shortest round-trip digits are the same digits JavaScript picks; only the
// layout differs: no exponent from 1e-6 up to (not including) 1e21, and "e+21" style exponents beyond.
func es6Number(f float64) (string, error) {
	if math.IsNaN(f) || math.IsInf(f, 0) {
		return "", errors.New("a JSON number must be finite")
	}
	if f == 0 {
		return "0", nil // also -0, as in JavaScript
	}
	sign := ""
	if f < 0 {
		sign, f = "-", -f
	}
	// 'e' with precision -1 gives the shortest digits as d.ddde±XX.
	text := strconv.FormatFloat(f, 'e', -1, 64)
	mantissa, expText, _ := strings.Cut(text, "e")
	exp, _ := strconv.Atoi(expText)
	digits := strings.Replace(mantissa, ".", "", 1)
	k, n := len(digits), exp+1 // value = 0.digits * 10^n
	switch {
	case k <= n && n <= 21:
		return sign + digits + strings.Repeat("0", n-k), nil
	case 0 < n && n <= 21:
		return sign + digits[:n] + "." + digits[n:], nil
	case -6 < n && n <= 0:
		return sign + "0." + strings.Repeat("0", -n) + digits, nil
	}
	e := n - 1
	expSign := "+"
	if e < 0 {
		expSign, e = "-", -e
	}
	if k == 1 {
		return sign + digits + "e" + expSign + strconv.Itoa(e), nil
	}
	return sign + digits[:1] + "." + digits[1:] + "e" + expSign + strconv.Itoa(e), nil
}
