// Package redact masks recognisable credentials in the command lines the core reports (failed commands, running-tool
// targets, hook commands). It is best effort: a credential of a shape not listed here still shows.
//
// Apply it only at the wire projection. Hashes, keys and every write path keep the raw text, because writes re-read
// hooks and match them by their command text.
package redact

import (
	"regexp"
	"strings"
)

// Mark replaces a masked value.
const Mark = "•••"

// rule is a pattern with three groups: the text kept before the value, the value, and the text kept after it.
type rule struct{ re *regexp.Regexp }

// A value is quoted (the quotes go with it) or a run that stops at white space and quotes.
const value = `"[^"]*"|'[^']*'|[^\s"'` + "`" + `]+`

var rules = []rule{
	// Authorization: <scheme> <value>, also as a JSON or shell assignment.
	{regexp.MustCompile(`(?i)(\bauthorization["']?\s*[:=]\s*["']?(?:[a-z][a-z0-9._-]*\s+)?)([^\s"'` + "`" + `]+)()`)},
	// A bare Bearer <value>.
	{regexp.MustCompile(`(\b[Bb]earer\s+)([A-Za-z0-9._~+/=-]{6,})()`)},
	// --token x, --password=x and the like; a value that starts with - is the next flag.
	{regexp.MustCompile(`(?i)((?:^|\s)--(?:token|password|passwd|secret|api-key|apikey|access-token|auth)(?:=|\s+))("[^"]*"|'[^']*'|[^\s"'` + "`" + `-][^\s"'` + "`" + `]*)()`)},
	// curl -u user:pass and --user user:pass; the user name stays.
	{regexp.MustCompile(`(\bcurl\b[^|;&\n]*?\s(?:-u|--user)(?:=|\s+)["']?[^\s"':]*:)([^\s"']+)()`)},
	// NAME=value where the environment-style NAME holds a secret word.
	{regexp.MustCompile(`((?:^|[^A-Za-z0-9_])[A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH)[A-Z0-9_]*=)(` + value + `)()`)},
	// scheme://user:password@host
	{regexp.MustCompile(userinfo)},
	// Token prefixes, so a pasted key is masked wherever it sits.
	{regexp.MustCompile(`()(\bsk-[A-Za-z0-9_-]{16,}|\bgh[pos]_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}|\bxox[abpr]-[A-Za-z0-9-]{10,}|\bAKIA[0-9A-Z]{16}\b|\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,})()`)},
}

const userinfo = `(\b[A-Za-z][A-Za-z0-9+.-]*://[^\s/@:"']+:)([^\s/"']+)(@)`

var userinfoRule = rule{regexp.MustCompile(userinfo)}

// Command masks the credentials in a command line or a line of error output.
func Command(text string) string {
	for _, r := range rules {
		text = r.apply(text)
	}
	return text
}

// Userinfo masks only the password of scheme://user:password@host, for a setting value that is not a command.
func Userinfo(text string) string { return userinfoRule.apply(text) }

func (r rule) apply(text string) string {
	if text == "" {
		return text
	}
	matches := r.re.FindAllStringSubmatchIndex(text, -1)
	if matches == nil {
		return text
	}
	var b strings.Builder
	last := 0
	for _, m := range matches {
		v := text[m[4]:m[5]]
		// A shell variable reference holds no secret, and a mark is already masked.
		if strings.HasPrefix(v, "$") || v == Mark {
			continue
		}
		b.WriteString(text[last:m[4]])
		b.WriteString(Mark)
		last = m[5]
	}
	b.WriteString(text[last:])
	return b.String()
}
