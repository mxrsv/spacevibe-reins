package ojson

import (
	"errors"
	"strconv"
)

// Errors never carry file content, key names or values, so they are safe to log and show (S-R3).
var (
	// ErrInvalidUTF8 means the bytes are not valid UTF-8.
	ErrInvalidUTF8 = errors.New("the JSON file is not valid UTF-8")
	// ErrTooDeep means arrays or objects nest deeper than MaxDepth.
	ErrTooDeep = errors.New("the JSON file nests too deeply")
	// ErrPathNotFound means an edit named a key or index that does not exist.
	ErrPathNotFound = errors.New("the JSON path does not exist")
	// ErrTypeMismatch means an edit walked through, or onto, a value of the wrong kind (a key on an array,
	// an append to a string).
	ErrTypeMismatch = errors.New("the JSON path crosses a value of the wrong kind")
	// ErrInvalidValue means a value cannot be written, such as a number whose text is not a JSON number.
	ErrInvalidValue = errors.New("the JSON value cannot be written")
)

// Problem names what is wrong at a syntax error position. The names match the Swift OrderedJSONError.Problem
// raw values.
type Problem string

// The syntax problems the parser reports.
const (
	UnexpectedEnd            Problem = "unexpectedEnd"
	UnexpectedCharacter      Problem = "unexpectedCharacter"
	InvalidNumber            Problem = "invalidNumber"
	InvalidEscape            Problem = "invalidEscape"
	ControlCharacterInString Problem = "controlCharacterInString"
	ExpectedColon            Problem = "expectedColon"
	ExpectedCommaOrEnd       Problem = "expectedCommaOrEnd"
	ExpectedKey              Problem = "expectedKey"
	TrailingContent          Problem = "trailingContent"
)

// SyntaxError is a JSON syntax error with a 1-based line and a 1-based byte column. It names the problem
// and the position only.
type SyntaxError struct {
	Problem Problem
	Line    int
	Column  int
}

func (e *SyntaxError) Error() string {
	return "the JSON file is not valid: " + string(e.Problem) + " at line " + strconv.Itoa(e.Line) +
		", column " + strconv.Itoa(e.Column)
}
