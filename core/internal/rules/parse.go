package rules

import (
	"regexp"
	"strings"
	"unicode"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/textjs"
)

// MaxRuleLength is the longest rule text, in UTF-16 units.
const MaxRuleLength = 1000

// Fixed sentences of rule input checks (also the answers of Check).
const (
	enterRuleMessage   = "Enter a rule such as Bash(npm test *)."
	invalidRuleMessage = "That is not a valid rule. Use Tool or Tool(pattern) on one line."
)

// ParseRule reads Tool or Tool(specifier). It is false when the text is neither. The tool name is
// [A-Za-z][A-Za-z0-9_.-]*, and the specifier is everything between the first "(" and the final ")" (RulesParse.swift).
func ParseRule(rule string) (ParsedRule, bool) {
	scalars := []rune(textjs.Trim(rule))
	if len(scalars) == 0 || !isASCIILetter(scalars[0]) {
		return ParsedRule{}, false
	}
	i := 1
	for i < len(scalars) && (isASCIILetter(scalars[i]) || isASCIIDigit(scalars[i]) || strings.ContainsRune("_.-", scalars[i])) {
		i++
	}
	tool := string(scalars[:i])
	if i == len(scalars) {
		return ParsedRule{Tool: tool}, true
	}
	if scalars[i] != '(' || scalars[len(scalars)-1] != ')' || len(scalars)-1 <= i {
		return ParsedRule{}, false
	}
	specifier := string(scalars[i+1 : len(scalars)-1])
	if textjs.Trim(specifier) == "" {
		return ParsedRule{Tool: tool}, true
	}
	return ParsedRule{Tool: tool, Specifier: &specifier}, true
}

// checkedRule is the rule text a caller may add: trimmed, one line, at most 1000 UTF-16 units, and a valid rule.
func checkedRule(rule string) (string, error) {
	text := textjs.Trim(rule)
	if text == "" {
		return "", coreerr.New(enterRuleMessage)
	}
	if textjs.UTF16Length(text) > MaxRuleLength || strings.ContainsAny(text, "\n\r") {
		return "", coreerr.New(invalidRuleMessage)
	}
	if _, ok := ParseRule(text); !ok {
		return "", coreerr.New(invalidRuleMessage)
	}
	return text, nil
}

// Check is the live check of RulesScopes.shapeError: "" when the text is a rule worth sending, otherwise the sentence
// to show. The engine stays the authority (it also refuses a duplicate). It differs from the write's check on purpose,
// as in Swift: it trims Foundation's whitespacesAndNewlines (U+0085 yes, U+FEFF no) and counts every Unicode newline
// (\v, \f, U+0085, U+2028, U+2029) as one, where the write only refuses \n and \r.
func Check(rule string) string {
	trimmed := strings.TrimFunc(textjs.Repair(rule), isFoundationSpace)
	if trimmed == "" {
		return enterRuleMessage
	}
	if textjs.UTF16Length(trimmed) > MaxRuleLength || strings.ContainsFunc(trimmed, isNewline) {
		return invalidRuleMessage
	}
	if _, ok := ParseRule(trimmed); !ok {
		return invalidRuleMessage
	}
	return ""
}

// isFoundationSpace is CharacterSet.whitespacesAndNewlines: Zs, U+0009, U+000A to U+000D, U+0085, U+2028, U+2029.
func isFoundationSpace(r rune) bool {
	switch {
	case r >= 0x09 && r <= 0x0D, r == 0x85, r == 0x2028, r == 0x2029:
		return true
	}
	return unicode.Is(unicode.Zs, r)
}

// isNewline is Character.isNewline for one scalar.
func isNewline(r rune) bool {
	return (r >= 0x0A && r <= 0x0D) || r == 0x85 || r == 0x2028 || r == 0x2029
}

func isASCIILetter(r rune) bool { return (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') }
func isASCIIDigit(r rune) bool  { return r >= '0' && r <= '9' }

// isWide is a bare Tool, Tool() or Tool(*): the rule covers every use of the tool.
func isWide(rule ParsedRule) bool {
	return rule.Specifier == nil || textjs.Trim(*rule.Specifier) == "*"
}

// namesEnvFile: the specifier names a .env file, that is ".env" at the start or right after a "/" or "*". Tested on
// the untrimmed specifier.
func namesEnvFile(specifier string) bool {
	const needle = ".env"
	for start := 0; start+len(needle) <= len(specifier); start++ {
		if specifier[start:start+len(needle)] != needle {
			continue
		}
		if start == 0 || specifier[start-1] == '/' || specifier[start-1] == '*' {
			return true
		}
	}
	return false
}

// jsSpace is JavaScript's \s written out for RE2. Go's \s lacks \v and U+FEFF.
const jsSpace = `[\t\n\x0B\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]`

// The ICU boundary of RulesParse.swift is (?<=[A-Za-z0-9_])(?![A-Za-z0-9_])|(?<![A-Za-z0-9_])(?=[A-Za-z0-9_]), which
// is ASCII word boundary, so RE2's \b (ASCII only) says the same, and the same as JavaScript's \b.
var pushPattern = func() *regexp.Regexp {
	s := jsSpace + "+"
	prefixes := []string{
		"git" + s + "push", "vercel", "netlify", "firebase" + s + "deploy", "fly" + s + "deploy", "wrangler" + s + "(?:deploy|publish)",
		"(?:npm|pnpm|yarn)" + s + "publish", "docker" + s + "push", "gh" + s + "release", "gh" + s + "pr" + s + "merge",
	}
	return regexp.MustCompile(`^(?:` + strings.Join(prefixes, "|") + `)\b|\bdeploy\b`)
}()

// looksLikePushOrDeploy: a command that pushes or deploys: starts with a push or deploy prefix, or has the word
// "deploy" anywhere.
func looksLikePushOrDeploy(command string) bool { return pushPattern.MatchString(textjs.Trim(command)) }

// jsTrimStart is String.prototype.trimStart.
func jsTrimStart(text string) string {
	return strings.TrimLeftFunc(textjs.Repair(text), textjs.IsJSSpace)
}
