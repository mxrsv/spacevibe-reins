package textjs

// The character sets of ICU (NSRegularExpression), spelled out for Go regexp (RE2) class syntax. The Swift
// patterns ran on ICU, where \s is the Unicode White_Space set and `.` and `$` know the line terminators. Packages
// that port such a pattern build it from these two constants so the sets exist once.
const (
	// ICUSpaceSet is the inside of a class for ICU's \s: \t \n \v \f \r, space, U+0085, U+00A0, U+1680,
	// U+2000..U+200A, U+2028, U+2029, U+202F, U+205F, U+3000 (not U+FEFF).
	ICUSpaceSet = `\t\n\x0B\x0C\r \x{85}\x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}`
	// ICUTermSet is the inside of a class for the line terminators ICU's `.` stops at and `$` accepts before the
	// end: \n \v \f \r, U+0085, U+2028, U+2029 (\r\n counts as one).
	ICUTermSet = `\n\x0B\x0C\r\x{85}\x{2028}\x{2029}`
)
